import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

extension AppState: EngineHost {

    public var bridgeChatsCurrent: [BridgeChatSnapshot] {
        chats.map { Self.bridgeSnapshot(from: $0) }
    }

    public var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        $chats
            .map { chats in chats.map { AppState.bridgeSnapshot(from: $0) } }
            .eraseToAnyPublisher()
    }

    public func handleHydrateHistory(sessionId: UUID) {
        hydrateHistoryFromBridge(chatId: sessionId)
    }

    public func handleSendMessage(sessionId: UUID, text: String, attachments: [WireAttachment]) {
        sendUserMessageFromBridge(chatId: sessionId, text: text, attachments: attachments)
    }

    public func handleNewSession(sessionId: UUID, text: String, attachments: [WireAttachment]) {
        newChatFromBridge(chatId: sessionId, text: text, attachments: attachments)
    }

    public func handleInterruptTurn(sessionId: UUID) {
        interruptActiveTurn(chatId: sessionId)
    }

    public func handleRequestAudio(
        audioId: String,
        reply: @MainActor @escaping (String?, String?, String?) -> Void
    ) {
        Task { @MainActor in
            if let client = audioCatalogClient {
                do {
                    let result = try await client.getBytes(audioId: audioId, appId: "clawix")
                    reply(result.base64, result.mimeType, nil)
                    return
                } catch ClawJSAudioClient.Error.notFound {
                    reply(nil, nil, "Audio no longer available")
                    return
                } catch {
                    reply(nil, nil, error.localizedDescription)
                    return
                }
            }
            reply(nil, nil, "Audio catalog is not available")
        }
    }

    public var audioCatalogClient: ClawJSAudioClient? {
        AudioCatalogBootstrap.shared.currentClient
    }

    /// In-process Whisper handler for the iPhone's `transcribeAudio`
    /// frame. Without this, the default `EngineHost` extension would
    /// answer "Transcription is not available on this host" and the
    /// iPhone would fall back to (or hang on) Apple Speech. Mirrors
    /// the daemon path: spool the bytes to a temp file, hand the URL
    /// to `TranscriptionService` (WhisperKit) with the model the user
    /// picked in Settings, then forward the text or a friendly error.
    public func handleTranscribeAudio(
        requestId: String,
        audioBase64: String,
        mimeType: String,
        language: String?,
        reply: @MainActor @escaping (String, String?) -> Void
    ) {
        Task { @MainActor in
            guard let data = Data(base64Encoded: audioBase64) else {
                reply("", "Audio decode failed")
                return
            }
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("clawix-attachments", isDirectory: true)
                .appendingPathComponent("dictation", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let ext = AudioCatalogRegistration.fileExtension(for: mimeType)
                let url = tmpDir.appendingPathComponent("\(requestId).\(ext)")
                try data.write(to: url, options: .atomic)
                let activeRaw = UserDefaults.standard.string(
                    forKey: DictationModelManager.activeModelDefaultsKey
                ) ?? ""
                let model = DictationModel(rawValue: activeRaw) ?? .default
                let text = try await TranscriptionService.shared.transcribe(
                    fileURL: url,
                    using: model,
                    language: language
                )
                try? FileManager.default.removeItem(at: url)
                reply(text, nil)
            } catch {
                reply("", error.localizedDescription)
            }
        }
    }

    private static func bridgeSnapshot(from chat: Chat) -> BridgeChatSnapshot {
        BridgeChatSnapshot(
            chat: chat.toWire(),
            messages: chat.messages.map { $0.toWire() }
        )
    }
}
