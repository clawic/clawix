import Foundation
import AppKit
import SwiftUI
import ClawixEngine

/// Single owner of the dictation state machine. Both the in-composer
/// mic button and the global hotkey route through this object so the
/// app can never end up in two recording sessions at once.
///
/// The state surface (`state`, `levels`, `formattedElapsed`) lines up
/// with what the composer's waveform and transcribing-spinner views
/// already read, so swapping the source from a per-view recorder to
/// this shared coordinator is a straight rename in the composer.
@MainActor
final class DictationCoordinator: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    /// Public-facing classification of the in-flight session, exposed
    /// as `@Published activeSource`. Views use it to decide whether
    /// they should react to the current recording. The in-composer
    /// waveform should *only* show for `.composer` sessions; the
    /// global floating overlay should *only* show for `.hotkey`
    /// sessions. Without this discriminator, a hotkey-driven recording
    /// (system-wide, agnostic to Clawix) would also flip the composer
    /// into its recording toolbar — the original bug this enum fixes.
    enum SessionSource: Equatable {
        case none
        case composer
        case hotkey
        case quickAsk
    }

    /// Internal full-resolution source enum that carries the composer's
    /// completion callback alongside the public classification.
    private enum Source {
        case composer(completion: (String) -> Void)
        case hotkey
        case quickAsk(completion: (String) -> Void)

        var publicSource: SessionSource {
            switch self {
            case .composer: return .composer
            case .hotkey:   return .hotkey
            case .quickAsk: return .quickAsk
            }
        }
    }

    static let shared = DictationCoordinator()

    @Published private(set) var state: State = .idle
    @Published private(set) var levels: [CGFloat] = []
    /// Downsampled level history at ~5 Hz. Drives the in-composer
    /// scrolling waveform, which expects bars to land at the same
    /// cadence as iOS (`AVAudioRecorder.averagePower` is polled five
    /// times per second there). Feeding it the raw 50 Hz `levels`
    /// stream made the scroll feel jittery and "buggy fast" because
    /// every audio callback would reset the bar phase.
    @Published private(set) var barLevels: [CGFloat] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastError: String?

    /// Origin of the current session (or `.none` while idle). Composer
    /// views observe this to ignore hotkey sessions; the floating
    /// overlay observes `overlayVisible`, which is only set on hotkey.
    @Published private(set) var activeSource: SessionSource = .none

    /// Whether the floating overlay panel should be visible. The
    /// overlay observes this directly; the SettingsView observes only
    /// `state`.
    @Published private(set) var overlayVisible: Bool = false

    /// Streaming partial transcript (#19). Apple Speech publishes a
    /// best-guess refinement every ~150 ms during recording; Whisper
    /// local doesn't and leaves this empty. Overlay observes and
    /// renders below the waveform when non-empty + the live preview
    /// toggle is on.
    @Published private(set) var partialTranscript: String = ""

    /// Drives the "Press ESC again to cancel recording" toast that
    /// appears above the pill on the first Esc press. Replicates the
    /// reference UI's double-tap-to-cancel pattern: a single Esc
    /// raises the hint, a second Esc within `escDoubleTapWindow`
    /// cancels, and the hint auto-dismisses if the second press never
    /// comes. Single-press cancellation would be too easy to fire by
    /// accident — the user can have Esc bound to other behaviours in
    /// the foreground app.
    @Published private(set) var escHintVisible: Bool = false
    private var escFirstPressAt: Date?
    private var escTimeoutTask: Task<Void, Never>?
    private let escDoubleTapWindow: TimeInterval = 1.5

    /// User-facing error message that the overlay surfaces as a toast
    /// when dictation finishes without delivering any text (e.g. the
    /// active Whisper model isn't installed, mic was denied, the cloud
    /// provider returned an error). Without this the overlay would
    /// just disappear and the user has no signal as to why the press
    /// produced nothing — exactly the silent failure mode the bug
    /// report flagged.
    @Published private(set) var errorToastMessage: String?
    private var errorToastTask: Task<Void, Never>?
    private let errorToastWindow: TimeInterval = 5.0

    let modelManager: DictationModelManager

    private let capture = AudioCapture()
    /// Allocated lazily the first time the user picks the Apple
    /// Speech backend so the system framework isn't loaded for users
    /// who stay on Whisper local.
    private lazy var appleSpeech = AppleSpeechRecorder()
    private var source: Source = .hotkey
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var barTimer: Timer?
    private static let barCadence: TimeInterval = 0.2
    private static let barHistoryCap = 240
    private var languageHint: String?
    private var injectOnFinish = true
    /// Increments on every `cancel()` and on every fresh start. Async
    /// transcription Tasks check this against their captured value
    /// and bail out if it no longer matches, so a slow Whisper run
    /// can't surface a stale result after the user has dismissed the
    /// overlay or kicked off a new dictation.
    private var sessionToken: Int = 0

    /// Which engine actually drove the current session. Captured at
    /// startCapture so cancel/stop paths know whether to tear down
    /// AUHAL or the Apple Speech recognizer.
    private var activeBackend: DictationTranscriptionBackend = .whisperLocal

    /// `restoreClipboard`, `injectText`, `autoSendKey`, `language`,
    /// `restoreClipboardDelayMs` and `addSpaceBefore` settings persist
    /// in UserDefaults and are read each session, so flipping them in
    /// Settings takes effect the next time the user dictates.
    /// `language` is the Whisper language code (e.g. "es", "en"); the
    /// sentinel `"auto"` means "let Whisper detect".
    static let injectDefaultsKey = "dictation.injectText"
    static let restoreClipboardDefaultsKey = "dictation.restoreClipboard"
    static let autoEnterDefaultsKey = "dictation.autoEnter"
    static let autoSendKeyDefaultsKey = "dictation.autoSendKey"
    static let languageDefaultsKey = "dictation.language"
    static let restoreClipboardDelayMsKey = "dictation.restoreClipboardDelayMs"
    static let addSpaceBeforeKey = "dictation.addSpaceBeforePaste"
    static let autoFormatParagraphsKey = "dictation.autoFormatParagraphs"
    static let prewarmOnLaunchKey = "dictation.prewarmOnLaunch"
    /// Voice Activity Detection on the local Whisper path. WhisperKit
    /// implements this via `chunkingStrategy = .vad`. Default ON.
    static let vadEnabledKey = "dictation.vadEnabled"
    /// Which transcription backend the coordinator routes to. Values
    /// are `DictationTranscriptionBackend.rawValue`. Default
    /// `whisperLocal` (the existing AUHAL → WhisperKit path); when
    /// set to `appleSpeech`, audio capture is handled inside
    /// `AppleSpeechRecorder` (its own AVAudioEngine) and partials
    /// stream into `partialTranscript` for the live preview.
    static let backendKey = "dictation.transcriptionBackend"
    /// Live preview toggle (#19). On: render Whisper / Apple Speech
    /// partials in the floating overlay so the user sees the words
    /// as they speak. Off: only the waveform shows.
    static let livePreviewEnabledKey = "dictation.livePreviewEnabled"

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        modelManager: DictationModelManager? = nil
    ) {
        self.defaults = defaults
        self.modelManager = modelManager ?? DictationModelManager(defaults: defaults)
        // Default to ON for paste + clipboard restore on first launch.
        // Auto-Enter stays OFF: presses Return inside whatever field the
        // user happens to be focused on, which is the kind of behaviour
        // users want to opt into rather than discover on first dictation.
        if defaults.object(forKey: Self.injectDefaultsKey) == nil {
            defaults.set(true, forKey: Self.injectDefaultsKey)
        }
        if defaults.object(forKey: Self.restoreClipboardDefaultsKey) == nil {
            defaults.set(true, forKey: Self.restoreClipboardDefaultsKey)
        }

        if defaults.object(forKey: Self.autoSendKeyDefaultsKey) == nil {
            if let legacy = defaults.object(forKey: Self.autoEnterDefaultsKey) as? Bool {
                let migrated: DictationAutoSendKey = legacy ? .enter : .none
                defaults.set(migrated.rawValue, forKey: Self.autoSendKeyDefaultsKey)
            } else {
                defaults.set(DictationAutoSendKey.none.rawValue, forKey: Self.autoSendKeyDefaultsKey)
            }
        }

        if defaults.object(forKey: Self.restoreClipboardDelayMsKey) == nil {
            defaults.set(2000, forKey: Self.restoreClipboardDelayMsKey)
        }
        if defaults.object(forKey: Self.addSpaceBeforeKey) == nil {
            defaults.set(true, forKey: Self.addSpaceBeforeKey)
        }
        if defaults.object(forKey: Self.autoFormatParagraphsKey) == nil {
            defaults.set(true, forKey: Self.autoFormatParagraphsKey)
        }
        if defaults.object(forKey: Self.prewarmOnLaunchKey) == nil {
            defaults.set(true, forKey: Self.prewarmOnLaunchKey)
        }
        if defaults.object(forKey: Self.vadEnabledKey) == nil {
            defaults.set(true, forKey: Self.vadEnabledKey)
        }
        if defaults.object(forKey: Self.backendKey) == nil {
            defaults.set(DictationTranscriptionBackend.whisperLocal.rawValue, forKey: Self.backendKey)
        }
        if defaults.object(forKey: Self.livePreviewEnabledKey) == nil {
            defaults.set(true, forKey: Self.livePreviewEnabledKey)
        }
        _ = MediaController.shared
        _ = PlaybackController.shared
        _ = FillerWordsManager.shared
        _ = PowerModeManager.shared
        // Start the privacy cleanup scheduler so users with the
        // toggle on don't accumulate stale rows / audio across
        // sessions. Idempotent; safe to call once per launch.
        CleanupScheduler.shared.start()
        capture.onLevels = { [weak self] levels in
            self?.levels = levels
        }
        // Touch the singleton so its Core Audio listeners are armed
        // from app launch (otherwise the device list updates only the
        // first time the user opens the menu bar item).
        _ = MicrophonePreferences.shared
    }

    var formattedElapsed: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Public entry points

    /// Start a recording driven by the in-composer mic button.
    /// `completion` fires once with the transcribed text; an empty
    /// string means recording was cancelled or transcription failed.
    ///
    /// Pass `nil` (the normal case) to honour the user's Voice-to-Text
    /// language setting, the same resolution the global hotkey uses.
    /// An explicit value overrides the setting for that one session.
    func startFromComposer(language: String? = nil, completion: @escaping (String) -> Void) {
        guard state == .idle else { return }
        source = .composer(completion: completion)
        languageHint = language ?? resolvedLanguageHint()
        injectOnFinish = false
        beginRecording(showOverlay: false)
    }

    func startFromQuickAsk(language: String? = nil, completion: @escaping (String) -> Void) {
        guard state == .idle else { return }
        source = .quickAsk(completion: completion)
        languageHint = language ?? resolvedLanguageHint()
        injectOnFinish = false
        beginRecording(showOverlay: false)
    }

    /// Start a recording driven by the global hotkey. Result is pasted
    /// into the foreground app (provided Accessibility is granted)
    /// when the recording stops.
    ///
    /// Language resolution order:
    ///   1. Explicit `language` argument (used by tests / future
    ///      headless callers).
    ///   2. The user's persisted `dictation.language` setting from
    ///      Settings → Voice to Text → Output.
    ///      - `"auto"` (default) → `nil`, so Whisper auto-detects.
    ///      - A specific code (e.g. `"es"`) → forces that language.
    ///
    /// The earlier implementation forced `AppLocale.current` here,
    /// which ignored the user's Settings choice — Spanish dictation
    /// against an English-locale app got translated to English text.
    func startFromHotkey(language: String? = nil) {
        guard state == .idle else { return }
        source = .hotkey
        languageHint = language ?? resolvedLanguageHint()
        injectOnFinish = defaults.bool(forKey: Self.injectDefaultsKey)
        beginRecording(showOverlay: true)
    }

    /// Resolve the Whisper language hint from the user's Settings,
    /// honouring any active Power Mode override.
    /// Returns `nil` for `"auto"` (or a missing/empty value) so
    /// `TranscriptionService.decodeOptions` skips the explicit
    /// `language` field and lets Whisper detect.
    private func resolvedLanguageHint() -> String? {
        // Power Mode override takes precedence.
        if let pm = PowerModeManager.shared.activeConfig,
           let langOverride = pm.languageOverride,
           !langOverride.isEmpty {
            if langOverride == "auto" { return nil }
            return langOverride
        }
        let stored = defaults.string(forKey: Self.languageDefaultsKey) ?? "auto"
        if stored.isEmpty || stored == "auto" {
            return nil
        }
        return stored
    }

    private func resolvedAutoSendKey() -> DictationAutoSendKey {
        if let pm = PowerModeManager.shared.activeConfig,
           let raw = pm.autoSendKeyOverride,
           let value = DictationAutoSendKey(rawValue: raw) {
            return value
        }
        let raw = defaults.string(forKey: Self.autoSendKeyDefaultsKey) ?? DictationAutoSendKey.none.rawValue
        return DictationAutoSendKey(rawValue: raw) ?? .none
    }

    private func resolvedActiveModel() -> DictationModel {
        if let pm = PowerModeManager.shared.activeConfig,
           let override = pm.transcriptionModelOverride {
            return override
        }
        return modelManager.activeModel
    }

    func resolvedLanguageHintForExternalCallers() -> String? {
        resolvedLanguageHint()
    }

    // MARK: - Prewarm

    static func composeWhisperPrompt(language: String?) -> String? {
        let vocab = VocabularyManager.shared.asPromptFragment()
        // Power Mode override takes precedence over the per-language
        // global prompt.
        let stylePrompt: String?
        if let pm = PowerModeManager.shared.activeConfig,
           let override = pm.whisperPromptOverride,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stylePrompt = override
        } else {
            stylePrompt = WhisperPromptStore.shared.prompt(for: language)
        }
        switch (vocab, stylePrompt) {
        case (nil, nil): return nil
        case (let v?, nil): return v
        case (nil, let s?):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case (let v?, let s?):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? v : "\(v). \(trimmed)"
        }
    }

    func prewarmIfEnabled() {
        guard defaults.object(forKey: Self.prewarmOnLaunchKey) as? Bool ?? true else { return }
        let model = modelManager.activeModel
        guard modelManager.installedModels.contains(model) else { return }
        let samples = [Float](repeating: 0.0, count: 3200)
        Task.detached(priority: .background) {
            _ = try? await TranscriptionService.shared.transcribe(
                samples: samples,
                using: model,
                language: nil
            )
        }
    }

    /// Hotkey "toggle" mode: tap once to start, tap again to stop.
    func toggleFromHotkey(language: String? = nil) {
        switch state {
        case .idle: startFromHotkey(language: language)
        case .recording: stop()
        case .transcribing: break
        }
    }

    // MARK: - Esc double-tap

    /// Routed through from the overlay's Esc key monitor. First press
    /// raises the toast; a second press inside the window cancels.
    /// No-op while idle so an Esc that wasn't aimed at the dictation
    /// chip can't suddenly start mutating its state.
    func handleEscapeFromOverlay() {
        guard state != .idle else { return }
        let now = Date()
        if let first = escFirstPressAt,
           now.timeIntervalSince(first) <= escDoubleTapWindow {
            // Second press inside the window: cancel the session.
            clearEscHint()
            cancel()
        } else {
            // First press: raise the hint and arm the auto-clear so the
            // window doesn't stay open forever — the toast's own
            // progress bar drains in lockstep with this sleep.
            escFirstPressAt = now
            escHintVisible = true
            escTimeoutTask?.cancel()
            let window = escDoubleTapWindow
            escTimeoutTask = Task { [weak self] in
                let nanos = UInt64(window * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.clearEscHint() }
            }
        }
    }

    /// Dismiss the Esc hint immediately. The toast's "x" button calls
    /// this so the user can hide it without waiting for the timer.
    func dismissEscHint() {
        clearEscHint()
    }

    private func clearEscHint() {
        escFirstPressAt = nil
        escTimeoutTask?.cancel()
        escTimeoutTask = nil
        escHintVisible = false
    }

    /// Raise an error toast over the floating panel and auto-dismiss
    /// after `errorToastWindow`. Called from `fail()` and from
    /// `finish()` when the result is empty + an error was reported.
    /// Idempotent — replaces any in-flight toast so two failures back
    /// to back collapse to a single visible message.
    private func showErrorToast(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorToastMessage = trimmed
        overlayVisible = true
        errorToastTask?.cancel()
        let window = errorToastWindow
        errorToastTask = Task { [weak self] in
            let nanos = UInt64(window * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismissErrorToast() }
        }
    }

    /// Dismiss the error toast and tear down the overlay panel. Called
    /// by the toast's close button and by the auto-dismiss timer.
    func dismissErrorToast() {
        errorToastTask?.cancel()
        errorToastTask = nil
        errorToastMessage = nil
        // Only the toast was keeping the panel up; with it gone the
        // panel should hide so it doesn't linger empty over the user's
        // foreground app.
        if state == .idle {
            overlayVisible = false
        }
    }

    /// Stop recording and run transcription. Result is delivered to
    /// the composer completion or pasted into the foreground app
    /// depending on `source`. The samples + model + language used for
    /// this run are captured and forwarded to
    /// `LastTranscriptionStore` after `finish` so quick-action
    /// AppIntents (Paste Last, Retry Last) can replay the result.
    func stop() {
        guard state == .recording else { return }
        // Unmute synchronously before the cue: AVAudioPlayer routes
        // through the system mixer, so the stop sound would be silent
        // otherwise. Mic capture is finished by this point, so there's
        // no bleed risk from unmuting early.
        MediaController.shared.unmuteImmediately()
        SoundManager.shared.playStop()
        state = .transcribing
        invalidateElapsedTimer()
        invalidateBarTimer()
        // Apple Speech delivers its final transcript via the recognizer
        // callback wired in startCapture. We just signal end-of-audio
        // and let `onFinal` drive the same `finish` path the Whisper
        // branch ends in.
        if activeBackend == .appleSpeech {
            appleSpeech.stop()
            return
        }
        let samples = capture.stopAndCollect()
        let language = languageHint
        let model = resolvedActiveModel()
        let prompt = Self.composeWhisperPrompt(language: language)
        let token = sessionToken

        // Cloud Whisper backends (Groq / Deepgram / Custom) take the
        // captured PCM and upload as WAV. Same async + enhancement
        // path as the local Whisper branch — the only difference is
        // the transcription source.
        if let cloud = activeBackend.cloudProvider {
            Task { [weak self] in
                do {
                    let cloudRaw = try await cloud.transcribe(
                        samples: samples,
                        language: language,
                        prompt: prompt
                    )
                    // Cloud Whisper providers don't return per-segment
                    // timestamps in their JSON shapes, so fall back to
                    // the heuristic sentence-boundary auto-format
                    // (mid-sentence safe).
                    let autoFormat = self?.defaults.object(forKey: Self.autoFormatParagraphsKey) as? Bool ?? true
                    let raw = autoFormat
                        ? TranscriptFormatter.format(cloudRaw)
                        : cloudRaw
                    let pmActive = await PowerModeManager.shared.activeConfig
                    let enhanced = await EnhancementService.shared.enhance(
                        raw: raw,
                        powerMode: pmActive
                    )
                    await self?.finishIfFresh(
                        token: token,
                        text: enhanced,
                        errorMessage: nil,
                        samples: samples,
                        model: model,
                        language: language
                    )
                } catch {
                    await self?.finishIfFresh(
                        token: token,
                        text: "",
                        errorMessage: error.localizedDescription,
                        samples: samples,
                        model: model,
                        language: language
                    )
                }
            }
            return
        }
        Task { [weak self] in
            do {
                let useVAD = self?.defaults.object(forKey: Self.vadEnabledKey) as? Bool ?? true
                let autoFormat = self?.defaults.object(forKey: Self.autoFormatParagraphsKey) as? Bool ?? true
                // Use the segmented variant when auto-format is on so
                // we have silence timestamps to break paragraphs at.
                // When off, take the cheaper joined-text path.
                let raw: String
                if autoFormat {
                    let segmented = try await TranscriptionService.shared.transcribeWithSegments(
                        samples: samples,
                        using: model,
                        language: language,
                        prompt: prompt,
                        useVAD: useVAD
                    )
                    raw = TranscriptFormatter.format(segmented)
                } else {
                    raw = try await TranscriptionService.shared.transcribe(
                        samples: samples,
                        using: model,
                        language: language,
                        prompt: prompt,
                        useVAD: useVAD
                    )
                }
                // AI Enhancement (#21). Returns the input unchanged
                // when the master toggle is off, so this is a no-op
                // for users who haven't opted in. Runs here in the
                // same async path as transcription so we never block
                // the main actor.
                let pmActive = await PowerModeManager.shared.activeConfig
                let enhanced = await EnhancementService.shared.enhance(
                    raw: raw,
                    powerMode: pmActive
                )
                await self?.finishIfFresh(
                    token: token,
                    text: enhanced,
                    errorMessage: nil,
                    samples: samples,
                    model: model,
                    language: language
                )
            } catch {
                await self?.finishIfFresh(
                    token: token,
                    text: "",
                    errorMessage: error.localizedDescription,
                    samples: samples,
                    model: model,
                    language: language
                )
            }
        }
    }

    /// Abandon the current session immediately, regardless of state.
    /// Wired to the overlay's "X" button so the user can always escape
    /// a stuck transcription (no model downloaded, daemon hung, etc.)
    /// and gets the audio engine torn down cleanly.
    func cancel() {
        // Unmute synchronously before the cue so it's audible even if
        // mute from this session is still in effect. cleanup() below
        // will re-enter the unmute path as a no-op (didMute=false).
        MediaController.shared.unmuteImmediately()
        SoundManager.shared.playCancel()
        sessionToken &+= 1
        invalidateElapsedTimer()
        invalidateBarTimer()
        capture.cancel()
        appleSpeech.cancel()
        cleanup(deliveryText: "")
    }

    // MARK: - Recording lifecycle

    private func beginRecording(showOverlay: Bool) {
        Task { @MainActor in
            let mic = DictationPermissions.microphone()
            NSLog("[Clawix.Dictation] beginRecording mic=%@", String(describing: mic))
            switch mic {
            case .granted:
                self.startCapture(showOverlay: showOverlay)
            case .notDetermined:
                let granted = await DictationPermissions.requestMicrophone()
                if granted {
                    self.startCapture(showOverlay: showOverlay)
                } else {
                    self.fail(with: "Microphone permission was denied")
                }
            case .denied:
                self.fail(with: "Microphone permission is denied")
                DictationPermissions.openMicrophoneSettings()
            }
        }
    }

    private func startCapture(showOverlay: Bool) {
        // Bump the session token so any pending transcription Task
        // from a previous, just-cancelled session is ignored if it
        // happens to come back at the same time we're starting fresh.
        sessionToken &+= 1
        levels = []
        barLevels = []
        elapsed = 0
        partialTranscript = ""
        lastError = nil

        // Resolve the backend. Power Mode override is intentionally
        // not applied here — backend choice is global, not per-app.
        let backendRaw = defaults.string(forKey: Self.backendKey) ?? DictationTranscriptionBackend.whisperLocal.rawValue
        let backend = DictationTranscriptionBackend(rawValue: backendRaw) ?? .whisperLocal
        activeBackend = backend

        switch backend {
        case .whisperLocal, .groqCloud, .deepgramCloud, .customCloud:
            // Local Whisper and the cloud Whisper backends share the
            // capture path: AUHAL records 16 kHz mono PCM into the
            // same buffer; `stop()` then either runs WhisperKit
            // locally or uploads the WAV to the cloud provider.
            do {
                try capture.start(deviceID: MicrophonePreferences.shared.activeDeviceID())
            } catch {
                fail(with: "Couldn't start audio engine: \(error.localizedDescription)")
                return
            }
        case .appleSpeech:
            // Apple Speech runs its own AVAudioEngine. First, make
            // sure speech-recognition TCC is granted; the prompt is
            // only shown on the very first request, every subsequent
            // call returns the cached status synchronously.
            let auth = AppleSpeechRecorder.authorizationStatus()
            if auth == .notDetermined {
                Task { @MainActor [weak self] in
                    let granted = await AppleSpeechRecorder.requestPermission()
                    if granted {
                        self?.startCapture(showOverlay: showOverlay)
                    } else {
                        self?.fail(with: "Apple Speech recognition permission denied")
                    }
                }
                return
            }
            if auth != .authorized {
                fail(with: "Apple Speech recognition permission denied. Open System Settings → Privacy → Speech Recognition.")
                return
            }
            // Wire the callbacks before start() so the very first
            // partial doesn't get dropped.
            let token = sessionToken
            appleSpeech.onPartial = { [weak self] partial in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.sessionToken == token else { return }
                    self.partialTranscript = partial
                }
            }
            appleSpeech.onFinal = { [weak self] final in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.sessionToken == token else { return }
                    // Run AI Enhancement (#21) before finish, mirroring
                    // the Whisper branch. Returns input unchanged when
                    // the master toggle is off.
                    let pmActive = PowerModeManager.shared.activeConfig
                    let enhanced = await EnhancementService.shared.enhance(
                        raw: final,
                        powerMode: pmActive
                    )
                    // Apple Speech doesn't have raw PCM samples to
                    // hand back — we feed an empty array so the
                    // history record skips audio storage. Live preview
                    // already showed the user the text.
                    self.finish(
                        text: enhanced,
                        errorMessage: nil,
                        samples: [],
                        model: nil,
                        language: self.languageHint
                    )
                }
            }
            appleSpeech.onError = { [weak self] message in
                Task { @MainActor in
                    self?.lastError = message
                }
            }
            do {
                try appleSpeech.start(language: languageHint)
            } catch {
                fail(with: "Apple Speech failed to start: \(error.localizedDescription)")
                return
            }
        }
        startedAt = Date()
        startElapsedTimer()
        startBarTimer()
        // Publish the session origin BEFORE flipping `state` so any
        // SwiftUI view observing both can decide whether to react in
        // the same render pass — composer views gate on
        // `activeSource == .composer` and would otherwise flash their
        // recording toolbar for hotkey sessions.
        activeSource = source.publicSource
        state = .recording
        overlayVisible = showOverlay
        SoundManager.shared.playStart()
        // Mute system output and pause Music/Spotify per user prefs.
        // Both controllers are no-ops when their toggles are off, so
        // calling them unconditionally keeps the lifecycle simple.
        // Defer the mute by ~0.5s so the start cue plays cleanly into
        // an unmuted system; mic bleed during that small window is
        // negligible and the cue clarity matters for UX.
        MediaController.shared.muteAfter(0.5)
        PlaybackController.shared.pauseIfNeeded()
    }

    private func startElapsedTimer() {
        invalidateElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func invalidateElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func tickElapsed() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    private func startBarTimer() {
        invalidateBarTimer()
        let cadence = Self.barCadence
        barTimer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureBar() }
        }
    }

    private func invalidateBarTimer() {
        barTimer?.invalidate()
        barTimer = nil
    }

    private func captureBar() {
        guard state == .recording else { return }
        let latest = levels.last ?? 0
        barLevels.append(latest)
        let cap = Self.barHistoryCap
        if barLevels.count > cap {
            barLevels.removeFirst(barLevels.count - cap)
        }
    }

    // MARK: - Finish / cleanup

    /// Wraps `finish(text:errorMessage:)` with a session-token check so
    /// a transcription Task that wins the race after the user already
    /// cancelled doesn't paste an old transcript or reopen the
    /// overlay.
    private func finishIfFresh(
        token: Int,
        text: String,
        errorMessage: String?,
        samples: [Float],
        model: DictationModel?,
        language: String?
    ) {
        guard token == sessionToken else { return }
        finish(
            text: text,
            errorMessage: errorMessage,
            samples: samples,
            model: model,
            language: language
        )
    }

    private func finish(
        text: String,
        errorMessage: String?,
        samples: [Float],
        model: DictationModel?,
        language: String?
    ) {
        if let errorMessage {
            lastError = errorMessage
        } else {
            lastError = nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip filler words ("uh", "um", "este", "o sea", …) before
        // running the user's word-replacement dictionary. Order
        // matters: replacements may map a filler-like sound to a
        // legitimate word, and we don't want filler removal to undo
        // that. So filter first, then replace.
        let deFillered = FillerWordsManager.shared.apply(to: trimmed, language: language)
        let processed = DictationReplacementStore.shared.apply(to: deFillered)
        // Auto-format paragraphs (#7) already happened upstream in
        // the Task that owned transcription (Whisper local uses
        // segment timestamps; cloud Whisper falls back to the
        // sentence-boundary heuristic). Apple Speech is a single
        // best-of utterance and doesn't need paragraph splitting.
        // Note: AI Enhancement (#21) runs in the async Task that
        // owns transcription (see `stop()`), BEFORE finish() is
        // called. By the time we land here `text` is already the
        // enhanced version when the master toggle is on, so we
        // don't re-enter the LLM here.

        if errorMessage == nil, !processed.isEmpty {
            // Unmute before the cue: the recording-time system mute
            // may still be active. cleanup() runs after finish() and
            // its unmuteAfterDelay becomes a no-op.
            MediaController.shared.unmuteImmediately()
            SoundManager.shared.playDone()
            // Snapshot the result so AppIntents (Paste Last, Retry
            // Last) can replay it without redictating.
            LastTranscriptionStore.shared.record(
                text: processed,
                samples: samples,
                model: model,
                language: language
            )
            // Persist a transcript row + companion WAV so the
            // history view (#24), cleanup (#25), export (#26), and
            // metrics (#27) all have something to chew on. The audio
            // dump runs synchronously here because it's just a
            // local file write; the DB insert hops a Task.
            let id = UUID().uuidString
            let audioURL = DictationAudioStorage.writeWAV(samples: samples, id: id)
            let words = processed.split(whereSeparator: { $0.isWhitespace }).count
            let duration = TimeInterval(samples.count) / 16_000.0
            let pmId = PowerModeManager.shared.activeConfig?.id.uuidString
            let enhancementProvider: String? = EnhancementService.shared.isEnabled
                ? UserDefaults.standard.string(forKey: EnhancementSettings.providerKey)
                : nil
            let record = TranscriptionRecord(
                id: id,
                timestamp: Date(),
                originalText: text,
                enhancedText: text == processed ? nil : processed,
                modelUsed: model?.rawValue,
                language: language,
                durationSeconds: duration,
                audioFilePath: audioURL?.path,
                powerModeId: pmId,
                wordCount: words,
                transcriptionMs: 0,
                enhancementMs: 0,
                enhancementProvider: enhancementProvider,
                costUSD: 0
            )
            Task { @MainActor in
                await TranscriptionsRepository.shared.record(record)
            }
        }

        if injectOnFinish, !processed.isEmpty {
            let restore = defaults.bool(forKey: Self.restoreClipboardDefaultsKey)
            let restoreMs = defaults.object(forKey: Self.restoreClipboardDelayMsKey) as? Int ?? 2000
            let restoreAfter = TimeInterval(max(100, min(10_000, restoreMs))) / 1000.0
            let autoSend = resolvedAutoSendKey()
            let addSpace = defaults.object(forKey: Self.addSpaceBeforeKey) as? Bool ?? true
            do {
                try TextInjector.inject(
                    text: processed,
                    restorePrevious: restore,
                    autoSendKey: autoSend,
                    restoreAfter: restoreAfter,
                    addSpaceBefore: addSpace
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        // Surface failures over the floating panel so the user sees
        // *why* a press produced nothing. Without this, an empty
        // result + non-nil error makes the overlay disappear silently
        // (e.g. when the active Whisper model is missing on disk).
        if let errorMessage, processed.isEmpty {
            showErrorToast(errorMessage)
        }

        cleanup(deliveryText: processed)
    }

    private func fail(with message: String) {
        lastError = message
        showErrorToast(message)
        cleanup(deliveryText: "")
    }

    private func cleanup(deliveryText: String) {
        let currentSource = source
        source = .hotkey
        languageHint = nil
        startedAt = nil
        invalidateBarTimer()
        levels = []
        barLevels = []
        elapsed = 0
        partialTranscript = ""
        state = .idle
        activeSource = .none
        // Keep the panel on screen while an error toast is up so the
        // user actually sees why dictation didn't deliver text. The
        // toast schedules its own dismissal which then clears
        // `overlayVisible`.
        overlayVisible = errorToastMessage != nil
        clearEscHint()
        // Restore system output and resume the paused media app, if
        // either was modified at session start. The controllers are
        // no-ops when nothing was muted/paused.
        MediaController.shared.unmuteAfterDelay()
        PlaybackController.shared.resumeAfterDelay()

        switch currentSource {
        case .composer(let completion):
            completion(deliveryText)
        case .quickAsk(let completion):
            completion(deliveryText)
        case .hotkey:
            break
        }
    }
}
