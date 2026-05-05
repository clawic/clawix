import Foundation

public enum WireRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

public struct WireChat: Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var createdAt: Date
    public var isPinned: Bool
    public var isArchived: Bool
    public var hasActiveTurn: Bool
    public var lastMessageAt: Date?
    public var lastMessagePreview: String?
    public var branch: String?
    public var cwd: String?

    public init(
        id: String,
        title: String,
        createdAt: Date,
        isPinned: Bool = false,
        isArchived: Bool = false,
        hasActiveTurn: Bool = false,
        lastMessageAt: Date? = nil,
        lastMessagePreview: String? = nil,
        branch: String? = nil,
        cwd: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.hasActiveTurn = hasActiveTurn
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.branch = branch
        self.cwd = cwd
    }
}

// MARK: - Work items

/// Status of a tool item the assistant ran during a turn.
public enum WireWorkItemStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case failed
}

/// Flat, wire-friendly version of the macOS `WorkItem`. Instead of an
/// enum-with-associated-values (a pain to encode/decode round-trip), we
/// carry a `kind` discriminator string and the optional fields that
/// each kind needs. Unused fields stay nil and Codable drops them.
public struct WireWorkItem: Codable, Equatable, Sendable {
    /// Stable id for this item across `inProgress` → `completed`.
    public let id: String
    /// Discriminator. Mirrors `WorkItemKind`:
    /// "command" | "fileChange" | "webSearch" | "mcpTool" |
    /// "dynamicTool" | "imageGeneration" | "imageView".
    public let kind: String
    public let status: WireWorkItemStatus
    /// Filled when `kind == "command"`. The shell text the agent ran.
    public var commandText: String?
    /// Parsed action labels for the command — "read", "listFiles",
    /// "search", or "unknown". Mirrors `CommandActionKind` raw values.
    public var commandActions: [String]?
    /// Filled when `kind == "fileChange"`. Repo-relative or absolute
    /// paths the patch touched.
    public var paths: [String]?
    /// MCP server name (when kind == "mcpTool").
    public var mcpServer: String?
    /// MCP tool name (when kind == "mcpTool").
    public var mcpTool: String?
    /// Dynamic tool name (when kind == "dynamicTool").
    public var dynamicToolName: String?

    public init(
        id: String,
        kind: String,
        status: WireWorkItemStatus,
        commandText: String? = nil,
        commandActions: [String]? = nil,
        paths: [String]? = nil,
        mcpServer: String? = nil,
        mcpTool: String? = nil,
        dynamicToolName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.commandText = commandText
        self.commandActions = commandActions
        self.paths = paths
        self.mcpServer = mcpServer
        self.mcpTool = mcpTool
        self.dynamicToolName = dynamicToolName
    }
}

/// One block in an assistant message's chronological timeline. Mirrors
/// macOS `AssistantTimelineEntry`. Encoded with a `type` discriminator
/// so decoders can keyed-decode without `Any`.
public enum WireTimelineEntry: Codable, Equatable, Sendable {
    case reasoning(id: String, text: String)
    case tools(id: String, items: [WireWorkItem])

    private enum CodingKeys: String, CodingKey {
        case type, id, text, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let id = try c.decode(String.self, forKey: .id)
        switch type {
        case "reasoning":
            let text = try c.decode(String.self, forKey: .text)
            self = .reasoning(id: id, text: text)
        case "tools":
            let items = try c.decode([WireWorkItem].self, forKey: .items)
            self = .tools(id: id, items: items)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "unknown timeline type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reasoning(let id, let text):
            try c.encode("reasoning", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .tools(let id, let items):
            try c.encode("tools", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(items, forKey: .items)
        }
    }
}

/// Aggregated work for a single assistant turn. Renders the elapsed-time
/// disclosure ("Worked for 12s. Ran 4 commands · Edited 2 files") above
/// the assistant body. Mirrors macOS `WorkSummary`.
public struct WireWorkSummary: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var items: [WireWorkItem]

    public init(startedAt: Date, endedAt: Date? = nil, items: [WireWorkItem]) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.items = items
    }
}

public struct WireMessage: Codable, Equatable, Sendable {
    public let id: String
    public let role: WireRole
    public var content: String
    public var reasoningText: String
    public var streamingFinished: Bool
    public var isError: Bool
    public let timestamp: Date
    /// Chronological timeline interleaving reasoning chunks and tool
    /// groups. Empty for user messages and for assistant messages whose
    /// text body is enough on its own.
    public var timeline: [WireTimelineEntry]
    /// Aggregated tool-call summary for the turn (the elapsed-time
    /// disclosure header). nil when the assistant did no tool work.
    public var workSummary: WireWorkSummary?

    public init(
        id: String,
        role: WireRole,
        content: String,
        reasoningText: String = "",
        streamingFinished: Bool = true,
        isError: Bool = false,
        timestamp: Date,
        timeline: [WireTimelineEntry] = [],
        workSummary: WireWorkSummary? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningText = reasoningText
        self.streamingFinished = streamingFinished
        self.isError = isError
        self.timestamp = timestamp
        self.timeline = timeline
        self.workSummary = workSummary
    }

    // Decodes legacy payloads (without `timeline` / `workSummary`)
    // gracefully. Both fields default to empty so an old Mac talking to
    // a new iPhone (or vice versa during a phased rollout) still works.
    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoningText, streamingFinished, isError, timestamp, timeline, workSummary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.role = try c.decode(WireRole.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.reasoningText = try c.decodeIfPresent(String.self, forKey: .reasoningText) ?? ""
        self.streamingFinished = try c.decodeIfPresent(Bool.self, forKey: .streamingFinished) ?? true
        self.isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.timeline = try c.decodeIfPresent([WireTimelineEntry].self, forKey: .timeline) ?? []
        self.workSummary = try c.decodeIfPresent(WireWorkSummary.self, forKey: .workSummary)
    }
}
