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

        case .sendPrompt(let chatIdString, let text, let attachments):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            host?.handleSendPrompt(chatId: uuid, text: text, attachments: attachments)

        case .newChat(let chatIdString, let text, let attachments):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            // Auto-subscribe so the bus pushes message-level deltas for
            // the freshly created chat without an extra `openChat` round
            // trip from the client.
            _ = bus.subscribe(chatId: chatIdString)
            host?.handleNewChat(chatId: uuid, text: text, attachments: attachments)

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

        case .transcribeAudio(let requestId, let audioBase64, let mimeType, let language):
            host?.handleTranscribeAudio(
                requestId: requestId,
                audioBase64: audioBase64,
                mimeType: mimeType,
                language: language,
                reply: { [weak session] text, errorMessage in
                    session?.send(BridgeFrame(.transcriptionResult(
                        requestId: requestId,
                        text: text,
                        errorMessage: errorMessage
                    )))
                }
            )

        case .auth, .authOk, .authFailed, .versionMismatch,
             .chatsSnapshot, .chatUpdated, .messagesSnapshot,
             .messageAppended, .messageStreaming, .errorEvent,
             .pairingPayload, .projectsSnapshot, .fileSnapshot,
             .transcriptionResult:
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
///
/// In dummy / fixture mode, the rollouts reference paths that don't
/// exist on this Mac (e.g. `/Users/demo/Code/Sample App/src/search/query.sql`).
/// To keep the file viewer functional, set the env var
/// `CLAWIX_FILE_FIXTURE_DIR=<dir>`. The reader then falls back, in order,
/// to: (a) a real file mirrored under `<dir>/<absolute path>`, so the
/// user can drop hand-crafted content for specific paths, and (b) a
/// synthesized body inferred from the basename and extension, so every
/// pill resolves to plausible content even without curation.
public enum BridgeFileReader {

    /// Opaque result used both by the bridge wire reply and the macOS
    /// `FileViewerPanel`. Keeps the on-disk → fixture → synthesized
    /// resolution in one place.
    public struct Result: Sendable {
        public let content: String?
        public let isMarkdown: Bool
        public let error: String?
        public init(content: String?, isMarkdown: Bool, error: String?) {
            self.content = content
            self.isMarkdown = isMarkdown
            self.error = error
        }
    }

    public static func read(path: String) -> BridgeBody {
        let result = load(path: path)
        return .fileSnapshot(
            path: path,
            content: result.content,
            isMarkdown: result.isMarkdown,
            error: result.error
        )
    }

    public static func load(path: String) -> Result {
        let url = URL(fileURLWithPath: path)
        let onDisk = FileManager.default.fileExists(atPath: url.path)
        let fixtureDir = ProcessInfo.processInfo.environment["CLAWIX_FILE_FIXTURE_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 }

        if onDisk {
            return decode(url: url, originalPath: path)
        }

        if let dir = fixtureDir {
            let mirrored = URL(fileURLWithPath: dir)
                .appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            if FileManager.default.fileExists(atPath: mirrored.path) {
                return decode(url: mirrored, originalPath: path)
            }
            let synthesized = FixtureFileSynthesizer.synthesize(for: path)
            let isMarkdown = isMarkdownExtension(url.pathExtension)
            return Result(content: synthesized, isMarkdown: isMarkdown, error: nil)
        }

        return Result(content: nil, isMarkdown: false, error: "File not found")
    }

    private static func decode(url: URL, originalPath: String) -> Result {
        guard let data = try? Data(contentsOf: url) else {
            return Result(content: nil, isMarkdown: false, error: "Couldn't read file")
        }
        if data.prefix(4096).contains(0) {
            return Result(content: nil, isMarkdown: false, error: "Preview not available for binary files")
        }
        guard let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .utf16) else {
            return Result(content: nil, isMarkdown: false, error: "Couldn't decode file as text")
        }
        let ext = URL(fileURLWithPath: originalPath).pathExtension
        return Result(content: raw, isMarkdown: isMarkdownExtension(ext), error: nil)
    }

    private static func isMarkdownExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "md" || lower == "markdown"
    }
}
