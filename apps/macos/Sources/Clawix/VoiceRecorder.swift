import Foundation
import AVFoundation
import Speech
import SwiftUI

/// Drives the voice-note flow inside the composer:
/// idle → recording (with live audio meter levels) → transcribing → idle.
///
/// Recording uses `AVAudioRecorder` writing an .m4a temp file and polls
/// `averagePower(forChannel:)` to feed a rolling buffer that the waveform
/// view renders. On stop, the file is fed to `SFSpeechRecognizer` and the
/// recognized text is returned via the completion handler so the composer
/// can append it to `composerText`.
@MainActor
final class VoiceRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var elapsedTimer: Timer?
    private var fileURL: URL?
    private var startedAt: Date?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionLocale = AppLocale.current

    /// Max samples kept in the rolling buffer. The waveform shows the
    /// suffix that fits in the available width, so a buffer slightly
    /// larger than the visible capacity keeps the animation smooth.
    private let maxLevels = 120

    var formattedElapsed: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Start

    func start(locale: Locale = AppLocale.current) {
        guard state == .idle else { return }
        levels = []
        elapsed = 0
        recognitionLocale = locale

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
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

    private func startTimers() {
        levelTimer?.invalidate()
        elapsedTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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
        // Map dB to 0..1 with a soft knee so quiet speech still produces
        // visible bars but loud peaks don't clip everything to max.
        let normalized = CGFloat(pow(10, Double(dB) / 30))
        let clamped = max(0, min(1, normalized))
        levels.append(clamped)
        if levels.count > maxLevels {
            levels.removeFirst(levels.count - maxLevels)
        }
    }

    private func tickElapsed() {
        guard let s = startedAt else { return }
        elapsed = Date().timeIntervalSince(s)
    }

    // MARK: - Stop / cancel

    /// Stop recording and transcribe. Completion fires once with the
    /// recognized text (empty string if recognition failed or was denied).
    func stop(completion: @escaping (String) -> Void) {
        guard state == .recording else { return }
        invalidateTimers()
        recorder?.stop()
        let url = fileURL
        recorder = nil
        startedAt = nil
        state = .transcribing

        guard let url else {
            resetAfterTranscription()
            completion("")
            return
        }
        transcribe(url: url, completion: completion)
    }

    /// Stop recording without transcribing. Used if the user wants to
    /// abandon the take (e.g. via Esc — currently unused but kept for parity).
    func cancel() {
        invalidateTimers()
        recorder?.stop()
        recorder = nil
        startedAt = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        levels = []
        elapsed = 0
        state = .idle
    }

    private func invalidateTimers() {
        levelTimer?.invalidate(); levelTimer = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
    }

    // MARK: - Transcription

    private func transcribe(url: URL, completion: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized,
                      let recognizer = SFSpeechRecognizer(locale: self.recognitionLocale),
                      recognizer.isAvailable
                else {
                    self.cleanup(url: url)
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
                            self.cleanup(url: url)
                            self.resetAfterTranscription()
                            completion(text)
                        } else if error != nil {
                            self.recognitionTask = nil
                            self.cleanup(url: url)
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
