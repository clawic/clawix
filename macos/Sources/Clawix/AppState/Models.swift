import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    var reasoningText: String
    var streamingFinished: Bool
    var isError: Bool
    let timestamp: Date
    var workSummary: WorkSummary?
    /// Chronological interleave of reasoning chunks and tool groups, so
    /// the chat row can render the Clawix-style timeline (text → "Ran N
    /// commands" → text → …) instead of a collapsed reasoning block.
    var timeline: [AssistantTimelineEntry]
    /// One entry per scheduled WORD on `content`. Each records the
    /// running total character count after that word was scheduled +
    /// when its fade should start. The renderer ramps each word from
    /// opacity 0→1 over a short window so the trailing edge of a
    /// streamed answer reads as a soft gradient.
    var streamCheckpoints: [StreamCheckpoint]
    /// Trailing partial word that hasn't seen its closing whitespace
    /// yet. Carried across deltas so the scheduler can run on
    /// `pendingTail + delta` instead of rescanning the full body on
    /// every token. Emptied by the scheduler whenever the tail closes.
    var streamPendingTail: String
    /// Same idea but per reasoning timeline entry (keyed by entry id).
    /// Reasoning resets on every tool group, so checkpoints have to be
    /// scoped to the entry rather than to the message as a whole.
    var reasoningCheckpoints: [UUID: [StreamCheckpoint]]
    /// Per-reasoning-entry pending partial-word tails.
    var reasoningPendingTails: [UUID: String]
    /// Pointer to the persisted voice clip the user dictated this
    /// message with. nil for typed prompts and for assistant replies.
    var audioRef: WireAudioRef?
    /// Inline image attachments hydrated from a rollout that referenced
    /// images on disk (dummy fixtures use `dummy/images/<filename>`;
    /// real Codex sessions can carry image inputs via `localImage`).
    /// Empty for live-streamed assistants and typed user messages
    /// without media. Daemon ships these on the wire so iOS can render
    /// `[image]` thumbnails on the same bubble.
    var attachments: [WireAttachment]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        reasoningText: String = "",
        streamingFinished: Bool = true,
        isError: Bool = false,
        timestamp: Date = Date(),
        workSummary: WorkSummary? = nil,
        timeline: [AssistantTimelineEntry] = [],
        streamCheckpoints: [StreamCheckpoint] = [],
        streamPendingTail: String = "",
        reasoningCheckpoints: [UUID: [StreamCheckpoint]] = [:],
        reasoningPendingTails: [UUID: String] = [:],
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
        self.workSummary = workSummary
        self.timeline = timeline
        self.streamCheckpoints = streamCheckpoints
        self.streamPendingTail = streamPendingTail
        self.reasoningCheckpoints = reasoningCheckpoints
        self.reasoningPendingTails = reasoningPendingTails
        self.audioRef = audioRef
        self.attachments = attachments
    }

    enum MessageRole { case user, assistant }
}

struct StreamCheckpoint: Equatable {
    let prefixCount: Int
    let addedAt: Date
}

enum AssistantTimelineEntry: Identifiable, Equatable {
    case reasoning(id: UUID, text: String)
    case message(id: UUID, text: String)
    case tools(id: UUID, items: [WorkItem])

    var id: UUID {
        switch self {
        case .reasoning(let id, _): return id
        case .message(let id, _):   return id
        case .tools(let id, _):     return id
        }
    }
}

struct WorkSummary: Equatable {
    var startedAt: Date
    var endedAt: Date?
    /// Indexed by the clawix item id so a single item being marked
    /// in-progress and then completed updates one entry rather than
    /// duplicating it. Order is insertion order for stable rendering.
    var items: [WorkItem]

    var isActive: Bool { endedAt == nil }

    func elapsedSeconds(asOf now: Date) -> Int {
        let end = endedAt ?? now
        return max(0, Int(end.timeIntervalSince(startedAt)))
    }
}

struct WorkItem: Equatable, Identifiable {
    /// Clawix item id (e.g. "item_…"). Stable across started/completed.
    let id: String
    var kind: WorkItemKind
    var status: WorkItemStatus
    /// Absolute path on this Mac of the PNG Codex's `imagegen` tool wrote
    /// for this call. Filled in by `RolloutReader` when it sees an
    /// `image_generation_end` event paired with the rollout's session
    /// id; clients fetch the bytes via `requestGeneratedImage`. Nil
    /// for non-image kinds and for live-streamed items (the JSON-RPC
    /// `item` payload doesn't carry the path; rehydration from the
    /// rollout fills it in on the next chat open).
    var generatedImagePath: String? = nil
}

enum WorkItemStatus: Equatable { case inProgress, completed, failed }

