import Foundation
import ClawixCore
import ClawixEngine

struct IngestedAudioAttachment {
    var ref: WireAudioRef
    var transcript: String
}

extension DaemonEngineHost {
    func ingestAudioAttachments(
        _ attachments: [WireAttachment],
        threadId: String,
        chatId: String,
        messageId: String,
        providedTranscript: String
    ) async throws -> IngestedAudioAttachment? {
        guard !attachments.isEmpty else { return nil }
        let normalizedTranscript = providedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTranscript = normalizedTranscript.isEmpty
            ? await transcribeFirstAudioAttachment(attachments)
            : nil

        guard let client = audioCatalogClient else {
            throw ClawJSAudioClient.Error.serviceNotReady
        }
        var lastEntry: IngestedAudioAttachment?
        for attachment in attachments {
            guard let data = Data(base64Encoded: attachment.dataBase64) else {
                BridgeLog.write("audio attachment decode failed id=\(attachment.id)")
                continue
            }
            let transcript = normalizedTranscript.isEmpty ? (fallbackTranscript ?? "") : normalizedTranscript
            let ref = try await AudioCatalogRegistration.register(
                client: client,
                id: attachment.id,
                kind: WireAudioKind.user_message.rawValue,
                appId: "clawix",
                originActor: WireAudioOriginActor.user.rawValue,
                audioData: data,
                mimeType: attachment.mimeType,
                threadId: threadId,
                linkedMessageId: messageId,
                transcript: transcript.isEmpty ? nil : .init(
                    text: transcript,
                    role: "transcription",
                    provider: normalizedTranscript.isEmpty ? "daemonWhisper" : "transcribeAudio"
                )
            )
            lastEntry = IngestedAudioAttachment(ref: ref, transcript: transcript)
        }
        return lastEntry
    }

    private func transcribeFirstAudioAttachment(_ attachments: [WireAttachment]) async -> String? {
        let suiteName = ClawixEnv.value(ClawixEnv.bridgeDefaultsSuite)
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let activeRaw = defaults.string(forKey: DictationModelManager.activeModelDefaultsKey) ?? ""
        let model = DictationModel(rawValue: activeRaw) ?? .default
        guard let first = attachments.first, let data = Data(base64Encoded: first.dataBase64) else { return nil }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawix-attachments", isDirectory: true)
            .appendingPathComponent("ingest", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let ext = AudioCatalogRegistration.fileExtension(for: first.mimeType)
        let tmpURL = tmpDir.appendingPathComponent("\(first.id).\(ext)")
        try? data.write(to: tmpURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        return try? await TranscriptionService.shared.transcribe(
            fileURL: tmpURL,
            using: model,
            language: nil
        )
    }
}
