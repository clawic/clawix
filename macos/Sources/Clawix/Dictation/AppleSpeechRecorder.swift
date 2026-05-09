import Foundation
import AVFoundation
import Speech

/// Native macOS Speech Recognition backend (#22). Lives parallel to
/// the existing AUHAL → WhisperKit path; the user picks one in
/// Settings via `dictation.transcriptionBackend`. Apple's recognizer
/// streams partials as you speak (cornerstone of #19 Live preview)
/// and is free of API keys / model downloads — at the cost of being
/// noticeably less accurate than Whisper Large in noisy environments
/// or with thick accents.
///
/// `delegate?.appleSpeechDidEmitPartial` fires repeatedly as the
/// recognizer refines its best guess; `appleSpeechDidFinalize` fires
/// once when stop() lands the final transcript.
@MainActor
final class AppleSpeechRecorder: NSObject {

    /// Callback for streaming partials (live preview).
    var onPartial: ((String) -> Void)?
    /// Callback for the final transcript when `stop()` resolves.
    /// Empty string means recognition produced nothing usable.
    var onFinal: ((String) -> Void)?
    /// Callback for non-recoverable errors. Always pairs with an
    /// empty `onFinal` so the coordinator's cleanup path runs.
    var onError: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isRunning = false
    /// Best-known partial since the last reset; shipped to `onPartial`
    /// so the overlay can render it as the user keeps speaking.
    private var latestPartial: String = ""

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Start streaming recognition. `language` is a BCP-47 locale
    /// string ("en-US", "es-ES"); `nil` falls back to Apple's default
    /// recognizer locale. Throws on engine startup failure so the
    /// coordinator can surface a usable error to the user.
    func start(language: String?) throws {
        guard !isRunning else { return }
        latestPartial = ""

        let locale: Locale
        if let language, !language.isEmpty, language != "auto" {
            // Apple expects BCP-47 ("en-US"). Whisper uses ISO 639-1
            // ("en"). Promote bare codes to a sensible regional form
            // so the recognizer doesn't reject them.
            locale = Self.bcp47Locale(from: language)
        } else {
            locale = .current
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw RecorderError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw RecorderError.notAvailable
        }
        // On-device when possible: keeps audio out of Apple's cloud
        // and matches the user's expectation that local Whisper is
        // private. Falls back to network if the locale's on-device
        // model isn't installed.
        recognizer.defaultTaskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            // Configure on-device on the request below.
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        // Wire the engine's input node to the recognition request.
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.latestPartial = text
                    self.onPartial?(text)
                    if result.isFinal {
                        self.cleanupEngine()
                        self.onFinal?(text)
                    }
                } else if let error {
                    self.cleanupEngine()
                    self.onError?(error.localizedDescription)
                    self.onFinal?(self.latestPartial)
                }
            }
        }

        isRunning = true
    }

    /// Stop recognition and emit the final transcript via `onFinal`.
    /// Idempotent so the coordinator's cleanup path can call it
    /// without checking state.
    func stop() {
        guard isRunning else { return }
        request?.endAudio()
        // The recognizer fires `result.isFinal=true` shortly after
        // endAudio(); we don't tear down the engine here so the
        // final result still flows through onFinal.
    }

    /// Force-cancel; no final result fired.
    func cancel() {
        guard isRunning else { return }
        cleanupEngine()
    }

    private func cleanupEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        isRunning = false
    }

    private static func bcp47Locale(from code: String) -> Locale {
        // Map common ISO 639-1 codes to a sensible BCP-47 default.
        // Anything not in the map is passed through as-is and Apple
        // either accepts it or returns nil (handled at the call site).
        let fallback: [String: String] = [
            "en": "en-US",
            "es": "es-ES",
            "fr": "fr-FR",
            "de": "de-DE",
            "it": "it-IT",
            "pt": "pt-BR",
            "ja": "ja-JP",
            "zh": "zh-CN",
            "ko": "ko-KR",
            "ru": "ru-RU",
            "ar": "ar-SA",
            "hi": "hi-IN"
        ]
        if let mapped = fallback[code.lowercased()] {
            return Locale(identifier: mapped)
        }
        return Locale(identifier: code)
    }

    enum RecorderError: Error, LocalizedError {
        case notAvailable
        case unsupportedLocale(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Speech recognition isn't available right now."
            case .unsupportedLocale(let id):
                return "Apple Speech doesn't support locale \(id)."
            }
        }
    }
}

/// Names of the available transcription backends. Default is
/// `whisperLocal` — the existing path that ships with the app. Cloud
/// variants share a common multipart-WAV upload path implemented in
/// `CloudTranscriptionProvider`.
enum DictationTranscriptionBackend: String, CaseIterable {
    case whisperLocal
    case appleSpeech
    case groqCloud
    case deepgramCloud
    case customCloud

    var displayName: String {
        switch self {
        case .whisperLocal:  return "Whisper (local)"
        case .appleSpeech:   return "Apple Speech (streaming)"
        case .groqCloud:     return "Groq (cloud)"
        case .deepgramCloud: return "Deepgram (cloud)"
        case .customCloud:   return "Custom Whisper endpoint"
        }
    }

    var description: String {
        switch self {
        case .whisperLocal:
            return "Highest accuracy. Requires a downloaded Whisper model."
        case .appleSpeech:
            return "Streaming partials, no model download. Less accurate in noisy environments."
        case .groqCloud:
            return "<200 ms latency. Whisper-large-v3 hosted; needs a Groq API key."
        case .deepgramCloud:
            return "Nova-3 cloud. Punctuation + smart formatting; needs a Deepgram key."
        case .customCloud:
            return "Any OpenAI-compatible /audio/transcriptions endpoint."
        }
    }

    /// True when the backend uploads via `CloudTranscriptionProvider`
    /// rather than running locally.
    var isCloud: Bool {
        switch self {
        case .whisperLocal, .appleSpeech: return false
        case .groqCloud, .deepgramCloud, .customCloud: return true
        }
    }

    /// Map to the cloud provider implementation. Nil for local
    /// backends.
    var cloudProvider: CloudTranscriptionProvider? {
        switch self {
        case .groqCloud:     return .groq
        case .deepgramCloud: return .deepgram
        case .customCloud:   return .custom
        case .whisperLocal, .appleSpeech: return nil
        }
    }
}