enum WorkItemKind: Equatable {
    case command(text: String?, actions: [CommandActionKind])
    case fileChange(paths: [String])
    case webSearch
    case mcpTool(server: String, tool: String)
    case dynamicTool(name: String)
    case imageGeneration
    case imageView
    /// One `js` invocation against the Codex Node REPL plugin
    /// (`browser-use@openai-bundled`). `flavor` records whether the JS
    /// drove the in-app browser (`tab.*`, `agent.browser.*`, …) or was a
    /// plain REPL block / errored before reaching the browser API.
    case jsCall(title: String?, flavor: JSCallFlavor)
    /// Standalone `js_reset` invocation that re-initialises the Node REPL
    /// runtime. Always grouped with REPL flavour calls in the timeline.
    case jsReset
}

enum JSCallFlavor: Equatable {
    case browser
    case repl
}

enum CommandActionKind: String, Equatable {
    case read, listFiles, search, unknown
}

enum TimelineFamily: Equatable {
    case command
    case fileChange
    case webSearch
    /// MCP tools merge only when targeting the SAME server: two adjacent
    /// `Used Revenuecat` calls collapse, but `Used Revenuecat` followed
    /// by `Used Linear` does not.
    case mcpTool(server: String)
    /// Node REPL calls that DROVE the in-app browser. Kept separate from
    /// `.jsRepl` so a run of `Used the browser` pills doesn't get glued
    /// to a trailing setup/error call rendered as `Used Node Repl`.
    case jsBrowser
    /// Plain Node REPL calls (setup, recovery, REPL-only JS) AND
    /// `js_reset` events. The reset is always REPL-flavour by definition.
    case jsRepl
    case other

    static func from(_ kind: WorkItemKind) -> TimelineFamily {
        switch kind {
        case .command:                return .command
        case .fileChange:             return .fileChange
        case .webSearch:              return .webSearch
        case .mcpTool(let server, _): return .mcpTool(server: server)
        case .jsCall(_, .browser):    return .jsBrowser
        case .jsCall(_, .repl):       return .jsRepl
        case .jsReset:                return .jsRepl
        default:                      return .other
        }
    }

    func matches(_ kind: WorkItemKind) -> Bool {
        switch (self, kind) {
        case (.command, .command):       return true
        case (.fileChange, .fileChange): return true
        case (.webSearch, .webSearch):   return true
        case (.mcpTool(let s), .mcpTool(let server, _)):
            return s == server
        case (.jsBrowser, .jsCall(_, .browser)): return true
        case (.jsRepl, .jsCall(_, .repl)):       return true
        case (.jsRepl, .jsReset):                return true
        default:                         return false
        }
    }
}

struct ContextUsage: Equatable {
    /// Tokens currently filling the context window after the latest turn.
    /// Sourced from `last.totalTokens` (sum of input + cached + output +
    /// reasoning tokens for the most recent request/response).
    var usedTokens: Int64
    /// Maximum tokens the active model can hold. nil when clawix did not
    /// report it (older CLIs / unsupported models).
    var contextWindow: Int64?

    var usedFraction: Double {
        guard let window = contextWindow, window > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedTokens) / Double(window)))
    }
}

