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

    let modelManager: DictationModelManager

    private let capture = AudioCapture()
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
        _ = MediaController.shared
        _ = PlaybackController.shared
        _ = FillerWordsManager.shared
        _ = PowerModeManager.shared
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
        NSLog("[Clawix.Dictation] startFromHotkey() state=%@", String(describing: state))
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

    /// Stop recording and run transcription. Result is delivered to
    /// the composer completion or pasted into the foreground app
    /// depending on `source`. The samples + model + language used for
    /// this run are captured and forwarded to
    /// `LastTranscriptionStore` after `finish` so quick-action
    /// AppIntents (Paste Last, Retry Last) can replay the result.
    func stop() {
        guard state == .recording else { return }
        SoundManager.shared.playStop()
        state = .transcribing
        invalidateElapsedTimer()
        invalidateBarTimer()
        let samples = capture.stopAndCollect()
        let language = languageHint
        let model = resolvedActiveModel()
        let prompt = Self.composeWhisperPrompt(language: language)
        let token = sessionToken
        Task { [weak self] in
            do {
                let text = try await TranscriptionService.shared.transcribe(
                    samples: samples,
                    using: model,
                    language: language,
                    prompt: prompt
                )
                await self?.finishIfFresh(
                    token: token,
                    text: text,
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
        SoundManager.shared.playCancel()
        sessionToken &+= 1
        invalidateElapsedTimer()
        invalidateBarTimer()
        capture.cancel()
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
        lastError = nil
        do {
            try capture.start(deviceID: MicrophonePreferences.shared.activeDeviceID())
        } catch {
            fail(with: "Couldn't start audio engine: \(error.localizedDescription)")
            return
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
        MediaController.shared.muteIfNeeded()
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

        if errorMessage == nil, !processed.isEmpty {
            SoundManager.shared.playDone()
            // Snapshot the result so AppIntents (Paste Last, Retry
            // Last) can replay it without redictating.
            LastTranscriptionStore.shared.record(
                text: processed,
                samples: samples,
                model: model,
                language: language
            )
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

        cleanup(deliveryText: processed)
    }

    private func fail(with message: String) {
        lastError = message
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
        state = .idle
        activeSource = .none
        overlayVisible = false
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
