import Foundation

/// Wire-format version exchanged in every frame. Bumped on any breaking
/// change to `BridgeFrame` payloads. The iPhone refuses to talk to a Mac
/// reporting a different `schemaVersion` and surfaces an "update Clawix
/// on the Mac" empty state.
public let bridgeSchemaVersion: Int = 1

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
    // Outbound (iPhone -> Mac)
    case auth(token: String, deviceName: String?)
    case listChats
    case openChat(chatId: String)
    case sendPrompt(chatId: String, text: String)

    // Inbound (Mac -> iPhone)
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
        }
    }

    private enum FlatKeys: String, CodingKey {
        case token, deviceName
        case chatId, text, messageId
        case macName, reason, serverVersion
        case chats, chat, messages, message
        case content, reasoningText, finished
        case code
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlatKeys.self)
        switch self {
        case .auth(let token, let deviceName):
            try c.encode(token, forKey: .token)
            try c.encodeIfPresent(deviceName, forKey: .deviceName)
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
        }
    }

    fileprivate static func decode(type: String, from decoder: Decoder) throws -> BridgeBody {
        let c = try decoder.container(keyedBy: FlatKeys.self)
        switch type {
        case "auth":
            return .auth(
                token: try c.decode(String.self, forKey: .token),
                deviceName: try c.decodeIfPresent(String.self, forKey: .deviceName)
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
