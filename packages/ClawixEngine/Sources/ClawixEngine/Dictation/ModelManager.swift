#if canImport(WhisperKit)
import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
import WhisperKit

/// Tracks which dictation models are downloaded and which one is the
/// active choice. Owned by the macOS GUI (`AppState`) so the Settings
/// page can bind to download progress and switch the active model
/// reactively. The daemon reads `activeModel` directly to know which
/// variant to ask `TranscriptionService` for when an iPhone request
/// lands.
@MainActor
public final class DictationModelManager: ObservableObject {

    /// Persisted choice of active model. Stored in UserDefaults so the
    /// GUI and the LaunchAgent daemon agree on which variant to load.
    public static let activeModelDefaultsKey = ClawixPersistentSurfaceKeys.dictationActiveModel

    /// Posted by `TranscriptionService` (or anything else that wipes a
    /// broken install) so every `DictationModelManager` instance —
    /// there's typically one in the GUI and one in the daemon — drops
    /// the broken model from `installedModels`. The notification's
    /// object is the `DictationModel.rawValue` string so observers can
    /// surface a targeted "re-download needed" error in Settings.
    public static let modelInvalidatedNotification = Notification.Name("DictationModelInvalidated")

    @Published public private(set) var activeModel: DictationModel
    @Published public private(set) var downloadProgress: [DictationModel: Double] = [:]
    @Published public private(set) var installedModels: Set<DictationModel> = []
    @Published public private(set) var downloadErrors: [DictationModel: String] = [:]
    /// Variants currently being removed from disk. Settings binds to
    /// this so the row can swap the Delete button for an inline spinner
    /// while the (potentially multi-GB) directory tree is unlinked off
    /// the main actor.
    @Published public private(set) var deletingModels: Set<DictationModel> = []

    public var lastError: String? { downloadErrors.values.first }

