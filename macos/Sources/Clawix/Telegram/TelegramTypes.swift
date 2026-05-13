import Foundation

/// Wire types matching `clawjs/telegram/src/server/state.ts` and the
/// envelope returned by every action route in `app.ts` (`runClawCli`).
/// Everything here is decoded from the Telegram surface running on
/// `127.0.0.1:CLAW_TELEGRAM_PORT`.

struct TelegramBot: Decodable, Identifiable, Equatable {
    let id: String
    let accountId: String
    let label: String
    let enabled: Bool
    let status: String
    let username: String?
    let firstName: String?
    let maskedCredential: String?
    let webhookUrl: String?
    let pollingActive: Bool?
    let recentErrors: [String]?
    let knownChats: Int?
    let updatedAt: String?
    let workspace: String?

    var displayUsername: String? {
        guard let username, !username.isEmpty else { return nil }
        return username.hasPrefix("@") ? username : "@\(username)"
    }

    var transport: TelegramTransport {
        if let url = webhookUrl, !url.isEmpty { return .webhook(url: url) }
        if pollingActive == true { return .polling }
        return .off
    }
}

enum TelegramTransport: Equatable {
    case off
    case polling
    case webhook(url: String)

    var label: String {
        switch self {
        case .off:     return "Off"
        case .polling: return "Polling"
        case .webhook: return "Webhook"
        }
    }
}

struct TelegramHealth: Decodable, Equatable {
    let ok: Bool
    let surface: String
    let workspace: String
    let clawBinAvailable: Bool
    let now: String
}

/// Generic envelope returned by action endpoints. The Telegram surface
/// shells out to `claw <subcommand> --json`; the parsed JSON (when the
/// CLI emits any) lands in `json` as a free-form payload.
struct ClawCliResult: Decodable, Equatable {
    let ok: Bool
    let exitCode: Int?
    let stdout: String
    let stderr: String
    let json: AnyJSON?
}

struct TelegramCommandSpec: Codable, Identifiable, Equatable, Hashable {
    var command: String
    var description: String

    var id: String { command }
}

struct TelegramKnownChat: Decodable, Identifiable, Equatable {
    let chatId: String
    let title: String?
    let type: String?
    let username: String?

    var id: String { chatId }

    private enum CodingKeys: String, CodingKey {
        case chatId
        case title
        case type
        case username
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .chatId) {
            self.chatId = s
        } else if let n = try? c.decode(Int64.self, forKey: .chatId) {
            self.chatId = String(n)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .chatId,
                in: c,
                debugDescription: "chatId not a string or int"
            )
        }
        self.title = try? c.decode(String.self, forKey: .title)
        self.type = try? c.decode(String.self, forKey: .type)
        self.username = try? c.decode(String.self, forKey: .username)
    }
}

/// Best-effort decoder for whatever the chats CLI returns. The surface
/// forwards raw JSON from `claw telegram chats list --json`; we read the
/// chats out of either the top-level array or `{ chats: [...] }`.
enum TelegramChatsExtractor {
    static func extract(from json: AnyJSON?) -> [TelegramKnownChat] {
        guard let json else { return [] }
        if case let .array(items) = json {
            return items.compactMap(decodeChat)
        }
        if case let .object(dict) = json,
           case let .array(items)? = dict["chats"] {
            return items.compactMap(decodeChat)
        }
        return []
    }

    private static func decodeChat(_ value: AnyJSON) -> TelegramKnownChat? {
        guard case let .object(dict) = value else { return nil }
        let chatId: String?
        if case let .string(s)? = dict["chatId"] {
            chatId = s
        } else if case let .number(n)? = dict["chatId"] {
            chatId = String(Int64(n))
        } else if case let .string(s)? = dict["id"] {
            chatId = s
        } else if case let .number(n)? = dict["id"] {
            chatId = String(Int64(n))
        } else {
            chatId = nil
        }
        guard let chatId else { return nil }
        var title: String?
        if case let .string(s)? = dict["title"] { title = s }
        var type: String?
        if case let .string(s)? = dict["type"] { type = s }
        var username: String?
        if case let .string(s)? = dict["username"] { username = s }
        return TelegramKnownChat(
            chatId: chatId,
            title: title,
            type: type,
            username: username
        )
    }
}

extension TelegramKnownChat {
    init(chatId: String, title: String?, type: String?, username: String?) {
        self.chatId = chatId
        self.title = title
        self.type = type
        self.username = username
    }
}

extension TelegramCommandSpec {
    /// Best-effort decoder of the array of `{command, description}` the
    /// CLI emits via `telegram commands get --json`.
    static func extract(from json: AnyJSON?) -> [TelegramCommandSpec] {
        guard let json else { return [] }
        let array: [AnyJSON]
        if case let .array(items) = json {
            array = items
        } else if case let .object(dict) = json,
                  case let .array(items)? = dict["commands"] {
            array = items
        } else {
            return []
        }
        return array.compactMap { value in
            guard case let .object(dict) = value,
                  case let .string(command)? = dict["command"] else { return nil }
            let description: String
            if case let .string(s)? = dict["description"] {
                description = s
            } else {
                description = ""
            }
            return TelegramCommandSpec(command: command, description: description)
        }
    }
}
