#if !canImport(AVFoundation)
import Foundation

// Linux stubs that satisfy call sites in `main.swift` which on Apple
// platforms rely on `ClawixEngine.AudioMessageStore` /
// `DictationModelManager` / `TranscriptionService`. The real types
// depend on AVFoundation + WhisperKit and therefore do not compile on
// Linux. Until the Linux daemon ships a whisper.cpp-backed engine,
// these stubs make remote dictation requests and audio replays return
// "not available" instead of failing the build.

public struct AudioMessageEntry: Sendable {
    public let id: String
    public let mimeType: String
    public let durationMs: Int
}

public struct AudioMessagePayload: Sendable {
    public let data: Data
    public let mimeType: String
}

public actor AudioMessageStore {
    public static let shared = AudioMessageStore()

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

    public func data(forAudioId audioId: String) async -> AudioMessagePayload? { nil }

    public func entries(forThread threadId: String) async -> [AudioMessageEntry] { [] }

    public func ingest(
        threadId: String,
        messageId: String,
        data: Data,
        mimeType: String,
        durationMs: Int
    ) async throws -> AudioMessageEntry {
        AudioMessageEntry(id: messageId, mimeType: mimeType, durationMs: durationMs)
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