    private let defaults: UserDefaults
    /// Per-model in-flight download task. Stored so the user can cancel
    /// from the Settings row; `nil` means no download is running for
    /// that model.
    private var inFlight: [DictationModel: Task<Void, Never>] = [:]
    private var invalidationObserver: NSObjectProtocol?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.activeModelDefaultsKey),
           let parsed = DictationModel(rawValue: raw) {
            self.activeModel = parsed
        } else {
            self.activeModel = .default
        }
        refreshInstalled()
        invalidationObserver = NotificationCenter.default.addObserver(
            forName: Self.modelInvalidatedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                self.refreshInstalled()
                if let raw = note.object as? String,
                   let model = DictationModel(rawValue: raw) {
                    self.downloadProgress[model] = nil
                    self.downloadErrors[model] = "Previous \(model.displayName) download was incomplete. Tap Download to retry."
                }
            }
        }
    }

    deinit {
        if let invalidationObserver {
            NotificationCenter.default.removeObserver(invalidationObserver)
        }
    }

    // MARK: - Active model

    public func setActive(_ model: DictationModel) {
        activeModel = model
        defaults.set(model.rawValue, forKey: Self.activeModelDefaultsKey)
    }

    // MARK: - Download / delete

    public func download(_ model: DictationModel) {
        guard inFlight[model] == nil else { return }

        // A previous run may have left the model fully on disk under
        // the HF cache layout WhisperKit uses. Adopt it instead of
        // re-fetching: WhisperKit.download still goes through the Hub
        // discovery API (`getFilenames`), which can fail with a
        // network blip even when every file is already local.
        refreshInstalled()
        if installedModels.contains(model) {
            downloadErrors[model] = nil
            return
        }

        // Any previous attempt that landed an incomplete tree (e.g.
        // the user quit mid-download, the network dropped, or the
        // process crashed during snapshot) leaves a partial folder
        // under `argmaxinc/whisperkit-coreml/openai_whisper-…/` that
        // is NOT a valid install. Hub.snapshot doesn't always cleanly
        // overwrite, and the tail of those broken `.mlmodelc` dirs
        // would silently survive a "successful" re-download and break
        // CoreML at load time. Wipe (silently — the user just asked
        // to download, no need to flag a "previous download was
        // incomplete" banner) before retrying.
        Self.wipeFolders(for: model)

        downloadProgress[model] = 0
        downloadErrors[model] = nil

        fputs("[Clawix.dictation] download begin variant=\(model.whisperKitVariant)\n", stderr)

        let task = Task { [weak self] in
            do {
                _ = try await WhisperKit.download(
                    variant: model.whisperKitVariant,
                    progressCallback: { [weak self] progress in
                        let fraction = progress.fractionCompleted
                        let completed = progress.completedUnitCount
                        let total = progress.totalUnitCount
                        fputs("[Clawix.dictation] progress \(model.rawValue) \(Int(fraction * 100))% (\(completed)/\(total))\n", stderr)
                        Task { @MainActor in
                            self?.downloadProgress[model] = fraction
                        }
                    }
                )
                try Task.checkCancellation()
                fputs("[Clawix.dictation] download finished variant=\(model.whisperKitVariant)\n", stderr)
                await MainActor.run {
                    guard let self else { return }
                    self.inFlight[model] = nil
                    self.downloadProgress[model] = 1.0
                    self.refreshInstalled()
                    self.installedModels.insert(model)
                }
            } catch {
                let cancelled = Self.isCancellation(error)
                let message = error.localizedDescription
                if cancelled {
                    fputs("[Clawix.dictation] download \(model.rawValue) cancelled\n", stderr)
                } else {
                    fputs("[Clawix.dictation] download \(model.rawValue) failed: \(message)\n", stderr)
                    fputs("[Clawix.dictation] error detail: \(String(reflecting: error))\n", stderr)
                }
                await MainActor.run {
                    guard let self else { return }
                    self.inFlight[model] = nil
                    if cancelled {
                        // User asked to stop; wipe any partial cache
                        // first so `refreshInstalled` doesn't pick up a
                        // half-written tree (a single completed
                        // .mlmodelc inside the variant folder is enough
                        // to fool the recursive probe and would leave
                        // the row stuck on Use/Delete). Silent wipe —
                        // cancellation is intentional, no banner.
                        Self.wipeFolders(for: model)
                        self.refreshInstalled()
                        self.downloadProgress[model] = nil
                        self.downloadErrors[model] = nil
                    } else {
                        // The download may have completed and the failure
                        // happened in a post-flight verification step. If
                        // the on-disk layout is now valid, treat it as
                        // installed instead of forcing the user to retry.
                        self.refreshInstalled()
                        if self.installedModels.contains(model) {
                            self.downloadProgress[model] = 1.0
                        } else {
                            // Partial state left over: every previous
                            // run treated this as "still installed" if
                            // ANY .mlmodelc dir was on disk, which is
                            // exactly how the user got into the
                            // "Unable to load model … coremldata.bin
                            // is not valid" trap. Silent wipe so the
                            // next download is clean; we set our own
                            // contextual error message right after, so
                            // we don't want the notification observer
                            // overwriting it with the generic
                            // "previous download was incomplete" copy.
                            Self.wipeFolders(for: model)
                            self.downloadProgress[model] = nil
                            self.downloadErrors[model] = "Download failed: \(message). Tap Download to retry."
                        }
                    }
                }
            }
        }
        inFlight[model] = task
    }

    public func cancel(_ model: DictationModel) {
        guard let task = inFlight[model] else { return }
        // Optimistically clear UI state; the task's catch path will run
        // shortly and finalize cleanup (cache wipe, inFlight removal).
        downloadProgress[model] = nil
        downloadErrors[model] = nil
        task.cancel()
    }

    public func isDownloading(_ model: DictationModel) -> Bool {
        inFlight[model] != nil
    }

    /// Treat both Swift's cooperative cancellation and URLSession's
    /// `NSURLErrorCancelled` as the same "user asked to stop" signal,
    /// since `WhisperKit.download` may surface either depending on
    /// where in the pipeline we cut it off.
    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        return false
    }

    public func delete(_ model: DictationModel) {
        guard !deletingModels.contains(model) else { return }
        deletingModels.insert(model)
        let urls = Self.candidatePaths(for: model)
        Task.detached(priority: .userInitiated) { [weak self] in
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            await MainActor.run {
                guard let self else { return }
                self.installedModels.remove(model)
                self.downloadProgress[model] = nil
                self.downloadErrors[model] = nil
                self.deletingModels.remove(model)
            }
        }
    }

    public func isDeleting(_ model: DictationModel) -> Bool {
        deletingModels.contains(model)
    }

    public func refreshInstalled() {
        var found: Set<DictationModel> = []
        for model in DictationModel.allCases where Self.installedFolder(for: model) != nil {
            found.insert(model)
        }
        installedModels = found
        // If the persisted active model isn't on disk but another one
        // is, adopt that one. Without this fallback the user gets a
        // silent "No transcription model is downloaded yet" error
        // every time they trigger dictation: e.g. when a previous
        // build saved a different default, when the chosen variant
        // was deleted out from under us, or when defaults got reset.
        // Picking deterministically keeps two simultaneous instances
        // (GUI + daemon) on the same model.
        if !found.isEmpty, !found.contains(activeModel),
           let fallback = found.sorted(by: { $0.rawValue < $1.rawValue }).first {
            activeModel = fallback
            defaults.set(fallback.rawValue, forKey: Self.activeModelDefaultsKey)
        }
    }

    // MARK: - Helpers

    /// Candidate on-disk locations WhisperKit may have unpacked the
    /// variant into. The Hub downloader nests under
    /// `argmaxinc/whisperkit-coreml/openai_whisper-<variant>/`; older
    /// flows wrote a flat `<variant>/` folder. We probe both so users
    /// who ran a previous build still resolve. `nonisolated` because
    /// `TranscriptionService` (an actor) calls this off the main
    /// actor when it needs to point WhisperKit at a folder.
    public nonisolated static func candidatePaths(for model: DictationModel) -> [URL] {
        let root = modelsRoot()
        return [
            root.appendingPathComponent("argmaxinc/whisperkit-coreml/openai_whisper-\(model.whisperKitVariant)"),
            root.appendingPathComponent("argmaxinc/whisperkit-coreml/\(model.whisperKitVariant)"),
            root.appendingPathComponent(model.whisperKitVariant)
        ]
    }

    /// Return the first candidate that holds a complete WhisperKit
    /// variant install, or nil if none do. WhisperKit reads the
    /// tokenizer separately from the `openai/whisper-<variant>` cache
    /// (different repo) so we don't require a `tokenizer.json` next to
    /// the weights — the argmaxinc folder typically doesn't carry one.
    public nonisolated static func installedFolder(for model: DictationModel) -> URL? {
        for url in candidatePaths(for: model) {
            if isCompleteVariantFolder(at: url) { return url }
        }
        return nil
    }

    /// CoreML refuses to load any `.mlmodelc` that doesn't carry a
    /// `coremldata.bin`, and an interrupted Hub.snapshot frequently
    /// leaves the dir present but without that file (or with it
    /// truncated to zero bytes). Treat both as "not installed" so the
    /// Settings row falls back to "Download" instead of pretending the
    /// model is ready. The previous `hasMLModelC` check only required
    /// the directory to exist, which is what shipped the user the
    /// "Unable to load model: file:///…/MelSpectrogram.mlmodelc"
    /// CoreML error after a partially-downloaded large-v3.
    private nonisolated static func mlmodelcIsValid(at url: URL) -> Bool {
        let bin = url.appendingPathComponent("coremldata.bin")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: bin.path) else {
            return false
        }
        if (attrs[.type] as? FileAttributeType) != .typeRegular { return false }
        if (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 0 { return false }
        return true
    }

    /// Components every Whisper variant on `argmaxinc/whisperkit-coreml`
    /// ships and that WhisperKit's `loadModels` looks up by name. Some
    /// distilled variants additionally ship `TextDecoderContextPrefill`
    /// — that one is optional and absent from base Large V3, so we
    /// don't gate on it.
    private nonisolated static var requiredMLModelCNames: [String] {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
    }

    /// True iff `url` looks like a complete WhisperKit variant folder:
    /// the three required `.mlmodelc` directories are present and each
    /// of them carries a non-empty `coremldata.bin`. We don't validate
    /// the inner `weights/weight.bin` because some small components
    /// inline their tensors into `model.mil`; CoreML's load step is
    /// the canonical authority and `coremldata.bin` is its gating file.
    public nonisolated static func isCompleteVariantFolder(at url: URL) -> Bool {
        for name in requiredMLModelCNames {
            let mlc = url.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            if !mlmodelcIsValid(at: mlc) { return false }
        }
        return true
    }

    /// Synchronously remove every candidate path for `model`. Used by
    /// `cancel`, `delete`, and the pre-download wipe — none of which
    /// should surface a "previous download was incomplete" banner to
    /// the user, since those are intentional or routine.
    private nonisolated static func wipeFolders(for model: DictationModel) {
        for url in candidatePaths(for: model) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Wipe the on-disk tree AND post `modelInvalidatedNotification`,
    /// so every live `DictationModelManager` instance (GUI + daemon)
    /// drops the model from `installedModels` and shows a re-download
    /// prompt. Reserved for genuine corruption signals — e.g. when
    /// `TranscriptionService` finds the folder passes our static
    /// validation but WhisperKit still refuses to load what's there.
    public nonisolated static func wipeBrokenInstall(for model: DictationModel) {
        wipeFolders(for: model)
        NotificationCenter.default.post(
            name: modelInvalidatedNotification,
            object: model.rawValue
        )
    }

    /// Root directory under which WhisperKit caches downloaded models.
    /// Matches the default `downloadBase` used by `Hub` when no custom
    /// folder is passed to `WhisperKit.download`.
    public nonisolated static func modelsRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("huggingface/models")
    }
}
#endif
