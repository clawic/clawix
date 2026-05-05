import Foundation

/// Wire-format version exchanged in every frame. Bumped on any breaking
/// change to `BridgeFrame` payloads. Clients refuse to talk to a peer
/// reporting a different `schemaVersion` and surface an "update Clawix"
/// empty state.
///
/// v2 (2026-05): Added `clientKind` capability tag to `auth` so the
/// server can tell apart the iPhone companion from a co-located desktop
/// client (the macOS GUI talking to the LaunchAgent daemon over
/// loopback). Added desktop-only frame types for chat editing
/// (`editPrompt`), archive/pin toggles, project listing, and the
/// pairing handshake the GUI uses to ask the daemon for a fresh QR.
/// v1 frames decode cleanly into v2 because every new field is optional
/// and every new frame type is additive.
public let bridgeSchemaVersion: Int = 2

/// Kind of client speaking on a session. Affects which frame types the
/// server is willing to dispatch:
///
/// - `.ios` is the read-mostly mobile companion: list/open chats and
///   send prompts, but not the chat-mutation grab-bag.
/// - `.desktop` is the macOS GUI talking to the LaunchAgent daemon. It
///   gets the full surface (edit, archive, pin, branch switch, project
///   selection, pairing token issuance, auth coordinator, etc.).
///
/// Old v1 iPhones don't send a `clientKind`; the server treats absent
/// as `.ios` so they keep working unchanged.
public enum ClientKind: String, Codable, Equatable, Sendable {
    case ios
    case desktop
}

public struct BridgeFrame: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let body: BridgeBody

    public init(_ body: BridgeBody, schemaVersion: Int = bridgeSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.body = body
    }

    private enum TopKeys: String, CodingKey {
        case schemaVersion
        case type
    }

    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: TopKeys.self)
        self.schemaVersion = try top.decode(Int.self, forKey: .schemaVersion)
        let type = try top.decode(String.self, forKey: .type)
        self.body = try BridgeBody.decode(type: type, from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        var top = encoder.container(keyedBy: TopKeys.self)
        try top.encode(schemaVersion, forKey: .schemaVersion)
        try top.encode(body.typeTag, forKey: .type)
        try body.encodePayload(to: encoder)
    }
}

/// All discriminated frame bodies. Wire format is flat: every frame
/// carries `schemaVersion`, `type`, and the payload fields at the top
/// level (no `payload` envelope) so log lines stay readable.
public enum BridgeBody: Equatable, Sendable {
    // MARK: - v1 outbound (iPhone -> Mac)
    case auth(token: String, deviceName: String?, clientKind: ClientKind?)
    case listChats
    case openChat(chatId: String)
    case sendPrompt(chatId: String, text: String)

    // MARK: - v1 inbound (Mac -> iPhone)
    case authOk(macName: String?)
    case authFailed(reason: String)
    case versionMismatch(serverVersion: Int)
    case chatsSnapshot(chats: [WireChat])
    case chatUpdated(chat: WireChat)
    case messagesSnapshot(chatId: String, messages: [WireMessage])
    case messageAppended(chatId: String, message: WireMessage)
    /// Carries the full current state of the message (content +
    /// reasoning) every tick, not deltas. The iPhone replaces. Trades
    /// a few extra KB on LAN for no append/delta correctness bugs.
    case messageStreaming(
        chatId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    )
    case errorEvent(code: String, message: String)

    // MARK: - v2 outbound (desktop client -> daemon)
    /// Edit a prompt in place and re-run the turn. `chatId` is the
    /// chat, `messageId` is the user message being rewritten, `text`
    /// is the new content. Daemon truncates the rollout at this turn,
    /// applies the new prompt, and re-streams.
    case editPrompt(chatId: String, messageId: String, text: String)
    /// Toggle the archived flag. Sticks across relaunches because the
    /// archive state lives in the GRDB database the daemon owns.
    case archiveChat(chatId: String)
    case unarchiveChat(chatId: String)
    /// Toggle the pinned flag.
    case pinChat(chatId: String)
    case unpinChat(chatId: String)
    /// Ask the daemon for a fresh pairing payload (token + QR JSON).
    /// Used by `PairWindowView` in the GUI.
    case pairingStart
    /// Ask the daemon for the current list of projects derived from
    /// chats + manual additions. Reply is `projectsSnapshot`.
    case listProjects

    // MARK: - v2 inbound (daemon -> desktop client)
    /// Reply to `pairingStart`. The QR is what the iPhone scans; the
    /// bearer is what the daemon will accept on the next `auth` frame
    /// from a fresh iPhone.
    case pairingPayload(qrJson: String, bearer: String)
    /// Reply to `listProjects`.
    case projectsSnapshot(projects: [WireProject])

    fileprivate var typeTag: String {
        switch self {
        case .auth:               return "auth"
        case .listChats:          return "listChats"
        case .openChat:           return "openChat"
        case .sendPrompt:         return "sendPrompt"
        case .authOk:             return "authOk"
        case .authFailed:         return "authFailed"
        case .versionMismatch:    return "versionMismatch"
        case .chatsSnapshot:      return "chatsSnapshot"
        case .chatUpdated:        return "chatUpdated"
        case .messagesSnapshot:   return "messagesSnapshot"
        case .messageAppended:    return "messageAppended"
        case .messageStreaming:   return "messageStreaming"
        case .errorEvent:         return "errorEvent"
        case .editPrompt:         return "editPrompt"
        case .archiveChat:        return "archiveChat"
        case .unarchiveChat:      return "unarchiveChat"
        case .pinChat:            return "pinChat"
        case .unpinChat:          return "unpinChat"
        case .pairingStart:       return "pairingStart"
        case .pairingPayload:     return "pairingPayload"
        case .listProjects:       return "listProjects"
        case .projectsSnapshot:   return "projectsSnapshot"
        }
    }

