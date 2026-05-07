import Foundation

public enum WireRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

/// What an attachment represents on the wire. `.image` is the legacy
/// kind: the daemon spools the bytes and forwards the path to Codex as
/// a `localImage` user input item. `.audio` means the attachment is a
/// voice clip belonging to the user message; the daemon transcribes it
/// with Whisper, uses the transcript as the prompt text Codex sees, and
/// stores the audio for later replay so the chat history shows a
/// playable bubble. Old peers without `kind` decode as `.image` so
/// existing image-only flows keep working unchanged.
public enum WireAttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case audio
}

/// One attachment piggy-backing on a `sendPrompt` / `newChat` frame. The
/// payload rides inline as base64 because the bridge speaks JSON over
/// WebSocket (no multipart). The daemon's behaviour depends on `kind`:
/// images are forwarded to Codex as `localImage`; audio is transcribed
/// (the transcript becomes the prompt text) and stored for replay.
///
/// `filename` is advisory: the daemon uses its extension when picking
/// the on-disk suffix, defaulting to `.jpg` for images and `.m4a` for
/// audio if none is supplied. Old peers that don't carry attachments
/// simply omit the field entirely; new peers receiving a frame without
/// it default to an empty array.
public struct WireAttachment: Codable, Equatable, Sendable {
    public let id: String
    public let kind: WireAttachmentKind
    public let mimeType: String
    public let filename: String?
    public let dataBase64: String

    public init(
        id: String,
        kind: WireAttachmentKind = .image,
        mimeType: String,
        filename: String?,
        dataBase64: String
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.filename = filename
        self.dataBase64 = dataBase64
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, mimeType, filename, dataBase64
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decodeIfPresent(WireAttachmentKind.self, forKey: .kind) ?? .image
        self.mimeType = try c.decode(String.self, forKey: .mimeType)
        self.filename = try c.decodeIfPresent(String.self, forKey: .filename)
        self.dataBase64 = try c.decode(String.self, forKey: .dataBase64)
    }
}

/// Project descriptor exposed to the desktop client when it asks the
/// daemon for `listProjects`. Mirrors the macOS `DerivedProject` shape
/// the GUI consumes today, minus the cached chat list (clients pull
/// chats independently via `chatsSnapshot`).
public struct WireProject: Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    /// Working directory the chats in this project were started in. The
    /// daemon uses this when the client opens a "new chat in this
    /// project" so it knows which `cwd` to pass to `clawix.startThread`.
    public var cwd: String
    public var hasGitRepo: Bool
    public var branch: String?
    public var lastUsedAt: Date?

    public init(
        id: String,
        title: String,
        cwd: String,
        hasGitRepo: Bool = false,
        branch: String? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.hasGitRepo = hasGitRepo
        self.branch = branch
        self.lastUsedAt = lastUsedAt
    }
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
    /// True when the rollout shows the last assistant turn ended
    /// without `final_answer` / `turn_completed` and the rollout has
    /// been quiet for more than `RolloutReader.interruptedThreshold`.
    /// Surfaced so the iPhone (or any client) can render an
    /// "Interrupted, retry?" affordance on the chat row.
    public var lastTurnInterrupted: Bool

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
        cwd: String? = nil,
        lastTurnInterrupted: Bool = false
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
        self.lastTurnInterrupted = lastTurnInterrupted
    }

    /// Decode tolerant of legacy payloads (without `lastTurnInterrupted`).
    /// Old Macs talking to a new iPhone (or vice versa during a phased
    /// rollout) still parse cleanly — the field defaults to false.
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, isPinned, isArchived, hasActiveTurn
        case lastMessageAt, lastMessagePreview, branch, cwd, lastTurnInterrupted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.hasActiveTurn = try c.decodeIfPresent(Bool.self, forKey: .hasActiveTurn) ?? false
        self.lastMessageAt = try c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        self.lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview)
        self.branch = try c.decodeIfPresent(String.self, forKey: .branch)
        self.cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        self.lastTurnInterrupted = try c.decodeIfPresent(Bool.self, forKey: .lastTurnInterrupted) ?? false
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
    /// Filled when `kind == "imageGeneration"`. Absolute filesystem path
    /// where the daemon's host wrote the generated PNG (today Codex
    /// stores them under `~/.codex/generated_images/<session>/<id>.png`).
    /// Clients pass this path back to `requestGeneratedImage` to fetch
    /// the bytes; the daemon validates the path stays inside its
    /// generated_images sandbox before reading. Optional so old peers
    /// without the field decode cleanly and so streaming-only items
    /// (where the rollout hasn't been parsed yet) can still flow.
    public var generatedImagePath: String?

    public init(
        id: String,
        kind: String,
        status: WireWorkItemStatus,
        commandText: String? = nil,
        commandActions: [String]? = nil,
        paths: [String]? = nil,
        mcpServer: String? = nil,
        mcpTool: String? = nil,
        dynamicToolName: String? = nil,
        generatedImagePath: String? = nil
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
        self.generatedImagePath = generatedImagePath
    }
}

