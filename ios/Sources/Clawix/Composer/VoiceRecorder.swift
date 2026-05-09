import Foundation
import AVFoundation
import Speech
import SwiftUI

// iOS counterpart of the macOS VoiceRecorder. Captures voice with
// `AVAudioRecorder` writing an .m4a temp file, polls
// `averagePower(forChannel:)` to feed the live waveform, and on stop
// hands the file to `SFSpeechRecognizer` for on-device transcription.
//
// Two iOS-specific bits compared to the Mac side:
//   * the audio session has to be configured to `.record` before
//     recording, otherwise AVAudioRecorder silently refuses to start
//   * permission is requested via `AVAudioApplication.requestRecordPermission`
//     (the iOS 17+ replacement for `AVAudioSession.requestRecordPermission`)
@MainActor
final class VoiceRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case transcribing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var elapsed: TimeInterval = 0

    /// Optional remote transcriber. When set the recorder ships the
    /// captured m4a to this closure (typically `BridgeStore` forwarding
    /// it to the Mac daemon for Whisper) and falls back to on-device
    /// `SFSpeechRecognizer` only if it throws. Letting the caller wire
    /// this up keeps `VoiceRecorder` decoupled from the bridge layer.
    var bridgeTranscriber: ((URL, String?) async throws -> String)?

    /// Whisper-style language hint sent to the bridge call. `nil`
    /// means auto-detect. Set by the caller before `start(...)`; the
    /// recorder forwards it to the bridge transcriber.
    var bridgeLanguage: String?

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var elapsedTimer: Timer?
    private var fileURL: URL?
    private var startedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionLocale: Locale = .current

    private let maxLevels = 120

    var formattedElapsed: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Start

    func start(locale: Locale = .current) {
        guard state == .idle else { return }
        levels = []
        elapsed = 0
        accumulatedElapsed = 0
        recognitionLocale = locale

        #if os(iOS)
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { return }
                self.beginRecording()
            }
        }
        #endif
    }

    private func beginRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            return
        }
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix_voice_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { return }
            recorder = r
            fileURL = url
            startedAt = Date()
            state = .recording
            startTimers()
        } catch {
            // Stay idle silently. The composer mic button will appear unchanged.
        }
    }

    // MARK: - Pause / resume

    func pause() {
        guard state == .recording, let r = recorder else { return }
        r.pause()
        if let s = startedAt {
            accumulatedElapsed += Date().timeIntervalSince(s)
        }
        startedAt = nil
        invalidateTimers()
        state = .paused
    }

    func resume() {
        guard state == .paused, let r = recorder else { return }
        guard r.record() else { return }
        startedAt = Date()
        state = .recording
        startTimers()
    }

    private func startTimers() {
        levelTimer?.invalidate()
        elapsedTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickLevel() }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func tickLevel() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        let dB = r.averagePower(forChannel: 0)        // -160 ... 0
        let normalized = CGFloat(pow(10, Double(dB) / 30))
        let clamped = max(0, min(1, normalized))
        levels.append(clamped)
        if levels.count > maxLevels {
            levels.removeFirst(levels.count - maxLevels)
        }
    }

    private func tickElapsed() {
        let live = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = accumulatedElapsed + live
    }

    // MARK: - Stop / cancel

    /// Stop recording and transcribe. Completion fires once with the
    /// recognized text (empty string if recognition failed or was denied).
    func stop(completion: @escaping (String) -> Void) {
        stopAndCapture(keepFile: false) { transcript, _ in completion(transcript) }
    }

    /// Variant of `stop` that hands the captured audio URL back to the
    /// caller alongside the transcript, and skips the automatic file
    /// cleanup so the bytes stay around long enough to ship over the
    /// bridge as an audio attachment. The caller is responsible for
    /// deleting the file once it's done with it.
    func stopAndKeep(completion: @escaping (String, URL?) -> Void) {
        stopAndCapture(keepFile: true, completion: completion)
    }

    private func stopAndCapture(keepFile: Bool, completion: @escaping (String, URL?) -> Void) {
        guard state == .recording || state == .paused else { return }
        invalidateTimers()
        recorder?.stop()
        let url = fileURL
        recorder = nil
        startedAt = nil
        accumulatedElapsed = 0
        state = .transcribing

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif

        guard let url else {
            resetAfterTranscription()
            completion("", nil)
            return
        }
        transcribe(url: url, keepFile: keepFile) { transcript in
            completion(transcript, keepFile ? url : nil)
        }
    }

    /// Stop recording without transcribing. Used when the user dismisses
    /// the overlay before deciding whether to send.
    func cancel() {
        invalidateTimers()
        recorder?.stop()
        recorder = nil
        startedAt = nil
        accumulatedElapsed = 0
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        levels = []
        elapsed = 0
        state = .idle
        recognitionTask?.cancel()
        recognitionTask = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private func invalidateTimers() {
        levelTimer?.invalidate(); levelTimer = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
    }

    // MARK: - Transcription

    private func transcribe(url: URL, keepFile: Bool = false, completion: @escaping (String) -> Void) {
        // Prefer the bridge transcriber when available so the iPhone
        // gets the same Whisper output the Mac dictation flow does.
        // If the bridge isn't connected or the daemon errored, fall
        // through to the on-device Apple Speech path. When `keepFile`
        // is true we hand the URL back to the caller (sendAsAudio
        // flow ships the bytes as an attachment) so we don't delete
        // it here; the caller deletes once shipping is done.
        if let bridgeTranscriber {
            Task { [weak self] in
                do {
                    let text = try await bridgeTranscriber(url, self?.bridgeLanguage)
                    await MainActor.run {
                        guard let self else { return }
                        if !keepFile { self.cleanup(url: url) }
                        else { self.fileURL = nil }
                        self.resetAfterTranscription()
                        completion(text)
                    }
                } catch {
                    // Soft fallback: try Apple Speech with the same
                    // file, so the user still gets a transcript when
                    // the Mac is unreachable.
                    self?.transcribeWithSpeech(url: url, keepFile: keepFile, completion: completion)
                }
            }
            return
        }
        transcribeWithSpeech(url: url, keepFile: keepFile, completion: completion)
    }

    private func transcribeWithSpeech(url: URL, keepFile: Bool = false, completion: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                let cleanupAfter: () -> Void = {
                    if keepFile { self.fileURL = nil } else { self.cleanup(url: url) }
                }
                guard status == .authorized,
                      let recognizer = SFSpeechRecognizer(locale: self.recognitionLocale),
                      recognizer.isAvailable
                else {
                    cleanupAfter()
                    self.resetAfterTranscription()
                    completion("")
                    return
                }

                let req = SFSpeechURLRecognitionRequest(url: url)
                req.shouldReportPartialResults = false
                if recognizer.supportsOnDeviceRecognition {
                    req.requiresOnDeviceRecognition = true
                }

                self.recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let result, result.isFinal {
                            let text = result.bestTranscription.formattedString
                            self.recognitionTask = nil
                            cleanupAfter()
                            self.resetAfterTranscription()
                            completion(text)
                        } else if error != nil {
                            self.recognitionTask = nil
                            cleanupAfter()
                            self.resetAfterTranscription()
                            completion("")
                        }
                    }
                }
            }
        }
    }

    private func resetAfterTranscription() {
        levels = []
        elapsed = 0
        state = .idle
    }

    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
        fileURL = nil
    }
}