struct Chat: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var clawixThreadId: String?
    /// Path to a rollout JSONL when the daemon explicitly exposes one;
    /// nil for ClawJS-indexed sessions that hydrate through the sessions API.
    var rolloutPath: URL?
    var historyHydrated: Bool
    var hasActiveTurn: Bool
    /// Most recent context-window usage reported by the clawix backend.
    /// Drives the context indicator in the composer toolbar.
    var contextUsage: ContextUsage? = nil
    /// Project this chat belongs to (nil means projectless).
    var projectId: UUID?
    /// Runtime archive state. Archived chats are hidden from
    /// the normal sidebar list but can still be surfaced by archived views.
    var isArchived: Bool
    var isPinned: Bool
    /// True when the assistant finished its last turn while the user was
    /// looking at a different route. Drives the soft-blue unread dot in
    /// the sidebar row. Cleared the moment the user navigates back into
    /// this chat.
    var hasUnreadCompletion: Bool
    /// Working directory of this chat (cwd from the rollout `session_meta`).
    /// Used to infer git-repo presence for the footer branch pill.
    var cwd: String?
    /// True when `cwd` is a git working tree. Drives whether the branch
    /// pill is rendered in the chat footer.
    var hasGitRepo: Bool
    /// Currently checked-out branch in `cwd`, when `hasGitRepo`.
    var branch: String?
    /// Local branches available in `cwd`. Populated when `hasGitRepo`.
    var availableBranches: [String]
    /// Number of files with uncommitted changes on `branch`. nil when unknown.
    var uncommittedFiles: Int?
    /// When this chat was created by forking another conversation, the
    /// parent chat's id. Drives the trailing "Forked from conversation"
    /// banner the renderer drops in after `forkBannerAfterMessageId`.
    var forkedFromChatId: UUID?
    /// Snapshot of the parent chat's title at fork time. Used as the
    /// new chat's initial title (matches the screenshot — the fork keeps
    /// the original title) and as the banner's tooltip / a11y label.
    var forkedFromTitle: String?
    /// The id of the last message included in the fork. The banner is
    /// rendered immediately after this message in the chat transcript so
    /// it sits between the copied parent history and any new turns the
    /// user adds in the forked chat.
    var forkBannerAfterMessageId: UUID?
    /// True when the rollout shows the last assistant turn ended
    /// without `final_answer` / `turn_completed` and has been quiet
    /// past `RolloutReader.interruptedThreshold`. Drives the
    /// "Interrupted, retry?" pill. Cleared when the user fires a new
    /// prompt or the engine produces a fresh turn.
    var lastTurnInterrupted: Bool = false
    /// Conversation lives only inside a QuickAsk session; sidebar
    /// filters these out and `QuickAskController.hide()` deletes them
    /// from `appState.chats` once the panel closes. Lets the user run
    /// throwaway prompts ("incognito") without polluting their history.
    var isQuickAskTemporary: Bool = false
    /// Conversation lives only inside the parent chat's right sidebar
    /// as a "side chat" tab (silent fork with inherited context). The
    /// main sidebar list filters these out so they don't pollute the
    /// chronological view; the parent's `ChatSidebarState` keeps the
    /// reference via a `SidebarItem.chat` entry.
    var isSideChat: Bool = false
    /// Owning `Agent.id`. Default = built-in Codex agent
    /// (`Agent.defaultCodexId`), which preserves the legacy "every chat
    /// is a Codex chat" semantics. Surfaced on the new Agents tabs and
    /// in the composer dropdown so the user knows which agent will pick
    /// up the next turn.
    var agentId: String = Agent.defaultCodexId
    /// Last activity timestamp; used by `AgentDetailView.chatsTab` to
    /// sort chats and by the surfaces that show the agent roster.
    var lastMessageAt: Date? = nil

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        clawixThreadId: String? = nil,
        rolloutPath: URL? = nil,
        historyHydrated: Bool = false,
        hasActiveTurn: Bool = false,
        projectId: UUID? = nil,
        isArchived: Bool = false,
        isPinned: Bool = false,
        hasUnreadCompletion: Bool = false,
        cwd: String? = nil,
        hasGitRepo: Bool = false,
        branch: String? = nil,
        availableBranches: [String] = [],
        uncommittedFiles: Int? = nil,
        forkedFromChatId: UUID? = nil,
        forkedFromTitle: String? = nil,
        forkBannerAfterMessageId: UUID? = nil,
        lastTurnInterrupted: Bool = false,
        isQuickAskTemporary: Bool = false,
        isSideChat: Bool = false,
        agentId: String = Agent.defaultCodexId,
        lastMessageAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.clawixThreadId = clawixThreadId
        self.rolloutPath = rolloutPath
        self.historyHydrated = historyHydrated
        self.hasActiveTurn = hasActiveTurn
        self.projectId = projectId
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.hasUnreadCompletion = hasUnreadCompletion
        self.cwd = cwd
        self.hasGitRepo = hasGitRepo
        self.branch = branch
        self.availableBranches = availableBranches
        self.uncommittedFiles = uncommittedFiles
        self.forkedFromChatId = forkedFromChatId
        self.forkedFromTitle = forkedFromTitle
        self.forkBannerAfterMessageId = forkBannerAfterMessageId
        self.lastTurnInterrupted = lastTurnInterrupted
        self.isQuickAskTemporary = isQuickAskTemporary
        self.isSideChat = isSideChat
        self.agentId = agentId
        self.lastMessageAt = lastMessageAt
    }
}

struct PendingPlanQuestion: Equatable {
    /// JSON-RPC id from the inbound request. Must round-trip exactly when
    /// answering — the daemon correlates the response by this id.
    let rpcId: ClawixRPCID
    let chatId: UUID
    let threadId: String
    let turnId: String
    let itemId: String
    /// Runtime requests can carry several questions in one shot. We render
    /// one card and step through them in order.
    let questions: [ToolRequestUserInputQuestion]

    static func == (lhs: PendingPlanQuestion, rhs: PendingPlanQuestion) -> Bool {
        lhs.rpcId == rhs.rpcId
            && lhs.chatId == rhs.chatId
            && lhs.threadId == rhs.threadId
            && lhs.turnId == rhs.turnId
            && lhs.itemId == rhs.itemId
            && lhs.questions.map(\.id) == rhs.questions.map(\.id)
    }
}

struct Plugin: Identifiable {
    let id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var iconName: String
}

struct Automation: Identifiable {
    let id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var trigger: String
}

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var resourceId: String?
    var name: String
    var path: String

    init(id: UUID = UUID(), resourceId: String? = nil, name: String, path: String) {
        self.id = id
        self.resourceId = resourceId
        self.name = name
        self.path = path
    }
}

struct PinnedItem: Identifiable {
    let id = UUID()
    let title: String
    let age: String
}
