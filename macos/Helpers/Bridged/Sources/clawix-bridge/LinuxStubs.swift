#if !canImport(AVFoundation)
import Foundation
import ClawixCore
import ClawixEngine

// Linux stubs that satisfy call sites in `main.swift` which on Apple
// platforms rely on AVFoundation-backed audio helpers,
// `DictationModelManager` and `TranscriptionService`. The real types
// depend on AVFoundation + WhisperKit and therefore do not compile on
// Linux. Until the Linux daemon ships a whisper.cpp-backed engine,
// these stubs make remote dictation requests and audio replays return
// "not available" instead of failing the build.

public enum AudioCatalogRegistration {
    public static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/m4a", "audio/mp4", "audio/x-m4a": return "m4a"
        case "audio/aac": return "aac"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/ogg", "audio/opus": return "ogg"
        case "audio/flac": return "flac"
        case "audio/caf", "audio/x-caf": return "caf"
        default: return "m4a"
        }
    }

    public static func register(
        client: ClawJSAudioClient,
        id: String? = nil,
        kind: String,
        appId: String,
        originActor: String,
        audioData: Data,
        mimeType: String,
        deviceId: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil,
        linkedMessageId: String? = nil,
        metadataJson: String? = nil,
        transcript: ClawJSAudioClient.RegisterTranscriptInput? = nil
    ) async throws -> WireAudioRef {
        throw ClawJSAudioClient.Error.serviceNotReady
    }
}

public enum DictationModel: String, Sendable {
    case `default`
}

public enum DictationModelManager {
    public static let activeModelDefaultsKey = "ClawixBridge.Dictation.ActiveModel"
}

public enum TranscriptionService {
    public static let shared = TranscriptionService.self

    public static func transcribe(
        fileURL: URL,
        using model: DictationModel,
        language: String?
    ) async throws -> String {
        ""
    }
}
#endif