/// One block in an assistant message's chronological timeline. Mirrors
/// macOS `AssistantTimelineEntry`. Encoded with a `type` discriminator
/// so decoders can keyed-decode without `Any`.
public enum WireTimelineEntry: Codable, Equatable, Sendable {
    case reasoning(id: String, text: String)
    case message(id: String, text: String)
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
        case "message":
            let text = try c.decode(String.self, forKey: .text)
            self = .message(id: id, text: text)
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
        case .message(let id, let text):
            try c.encode("message", forKey: .type)
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
    /// When this user message was originally captured as a voice clip,
    /// `audioRef` carries the lookup id the daemon stores it under in
    /// its audio sidecar. Clients render a playable audio bubble next
    /// to (or in place of) the transcript and fetch the bytes on first
    /// tap via the `requestAudio` frame. nil for typed prompts and for
    /// every assistant message.
    public var audioRef: WireAudioRef?
    /// Inline image (or audio) attachments belonging to this message.
    /// Empty for live-streamed assistant messages and for typed user
    /// messages without media. Populated when hydrating history from
    /// a rollout that referenced images on disk: the daemon reads the
    /// bytes, base64-encodes them, and ships them so the client can
    /// render the same `[image]` thumbnails the user originally saw.
    /// Old peers that don't know about this field decode an empty array.
    public var attachments: [WireAttachment]

    public init(
        id: String,
        role: WireRole,
        content: String,
        reasoningText: String = "",
        streamingFinished: Bool = true,
        isError: Bool = false,
        timestamp: Date,
        timeline: [WireTimelineEntry] = [],
        workSummary: WireWorkSummary? = nil,
        audioRef: WireAudioRef? = nil,
        attachments: [WireAttachment] = []
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
        self.audioRef = audioRef
        self.attachments = attachments
    }

    // Decodes legacy payloads (without `timeline` / `workSummary` /
    // `audioRef` / `attachments`) gracefully. Each new field defaults
    // so an old Mac talking to a new iPhone (or vice versa during a
    // phased rollout) still works.
    private enum CodingKeys: String, CodingKey {
        case id, role, content, reasoningText, streamingFinished, isError, timestamp, timeline, workSummary, audioRef, attachments
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
        self.audioRef = try c.decodeIfPresent(WireAudioRef.self, forKey: .audioRef)
        self.attachments = try c.decodeIfPresent([WireAttachment].self, forKey: .attachments) ?? []
    }
}

/// Lightweight pointer the daemon attaches to user messages that came
/// in as a voice clip. `id` is the lookup key for `requestAudio`;
/// `mimeType` and `durationMs` let clients render the bubble (duration
/// label, codec hint) without having to download the bytes first. The
/// transcript itself stays in `WireMessage.content` so search and the
/// rollout history keep working without any audio-aware extra plumbing.
public struct WireAudioRef: Codable, Equatable, Sendable {
    public let id: String
    public let mimeType: String
    public let durationMs: Int

    public init(id: String, mimeType: String, durationMs: Int) {
        self.id = id
        self.mimeType = mimeType
        self.durationMs = durationMs
    }
}