    private enum FlatKeys: String, CodingKey {
        case token, deviceName, clientKind
        case chatId, text, messageId
        case macName, reason, serverVersion
        case chats, chat, messages, message
        case content, reasoningText, finished
        case code
        case qrJson, bearer
        case projects
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlatKeys.self)
        switch self {
        case .auth(let token, let deviceName, let clientKind):
            try c.encode(token, forKey: .token)
            try c.encodeIfPresent(deviceName, forKey: .deviceName)
            try c.encodeIfPresent(clientKind, forKey: .clientKind)
        case .listChats:
            break
        case .openChat(let chatId):
            try c.encode(chatId, forKey: .chatId)
        case .sendPrompt(let chatId, let text):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(text, forKey: .text)
        case .authOk(let macName):
            try c.encodeIfPresent(macName, forKey: .macName)
        case .authFailed(let reason):
            try c.encode(reason, forKey: .reason)
        case .versionMismatch(let serverVersion):
            try c.encode(serverVersion, forKey: .serverVersion)
        case .chatsSnapshot(let chats):
            try c.encode(chats, forKey: .chats)
        case .chatUpdated(let chat):
            try c.encode(chat, forKey: .chat)
        case .messagesSnapshot(let chatId, let messages):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messages, forKey: .messages)
        case .messageAppended(let chatId, let message):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(message, forKey: .message)
        case .messageStreaming(let chatId, let messageId, let content, let reasoningText, let finished):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(content, forKey: .content)
            try c.encode(reasoningText, forKey: .reasoningText)
            try c.encode(finished, forKey: .finished)
        case .errorEvent(let code, let message):
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case .editPrompt(let chatId, let messageId, let text):
            try c.encode(chatId, forKey: .chatId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(text, forKey: .text)
        case .archiveChat(let chatId), .unarchiveChat(let chatId),
             .pinChat(let chatId), .unpinChat(let chatId):
            try c.encode(chatId, forKey: .chatId)
        case .pairingStart, .listProjects:
            break
        case .pairingPayload(let qrJson, let bearer):
            try c.encode(qrJson, forKey: .qrJson)
            try c.encode(bearer, forKey: .bearer)
        case .projectsSnapshot(let projects):
            try c.encode(projects, forKey: .projects)
        }
    }

    fileprivate static func decode(type: String, from decoder: Decoder) throws -> BridgeBody {
        let c = try decoder.container(keyedBy: FlatKeys.self)
        switch type {
        case "auth":
            return .auth(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName),
                clientKind: try c.decodeIfPresent(ClientKind.self, forKey: .clientKind)
            )
        case "listChats":
            return .listChats
        case "openChat":
            return .openChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "sendPrompt":
            return .sendPrompt(
                chatId: try c.decode(String.self, forKey: .chatId),
                text: try c.decode(String.self, forKey: .text)
            )
        case "authOk":
            return .authOk(macName: try c.decodeIfPresent(String.self, forKey: .macName))
        case "authFailed":
            return .authFailed(reason: try c.decode(String.self, forKey: .reason))
        case "versionMismatch":
            return .versionMismatch(serverVersion: try c.decode(Int.self, forKey: .serverVersion))
        case "chatsSnapshot":
            return .chatsSnapshot(chats: try c.decode([WireChat].self, forKey: .chats))
        case "chatUpdated":
            return .chatUpdated(chat: try c.decode(WireChat.self, forKey: .chat))
        case "messagesSnapshot":
            return .messagesSnapshot(
                chatId: try c.decode(String.self, forKey: .chatId),
                messages: try c.decode([WireMessage].self, forKey: .messages)
            )
        case "messageAppended":
            return .messageAppended(
                chatId: try c.decode(String.self, forKey: .chatId),
                message: try c.decode(WireMessage.self, forKey: .message)
            )
        case "messageStreaming":
            return .messageStreaming(
                chatId: try c.decode(String.self, forKey: .chatId),
                messageId: try c.decode(String.self, forKey: .messageId),
                content: try c.decode(String.self, forKey: .content),
                reasoningText: try c.decode(String.self, forKey: .reasoningText),
                finished: try c.decode(Bool.self, forKey: .finished)
            )
        case "errorEvent":
            return .errorEvent(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message)
            )
        case "editPrompt":
            return .editPrompt(
                chatId: try c.decode(String.self, forKey: .chatId),
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text)
            )
        case "archiveChat":
            return .archiveChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "unarchiveChat":
            return .unarchiveChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "pinChat":
            return .pinChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "unpinChat":
            return .unpinChat(chatId: try c.decode(String.self, forKey: .chatId))
        case "pairingStart":
            return .pairingStart
        case "pairingPayload":
            return .pairingPayload(
                qrJson: try c.decode(String.self, forKey: .qrJson),
                bearer: try c.decode(String.self, forKey: .bearer)
            )
        case "listProjects":
            return .listProjects
        case "projectsSnapshot":
            return .projectsSnapshot(projects: try c.decode([WireProject].self, forKey: .projects))
        default:
            throw BridgeDecodingError.unknownType(type)
        }
    }
}

public enum BridgeDecodingError: Error, Equatable {
    case unknownType(String)
}

public enum BridgeCoder {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ frame: BridgeFrame) throws -> Data {
        try encoder.encode(frame)
    }

    public static func decode(_ data: Data) throws -> BridgeFrame {
        try decoder.decode(BridgeFrame.self, from: data)
    }
}
