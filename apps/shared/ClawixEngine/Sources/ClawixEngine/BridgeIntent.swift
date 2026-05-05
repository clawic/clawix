import Foundation
import ClawixCore

@MainActor
public enum BridgeIntent {

    /// Routes an authenticated inbound frame to the right `EngineHost`
    /// or `BridgeBus` operation. Frames that are server-only or that
    /// have no authenticated meaning are ignored.
    public static func dispatch(
        body: BridgeBody,
        host: EngineHost?,
        bus: BridgeBus,
        session: BridgeSession
    ) {
        switch body {
        case .listChats:
            session.send(BridgeFrame(.chatsSnapshot(chats: bus.currentChats())))

        case .openChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            // Mirror what selecting a chat in the Mac UI does: pull
            // the rollout file off disk so `chat.messages` is populated
            // before we hand it to the bridge subscriber. Without this
            // every `notLoaded` thread shows up empty on the iPhone.
            host?.handleHydrateHistory(chatId: uuid)
            let messages = bus.subscribe(chatId: chatIdString)
            session.send(BridgeFrame(.messagesSnapshot(chatId: chatIdString, messages: messages)))

        case .sendPrompt(let chatIdString, let text):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            host?.handleSendPrompt(chatId: uuid, text: text)

        case .newChat(let chatIdString, let text):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            // Auto-subscribe so the bus pushes message-level deltas for
            // the freshly created chat without an extra `openChat` round
            // trip from the client.
            _ = bus.subscribe(chatId: chatIdString)
            host?.handleNewChat(chatId: uuid, text: text)

        case .editPrompt(let chatIdString, let messageIdString, let text):
            guard let chatUuid = UUID(uuidString: chatIdString),
                  let msgUuid = UUID(uuidString: messageIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badId", message: chatIdString)))
                return
            }
            host?.handleEditPrompt(chatId: chatUuid, messageId: msgUuid, text: text)

        case .archiveChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else { return }
            host?.handleArchiveChat(chatId: uuid, archived: true)
        case .unarchiveChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else { return }
            host?.handleArchiveChat(chatId: uuid, archived: false)
        case .pinChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else { return }
            host?.handlePinChat(chatId: uuid, pinned: true)
        case .unpinChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else { return }
            host?.handlePinChat(chatId: uuid, pinned: false)

        case .pairingStart:
            if let payload = host?.handlePairingStart() {
                session.send(BridgeFrame(.pairingPayload(qrJson: payload.qrJson, bearer: payload.bearer)))
            } else {
                session.send(BridgeFrame(.errorEvent(
                    code: "notImplemented",
                    message: "host does not mint pairing tokens"
                )))
            }

        case .listProjects:
            let projects = host?.currentProjects() ?? []
            session.send(BridgeFrame(.projectsSnapshot(projects: projects)))

        case .readFile(let path):
            session.send(BridgeFrame(BridgeFileReader.read(path: path)))

        case .auth, .authOk, .authFailed, .versionMismatch,
             .chatsSnapshot, .chatUpdated, .messagesSnapshot,
             .messageAppended, .messageStreaming, .errorEvent,
             .pairingPayload, .projectsSnapshot, .fileSnapshot:
            // Either already handled (auth) or server-only.
            break
        }
    }
}

/// Reads a text file off disk for the bridge `readFile` request.
///
/// Mirrors the macOS `FileViewerPanel.load` rules: report a friendly
/// reason for missing files / binary blobs / undecodable bytes instead
/// of leaking raw NSError descriptions, mark `.md` / `.markdown` files
/// so the iPhone renders them with the assistant's markdown view.
public enum BridgeFileReader {
    public static func read(path: String) -> BridgeBody {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fileSnapshot(path: path, content: nil, isMarkdown: false, error: "File not found")
        }
        guard let data = try? Data(contentsOf: url) else {
            return .fileSnapshot(path: path, content: nil, isMarkdown: false, error: "Couldn't read file")
        }
        if data.prefix(4096).contains(0) {
            return .fileSnapshot(path: path, content: nil, isMarkdown: false, error: "Preview not available for binary files")
        }
        guard let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .utf16) else {
            return .fileSnapshot(path: path, content: nil, isMarkdown: false, error: "Couldn't decode file as text")
        }
        let ext = url.pathExtension.lowercased()
        let isMarkdown = ext == "md" || ext == "markdown"
        return .fileSnapshot(path: path, content: raw, isMarkdown: isMarkdown, error: nil)
    }
}
