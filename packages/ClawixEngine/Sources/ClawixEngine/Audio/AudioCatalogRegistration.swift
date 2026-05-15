#if canImport(AVFoundation)
import Foundation
import AVFoundation
import ClawixCore

public enum AudioCatalogRegistration {
    @discardableResult
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
        let durationMs = durationMs(of: audioData, mimeType: mimeType)
        let result = try await client.register(.init(
            id: id,
            kind: kind,
            appId: appId,
            originActor: originActor,
            mimeType: mimeType,
            bytesBase64: audioData.base64EncodedString(),
            durationMs: durationMs,
            deviceId: deviceId,
            sessionId: sessionId,
            threadId: threadId,
            linkedMessageId: linkedMessageId,
            metadataJson: metadataJson,
            transcript: transcript
        ))
        return WireAudioRef(
            id: result.asset.id,
            mimeType: result.asset.mimeType,
            durationMs: result.asset.durationMs
        )
    }

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

    private static func durationMs(of data: Data, mimeType: String) -> Int {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-audio-duration-\(UUID().uuidString).\(fileExtension(for: mimeType))")
        do {
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            guard let file = try? AVAudioFile(forReading: url) else { return 0 }
            let frames = Double(file.length)
            let sampleRate = file.processingFormat.sampleRate
            guard sampleRate > 0 else { return 0 }
            let seconds = frames / sampleRate
            guard seconds.isFinite, seconds > 0 else { return 0 }
            return Int((seconds * 1000).rounded())
        } catch {
            return 0
        }
    }
}
#endif
