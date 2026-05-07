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
    }

    /// Internal full-resolution source enum that carries the composer's
    /// completion callback alongside the public classification.
    private enum Source {
        case composer(completion: (String) -> Void)
        case hotkey

        var publicSource: SessionSource {
            switch self {
            case .composer: return .composer
            case .hotkey:   return .hotkey
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

    /// `restoreClipboard`, `injectText`, `autoEnter` and `language`
    /// settings persist in UserDefaults and are read each session, so
    /// flipping them in Settings takes effect the next time the user
    /// dictates. `language` is the Whisper language code (e.g. "es",
    /// "en"); the sentinel `"auto"` means "let Whisper detect".
    static let injectDefaultsKey = "dictation.injectText"
    static let restoreClipboardDefaultsKey = "dictation.restoreClipboard"
    static let autoEnterDefaultsKey = "dictation.autoEnter"
    static let languageDefaultsKey = "dictation.language"

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
        if defaults.object(forKey: Self.autoEnterDefaultsKey) == nil {
            defaults.set(false, forKey: Self.autoEnterDefaultsKey)
        }
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

    /// Resolve the Whisper language hint from the user's Settings.
    /// Returns `nil` for `"auto"` (or a missing/empty value) so
    /// `TranscriptionService.decodeOptions` skips the explicit
    /// `language` field and lets Whisper detect.
    private func resolvedLanguageHint() -> String? {
        let stored = defaults.string(forKey: Self.languageDefaultsKey) ?? "auto"
        if stored.isEmpty || stored == "auto" {
            return nil
        }
        return stored
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
    /// depending on `source`.
    func stop() {
        guard state == .recording else { return }
        state = .transcribing
        invalidateElapsedTimer()
        invalidateBarTimer()
        let samples = capture.stopAndCollect()
        let language = languageHint
        let model = modelManager.activeModel
        let token = sessionToken
        Task { [weak self] in
            do {
                let text = try await TranscriptionService.shared.transcribe(
                    samples: samples,
                    using: model,
                    language: language
                )
                await self?.finishIfFresh(token: token, text: text, errorMessage: nil)
            } catch {
                await self?.finishIfFresh(token: token, text: "", errorMessage: error.localizedDescription)
            }
        }
    }

    /// Abandon the current session immediately, regardless of state.
    /// Wired to the overlay's "X" button so the user can always escape
    /// a stuck transcription (no model downloaded, daemon hung, etc.)
    /// and gets the audio engine torn down cleanly.
    func cancel() {
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
    private func finishIfFresh(token: Int, text: String, errorMessage: String?) {
        guard token == sessionToken else { return }
        finish(text: text, errorMessage: errorMessage)
    }

    private func finish(text: String, errorMessage: String?) {
        if let errorMessage {
            lastError = errorMessage
        } else {
            lastError = nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if injectOnFinish, !trimmed.isEmpty {
            let restore = defaults.bool(forKey: Self.restoreClipboardDefaultsKey)
            let autoEnter = defaults.bool(forKey: Self.autoEnterDefaultsKey)
            do {
                try TextInjector.inject(
                    text: trimmed,
                    restorePrevious: restore,
                    autoEnter: autoEnter
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        cleanup(deliveryText: trimmed)
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

        switch currentSource {
        case .composer(let completion):
            completion(deliveryText)
        case .hotkey:
            break
        }
    }
}
