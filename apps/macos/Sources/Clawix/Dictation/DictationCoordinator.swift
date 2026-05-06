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

    /// Where the current session was kicked off from. Drives whether
    /// the floating overlay is shown and whether the result is pasted
    /// into the foreground app or returned to the composer caller.
    private enum Source {
        case composer(completion: (String) -> Void)
        case hotkey
    }

    static let shared = DictationCoordinator()

    @Published private(set) var state: State = .idle
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastError: String?

    /// Whether the floating overlay panel should be visible. The
    /// overlay observes this directly; the SettingsView observes only
    /// `state`.
    @Published private(set) var overlayVisible: Bool = false

    let modelManager: DictationModelManager

    private let capture = AudioCapture()
    private var source: Source = .hotkey
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var languageHint: String?
    private var injectOnFinish = true
    /// Increments on every `cancel()` and on every fresh start. Async
    /// transcription Tasks check this against their captured value
    /// and bail out if it no longer matches, so a slow Whisper run
    /// can't surface a stale result after the user has dismissed the
    /// overlay or kicked off a new dictation.
    private var sessionToken: Int = 0

    /// `restoreClipboard` and `injectText` toggles persisted in
    /// UserDefaults and read each session, so flipping them in
    /// Settings takes effect the next time the user dictates.
    static let injectDefaultsKey = "dictation.injectText"
    static let restoreClipboardDefaultsKey = "dictation.restoreClipboard"

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        modelManager: DictationModelManager? = nil
    ) {
        self.defaults = defaults
        self.modelManager = modelManager ?? DictationModelManager(defaults: defaults)
        // Default to ON for both flags on first launch.
        if defaults.object(forKey: Self.injectDefaultsKey) == nil {
            defaults.set(true, forKey: Self.injectDefaultsKey)
        }
        if defaults.object(forKey: Self.restoreClipboardDefaultsKey) == nil {
            defaults.set(true, forKey: Self.restoreClipboardDefaultsKey)
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
    func startFromComposer(language: String?, completion: @escaping (String) -> Void) {
        guard state == .idle else { return }
        source = .composer(completion: completion)
        languageHint = language
        injectOnFinish = false
        beginRecording(showOverlay: false)
    }

    /// Start a recording driven by the global hotkey. Result is pasted
    /// into the foreground app (provided Accessibility is granted)
    /// when the recording stops.
    func startFromHotkey(language: String? = nil) {
        guard state == .idle else { return }
        source = .hotkey
        languageHint = language ?? AppLanguage.from(code: AppLocale.current.identifier).whisperLanguageCode
        injectOnFinish = defaults.bool(forKey: Self.injectDefaultsKey)
        beginRecording(showOverlay: true)
    }

    /// Hotkey "toggle" mode: tap once to start, tap again to stop.
    func toggleFromHotkey(language: String? = nil) {
        switch state {
        case .idle: startFromHotkey(language: language)
        case .recording: stop()
        case .transcribing: break
        }
    }

    /// Stop recording and run transcription. Result is delivered to
    /// the composer completion or pasted into the foreground app
    /// depending on `source`.
    func stop() {
        guard state == .recording else { return }
        state = .transcribing
        invalidateElapsedTimer()
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
        capture.cancel()
        cleanup(deliveryText: "")
    }

    // MARK: - Recording lifecycle

    private func beginRecording(showOverlay: Bool) {
        Task { @MainActor in
            let mic = DictationPermissions.microphone()
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
            do {
                try TextInjector.inject(text: trimmed, restorePrevious: restore)
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
        levels = []
        elapsed = 0
        state = .idle
        overlayVisible = false

        switch currentSource {
        case .composer(let completion):
            completion(deliveryText)
        case .hotkey:
            break
        }
    }
}
