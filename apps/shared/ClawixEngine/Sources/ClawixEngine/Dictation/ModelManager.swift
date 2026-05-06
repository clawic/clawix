import Foundation
import Combine
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
    public static let activeModelDefaultsKey = "dictation.activeModel"

    @Published public private(set) var activeModel: DictationModel
    @Published public private(set) var downloadProgress: [DictationModel: Double] = [:]
    @Published public private(set) var installedModels: Set<DictationModel> = []
    @Published public private(set) var lastError: String?

    private let defaults: UserDefaults
    private var inFlight: Set<DictationModel> = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.activeModelDefaultsKey),
           let parsed = DictationModel(rawValue: raw) {
            self.activeModel = parsed
        } else {
            self.activeModel = .default
        }
        refreshInstalled()
    }

    // MARK: - Active model

    public func setActive(_ model: DictationModel) {
        activeModel = model
        defaults.set(model.rawValue, forKey: Self.activeModelDefaultsKey)
    }

    // MARK: - Download / delete

    public func download(_ model: DictationModel) {
        guard !inFlight.contains(model) else { return }
        inFlight.insert(model)
        downloadProgress[model] = 0
        lastError = nil

        Task { [weak self] in
            do {
                _ = try await WhisperKit.download(
                    variant: model.whisperKitVariant,
                    progressCallback: { [weak self] progress in
                        Task { @MainActor in
                            self?.downloadProgress[model] = progress.fractionCompleted
                        }
                    }
                )
                await MainActor.run {
                    self?.inFlight.remove(model)
                    self?.downloadProgress[model] = 1.0
                    self?.installedModels.insert(model)
                }
            } catch {
                await MainActor.run {
                    self?.inFlight.remove(model)
                    self?.downloadProgress[model] = nil
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    public func isDownloading(_ model: DictationModel) -> Bool {
        inFlight.contains(model)
    }

    public func delete(_ model: DictationModel) {
        let folder = Self.modelsRoot().appendingPathComponent(model.whisperKitVariant)
        try? FileManager.default.removeItem(at: folder)
        installedModels.remove(model)
        downloadProgress[model] = nil
    }

    public func refreshInstalled() {
        let root = Self.modelsRoot()
        var found: Set<DictationModel> = []
        for model in DictationModel.allCases {
            // WhisperKit nests variant folders under the HF repo path
            // (`argmaxinc/whisperkit-coreml/<variant>/`). Treat any
            // matching folder that contains at least one .mlmodelc as
            // installed.
            let candidates = [
                root.appendingPathComponent(model.whisperKitVariant),
                root.appendingPathComponent("argmaxinc/whisperkit-coreml/openai_whisper-\(model.whisperKitVariant)"),
                root.appendingPathComponent("argmaxinc/whisperkit-coreml/\(model.whisperKitVariant)")
            ]
            for url in candidates {
                if hasMLModelC(at: url) {
                    found.insert(model)
                    break
                }
            }
        }
        installedModels = found
    }

    // MARK: - Helpers

    private func hasMLModelC(at url: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return entries.contains { $0.pathExtension == "mlmodelc" }
            || entries.contains { hasMLModelC(at: $0) }
    }

    /// Root directory under which WhisperKit caches downloaded models.
    /// Matches the default `downloadBase` used by `Hub` when no custom
    /// folder is passed to `WhisperKit.download`.
    public static func modelsRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("huggingface/models")
    }
}
