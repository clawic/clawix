import SwiftUI
import Combine
import AppKit

// MARK: - Route

enum SidebarRoute: Equatable {
    case home
    case search
    case plugins
    case automations
    case project
    case chat(UUID)
    case settings
}

// MARK: - Models

struct ChatMessage: Identifiable {
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
        reasoningPendingTails: [UUID: String] = [:]
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
    }

    enum MessageRole { case user, assistant }
}

/// Marker recorded each time a streaming delta lands on a piece of text.
/// `prefixCount` is the total UTF-16 character count of the receiving
/// string AFTER the delta was applied, so the renderer can find which
/// checkpoint covers any given character index without re-scanning the
/// delta history.
struct StreamCheckpoint: Equatable {
    let prefixCount: Int
    let addedAt: Date
}

/// One block in an assistant message's chronological timeline.
/// Reasoning summary deltas land in `.reasoning`; tool items
/// (`commandExecution`, `fileChange`, …) land in the trailing `.tools`
/// group until the next reasoning delta opens a fresh chunk.
enum AssistantTimelineEntry: Identifiable, Equatable {
    case reasoning(id: UUID, text: String)
    case tools(id: UUID, items: [WorkItem])

    var id: UUID {
        switch self {
        case .reasoning(let id, _): return id
        case .tools(let id, _):     return id
        }
    }
}

// MARK: - Work summary (the elapsed-time disclosure header)

/// Aggregates everything the assistant did during a single turn, so the
/// chat row can render the elapsed-time disclosure with a short list of
/// tool activity (commands, file reads, browser, …).
///
/// Built incrementally from `item/started` / `item/completed` notifications
/// and frozen on `turn/completed`.
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
        return max(0, Int((end.timeIntervalSince(startedAt)).rounded()))
    }
}

struct WorkItem: Equatable, Identifiable {
    /// Clawix item id (e.g. "item_…"). Stable across started/completed.
    let id: String
    var kind: WorkItemKind
    var status: WorkItemStatus
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
}

enum CommandActionKind: String, Equatable {
    case read, listFiles, search, unknown
}

/// Coarse grouping used when assembling the timeline so the renderer can
/// decide whether two consecutive tool items belong in the same `.tools`
/// entry or should each get their own row. Same-family items merge so the
/// inline transcript collapses runs like "Searched the web · Searched the
/// web · Searched the web" into a single counted row, while different
/// families ("Used Revenuecat" then "Searched the web") stay split.
enum TimelineFamily: Equatable {
    case command
    case fileChange
    case webSearch
    /// MCP tools merge only when targeting the SAME server: two adjacent
    /// `Used Revenuecat` calls collapse, but `Used Revenuecat` followed
    /// by `Used Linear` does not.
    case mcpTool(server: String)
    case other

    static func from(_ kind: WorkItemKind) -> TimelineFamily {
        switch kind {
        case .command:                return .command
        case .fileChange:             return .fileChange
        case .webSearch:              return .webSearch
        case .mcpTool(let server, _): return .mcpTool(server: server)
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
        default:                         return false
        }
    }
}

/// Snapshot of how much of the model context window the live thread is
/// using right now. Updated from `thread/tokenUsage/updated` notifications.
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

struct Chat: Identifiable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var clawixThreadId: String?
    /// Path to the rollout JSONL on disk (for sessions discovered via
    /// SessionsIndex; nil for chats started inside the app).
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
        uncommittedFiles: Int? = nil
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
    }
}

/// One outstanding `item/tool/requestUserInput` request waiting for the
/// user to answer or dismiss. Carries the JSON-RPC id used to resolve
/// the request when the user picks an option, plus a snapshot of the
/// payload so the chat view can render the question card with the same
/// data the backend sent.
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
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

struct PinnedItem: Identifiable {
    let id = UUID()
    let title: String
    let age: String
}

enum IntelligenceLevel: String, CaseIterable, Identifiable {
    case low, medium, high, extra
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low:    return String(localized: "Low", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .medium: return String(localized: "Medium", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .high:   return String(localized: "High", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .extra:  return String(localized: "Extra high", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var clawixEffort: String {
        switch self {
        case .low:    return "low"
        case .medium: return "medium"
        case .high:   return "high"
        case .extra:  return "xhigh"
        }
    }
}

enum SpeedLevel: String, CaseIterable, Identifiable {
    case standard, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return String(localized: "Standard", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "Fast", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
    var description: String {
        switch self {
        case .standard: return String(localized: "Default speed, normal usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "1.5x faster speed, higher usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
}

enum PermissionMode: String, CaseIterable, Identifiable {
    case defaultPermissions, autoReview, fullAccess
    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultPermissions: return String(localized: "Default permissions", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .autoReview:         return String(localized: "Automatic review", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fullAccess:         return String(localized: "Full access", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var iconName: String {
        switch self {
        case .defaultPermissions: return "hand.raised"
        case .autoReview:         return "checkmark.shield"
        case .fullAccess:         return "exclamationmark.octagon"
        }
    }

    var accent: Color {
        switch self {
        case .defaultPermissions: return Color(white: 0.78)
        case .autoReview:         return Color(red: 0.34, green: 0.62, blue: 1.0)
        case .fullAccess:         return Color(red: 0.95, green: 0.50, blue: 0.20)
        }
    }
}

// MARK: - Composer attachments

/// File the user has staged in the composer via the attach menu or
/// drag-and-drop. On send, each attachment is converted to a
/// `@<absolute-path>` mention prepended to the text (the runtime
/// file-mention syntax) so the agent can read it. The chip row above
/// the text editor lists them with a remove button.
struct ComposerAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    var filename: String { url.lastPathComponent }

    var isImage: Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"]
        return imageExts.contains(url.pathExtension.lowercased())
    }
}

// MARK: - ComposerState
//
// Lives separately from AppState so that typing into the composer only
// invalidates ComposerView, not every view that observes AppState (sidebar,
// content shell, chat view, etc.). `@EnvironmentObject` does not track
// individual `@Published` properties — any change to AppState would
// re-render ~40 views in the tree, which dropped frames while typing fast.
@MainActor
final class ComposerState: ObservableObject {
    @Published var text: String = ""
    /// Files staged in the composer (paperclip menu / drag-and-drop /
    /// future paste). On `sendMessage` each url is prepended to the
    /// outgoing text as `@<path>` and the array is cleared.
    @Published var attachments: [ComposerAttachment] = []
    /// Bumped whenever something wants to pull keyboard focus back into
    /// the composer (e.g. ⌘N from home, switching chats from the
    /// sidebar). The composer text editor watches this token and calls
    /// `makeFirstResponder` on change.
    @Published var focusToken: Int = 0
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var currentRoute: SidebarRoute = .home {
        didSet { clearUnreadIfChatRoute() }
    }
    @Published var searchQuery: String = ""
    @Published var searchResults: [String] = []
    @Published var chats: [Chat] = []
    /// Manual ordering for pinned chats. Persisted via metadata as the
    /// order of `pinnedThreadIds`. The sidebar sorts pinned rows by the
    /// index a chat appears at here; chats not in this array fall to the
    /// bottom of the pinned section.
    @Published var pinnedOrder: [UUID] = []
    /// Chats the runtime has marked as archived. Kept separate from
    /// `chats` so the regular sidebar lists never need to filter on
    /// `isArchived`. Populated lazily the first time the sidebar's
    /// archived section is expanded, plus optimistically appended when
    /// the user archives a chat from inside the app.
    @Published var archivedChats: [Chat] = []
    /// True while a `listThreads(archived: true)` request is in flight.
    /// The sidebar shows a spinner inside the section while this is set.
    @Published var archivedLoading: Bool = false
    /// Tracks whether the lazy fetch has succeeded at least once during
    /// this session, so re-expanding the section doesn't re-hit the
    /// runtime. `unarchiveChat` triggers a refetch when the active list
    /// reload completes.
    private var archivedLoaded: Bool = false
    /// Cap applied to the sidebar's archived section. The settings page
    /// can surface a larger list if we ever wire it up; the sidebar is
    /// for browsing recent archives, not exhaustive history.
    static let archivedSidebarLimit: Int = 30
    let sampleChat: Chat
    let browserSampleChat: Chat
    @Published var plugins: [Plugin] = []
    @Published var automations: [Automation] = []
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var selectedModel: String = "5.5"
    @Published var selectedIntelligence: IntelligenceLevel = .high
    @Published var selectedSpeed: SpeedLevel = .standard
    @Published var permissionMode: PermissionMode = .fullAccess
    /// Global plan-mode toggle. When on, subsequent turns are sent with
    /// `collaborationMode = "plan"` so the agent surfaces
    /// `item/tool/requestUserInput` instead of acting directly. Toggled by
    /// `/plan`, the composer pill, or the "+" menu row.
    @Published var planMode: Bool = false
    /// Per-chat plan-mode questions awaiting an answer. Set when the
    /// backend sends `item/tool/requestUserInput`; cleared on submit /
    /// dismiss / turn completion. The sidebar surfaces an awaiting-answer
    /// hint while this is non-nil for a chat.
    @Published var pendingPlanQuestions: [UUID: PendingPlanQuestion] = [:]
    /// URL of an image currently being previewed in the fullscreen
    /// viewer. Same overlay used by composer chips and chat bubbles.
    @Published var imagePreviewURL: URL?
    /// Drives the rename sheet from anywhere in the UI (chat-title
    /// ellipsis, sidebar right-click). Setting non-nil presents the sheet;
    /// the sheet clears it on dismiss.
    @Published var pendingRenameChat: Chat?
    /// Drives the global confirmation dialog (destructive actions, writes
    /// to Codex state). Set non-nil to present, the sheet clears it on
    /// dismiss or after the user confirms.
    @Published var pendingConfirmation: ConfirmationRequest?
    /// Composer text + staged attachments + focus token live here so
    /// typing only fires `objectWillChange` on this child object,
    /// leaving AppState's other observers untouched.
    let composer = ComposerState()
    @Published var pinnedItems: [PinnedItem] = []
    @Published var isLeftSidebarOpen: Bool = true
    @Published var isCommandPaletteOpen: Bool = false
    /// When `true`, the right sidebar takes over the full width of the
    /// content area (everything to the right of the left sidebar),
    /// completely covering the main view. The persisted column width is
    /// preserved so collapsing brings the panel back to its previous size.
    @Published var isRightSidebarMaximized: Bool = false
    /// One sidebar state per chat (keyed by `Chat.id`). Switching chats
    /// rebinds every consumer of `currentSidebar`/`isRightSidebarOpen` to
    /// the destination chat's entry, so the right column animates to
    /// whatever was open in that chat last (or closes if the chat had no
    /// items).
    @Published var chatSidebars: [UUID: ChatSidebarState] = [:]
    /// Cross-tab favicon memory keyed by the registrable host. A tab freshly
    /// opened to a host visited before therefore renders its real favicon
    /// from the very first frame instead of cycling through the monogram and
    /// the Google s2 fallback while WKWebView re-extracts the page's
    /// `<link rel="icon">`. Persisted to UserDefaults under
    /// `HostFavicons` so it survives relaunches.
    @Published private(set) var hostFavicons: [String: URL] = [:]
    /// One-shot signal consumed by `BrowserView` to reload the active web
    /// view. Set when `openLinkInBrowser` is asked to open a URL already
    /// present in the strip and the user expects the existing tab to refresh
    /// instead of a duplicate opening. The view resets it back to nil after
    /// firing the reload.
    @Published var pendingReloadTabId: UUID?
    /// Per-web-tab live page background colour sampled from the bottom-left
    /// pixel of each browser webview. Keyed by the web item's id so the
    /// bottom-trailing rounded-corner cutout blends with whatever the
    /// active page is currently painting at that edge.
    @Published var browserPageBackgroundColors: [UUID: Color] = [:]
    @Published var recentSessions: [ClawixSessionSummary] = []
    /// Project ids whose chats are currently being lazy-loaded from the
    /// runtime. The sidebar uses this to render a per-project spinner.
    @Published var loadingProjects: Set<UUID> = []
    /// Project ids we've already lazy-loaded at least once during this
    /// session. Prevents re-firing the same query on every accordion
    /// toggle. Cleared if the user explicitly refreshes.
    private var lazyLoadedProjects: Set<UUID> = []
    @Published var clawixBackendStatus: ClawixService.Status = .idle
    /// Snapshot of the user's primary/secondary rate-limit windows as
    /// reported by the backend (`account/rateLimits/read` once at boot,
    /// then refreshed by `account/rateLimits/updated`). nil while the
    /// initial fetch is in flight or when the backend declined to answer.
    @Published var rateLimits: RateLimitSnapshot? = nil
    /// Per-bucket rate-limit snapshots keyed by metered `limit_id`
    /// (e.g. "codex", "codex_<model>"). Empty when the backend doesn't
    /// surface a per-bucket view.
    @Published var rateLimitsByLimitId: [String: RateLimitSnapshot] = [:]
    @Published var settingsCategory: SettingsCategory = .general
    /// User-selected interface language. Persisted via UserDefaults
    /// (suite `appPrefsSuite`, key `PreferredLanguage`). Changing
    /// this immediately re-applies the language process-wide
    /// (`AppleLanguages` + `AppLocale.current`) and SwiftUI re-renders
    /// because the root view binds `\.locale` to it.
    @Published var preferredLanguage: AppLanguage = .spanish {
        didSet {
            guard oldValue != preferredLanguage else { return }
            AppLanguage.apply(preferredLanguage)
        }
    }
    /// Cache of resolved `<title>` for URLs the chat surfaces in the
    /// trailing "Website" card. Populated lazily — the card paints with
    /// the URL host until the fetch lands.
    let linkMetadata = LinkMetadataStore()

    let availableModels = ["5.5", "5.4"]
    let otherModels = ["5.4-Mini", "5.3-Pro", "5.3-Pro-Spark", "5.2"]

    let clawixBinary: ClawixBinaryInfo?
    let clawix: ClawixService?
    let auth = BackendAuthCoordinator()
    private var authObserver: AnyCancellable?

    /// Local-network WS server that exposes this AppState to the iOS
    /// companion. Lazily created so the property doesn't take a
    /// reference to `self` before init finishes.
    private var bridgeServer: BridgeServer?

    private let projectsRepo = ProjectsRepository()
    private let pinsRepo = PinsRepository()
    private let chatProjectsRepo = ChatProjectsRepository()
    private let metaRepo = MetaRepository()
    private let archivesRepo = ArchivesRepository()
    private let hiddenRootsRepo = HiddenRootsRepository()
    /// Persistent cache of the sidebar's last applied state. Used to
    /// paint Pinned + chat list instantly at launch from local SQLite,
    /// before the runtime bootstraps and paginates the real thread list.
    /// Rewritten at the end of every applyThreads / mergeThreads.
    private let snapshotRepo = SnapshotRepository()
    /// True when the snapshot cache is active. Disabled while fixtures
    /// are driving the threads list (CLAWIX_THREAD_FIXTURE) so tests
    /// stay deterministic and the snapshot table never sees fixture
    /// data.
    private let snapshotEnabled: Bool = (AgentThreadStore.fixtureThreads() == nil)
    private var backendState: BackendState = .empty

    /// Resolves session ids to thread names by aggregating the runtime
    /// session index (~/.codex/session_index.jsonl) and the app's own
    /// session_titles table. User renames and generated titles are
    /// persisted through this repository.
    private let titlesRepo = SessionTitlesRepository()
    /// Available only when ClawixBinary.resolve() returned a path. If
    /// nil, automatic title generation is silently disabled and
    /// historic sessions without an entry in titlesRepo keep their
    /// firstMessage fallback.
    private let titleGenerator: TitleGenerator?
    /// Chats already considered for post-turn title generation. Prevents
    /// re-firing on every turn of the same chat.
    private var titledChatIds: Set<UUID> = []

    init() {
        // Initial language: read directly from persisted storage so the
        // didSet observer doesn't fire (and re-apply) during init.
        // ClawixApp.init() has already called AppLanguage.bootstrap()
        // before AppState is constructed, so AppLocale.current and the
        // AppleLanguages override are already in place.
        self.preferredLanguage = AppLanguage.loadPersisted()

        sampleChat = Chat(
            id: UUID(uuidString: "8B46DFE1-B932-48E6-94E7-C86E65F7F18D")!,
            title: "Refactor authentication module",
            messages: [
                ChatMessage(role: .user,
                            content: "Can you help me refactor the authentication module?",
                            timestamp: Date()),
                ChatMessage(role: .assistant,
                            content: "Sure. I'll start by analyzing the module's current structure and suggest improvements to readability and security.",
                            timestamp: Date())
            ],
            createdAt: Date()
        )

        let browserStart = Date().addingTimeInterval(-180)
        let browserEnd = browserStart.addingTimeInterval(150)
        browserSampleChat = Chat(
            id: UUID(uuidString: "C0FFEE11-CAFE-4BAB-9B0E-BAB1E7B0FFEE")!,
            title: "Find round titanium frames on 1688",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "I'm looking for round titanium glasses frames similar to the ones in this photo. Can you browse 1688 and pull a few options?",
                    timestamp: browserStart
                ),
                ChatMessage(
                    role: .assistant,
                    content: "Found a handful of close matches: aviator-style with metal bridge, full titanium frame and prescription-ready. Listings open in the integrated browser if you want to compare them side by side.",
                    timestamp: browserEnd,
                    workSummary: WorkSummary(
                        startedAt: browserStart,
                        endedAt: browserEnd,
                        items: [
                            WorkItem(id: "tool-browser-1",
                                     kind: .dynamicTool(name: "the browser"),
                                     status: .completed),
                            WorkItem(id: "tool-search-1", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-2", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-3", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-4", kind: .webSearch, status: .completed)
                        ]
                    )
                )
            ],
            createdAt: browserStart
        )

        let resolvedBinary = ClawixBinary.resolve()
        self.clawixBinary = resolvedBinary
        self.clawix = resolvedBinary.map { ClawixService(binary: $0) }
        self.titleGenerator = nil

        backendState = BackendStateReader.read()
        loadMockData()
        if let fixtureThreads = AgentThreadStore.fixtureThreads() {
            applyThreads(fixtureThreads)
        } else {
            // First paint: build chats[] + pinnedOrder from the SQLite
            // snapshot of the last applied state. Falls back to an empty
            // list (existing behavior) when the snapshot is empty
            // (fresh install / post-resetLocalOverrides). The runtime
            // reconciles via applyThreads once clawix.bootstrap()
            // resolves, preserving Chat.id thanks to oldByThread.
            applySnapshotForFirstPaint()
        }
        loadHostFavicons()
        loadChatSidebars()
        applyLaunchRoute()
        // FaviconCache hits disk; defer it past the first paint so the
        // synchronous init returns as fast as possible and SwiftUI can
        // render the sidebar from the snapshot.
        Task { @MainActor in
            FaviconCache.shared.primeDiskCache()
        }

        // Forward auth coordinator changes so views observing AppState
        // also rebuild when login / logout state flips.
        auth.bootstrap()
        authObserver = auth.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }

        clawix?.appState = self
        if let clawix, ProcessInfo.processInfo.environment["CLAWIX_DISABLE_BACKEND"] != "1" {
            Task { @MainActor in
                await clawix.bootstrap()
                self.clawixBackendStatus = clawix.status
                if let firstThreadId = self.chats.first(where: { $0.clawixThreadId != nil })?.clawixThreadId,
                   case .ready = clawix.status {
                    // No-op: threads are resumed lazily on user click.
                    _ = firstThreadId
                }
                await self.seedArchivesIfNeeded()
            }
        }

        // Bridge to the iOS companion. Always-on so the pairing UI
        // can show a QR the iPhone scans without flipping any env
        // var. Disabled with CLAWIX_BRIDGE_DISABLE=1 for tests or
        // multi-instance debugging.
        if ProcessInfo.processInfo.environment["CLAWIX_BRIDGE_DISABLE"] != "1" {
            let server = BridgeServer(appState: self, port: PairingService.shared.port)
            server.start()
            self.bridgeServer = server
        }

        // Auto-reload threads when the app gains focus, debounced to avoid
        // hammering the runtime when the user alt-tabs rapidly. Gated by
        // SyncSettings.autoReloadOnFocus.
        focusReloadObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppDidBecomeActive() }
        }
    }

    /// Most recent auto-reload time. Used to debounce the focus-driven
    /// reload to at most one trigger per second.
    private var lastAutoReloadAt: Date?
    private var focusReloadObserver: NSObjectProtocol?

    private func handleAppDidBecomeActive() {
        guard SyncSettings.autoReloadOnFocus else { return }
        guard let clawix, case .ready = clawix.status else { return }
        if let last = lastAutoReloadAt, Date().timeIntervalSince(last) < 1.0 { return }
        lastAutoReloadAt = Date()
        Task { @MainActor in
            await self.loadThreadsFromRuntime()
        }
    }

    /// First-launch seed for the local_archives table. Pulls the runtime's
    /// archived list once and reconciles it into our DB so that
    /// `Chat.isArchived` (which now reads from the repo) matches the
    /// runtime's view from the very first sidebar render. Subsequent
    /// launches see the meta flag and skip.
    private func seedArchivesIfNeeded() async {
        guard SyncSettings.syncArchiveWithCodex else { return }
        if metaRepo.boolValue(forKey: "archives_seeded") { return }
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let archived = try await clawix.listThreads(
                archived: true,
                limit: 1000,
                useStateDbOnly: true
            )
            archivesRepo.bulkArchive(archived.map(\.id))
            metaRepo.setBool(true, forKey: "archives_seeded")
        } catch {
            // Non-fatal: next launch retries.
        }
    }

    // MARK: - Auth helpers

    /// Triggers runtime login. No-op if the binary couldn't be resolved.
    func startBackendLogin() {
        guard let binary = clawixBinary else {
            auth.refresh()
            return
        }
        auth.startLogin(binary: binary)
    }

    /// Triggers runtime logout. Optimistic: the auth coordinator clears
    /// its info immediately so the login screen appears without a flash.
    func performBackendLogout() {
        guard let binary = clawixBinary else {
            auth.refresh()
            return
        }
        auth.logout(binary: binary)
    }

    private func loadMockData() {
        chats = []

        let now = Date()
        archivedChats = [
            Chat(title: "Refactor authentication module",
                 createdAt: now.addingTimeInterval(-60 * 60 * 26),
                 isArchived: true),
            Chat(title: "Investigate flaky CI on macOS",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 3),
                 isArchived: true),
            Chat(title: "Spike: streaming JSON parser",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 8),
                 isArchived: true),
            Chat(title: "Cleanup unused fixtures",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 17),
                 isArchived: true)
        ]

        plugins = [
            Plugin(id: UUID(), name: "GitHub",
                   description: "Integration with GitHub repositories",
                   isEnabled: true, iconName: "globe"),
            Plugin(id: UUID(), name: "Terminal",
                   description: "Access to the system terminal",
                   isEnabled: true, iconName: "terminal"),
            Plugin(id: UUID(), name: "Web search",
                   description: "Search the web for information",
                   isEnabled: false, iconName: "magnifyingglass.circle")
        ]

        automations = [
            Automation(id: UUID(), name: "PR review",
                       description: "Review pull requests automatically",
                       isEnabled: true, trigger: "When a PR is opened"),
            Automation(id: UUID(), name: "Auto-run tests",
                       description: "Run tests on every save",
                       isEnabled: false, trigger: "On file save")
        ]

        projects = mergedProjects()
        selectedProject = nil

        pinnedItems = []
    }

    private func loadClawixSessions() {
        // Temporary bridge while the runtime app-server is starting: keep the
        // sidebar useful, but only the app-server index is authoritative once
        // it becomes available.
        let sessions = SessionsIndex.list(limit: 60)
        recentSessions = sessions
        let threads = sessions.map {
            AgentThreadSummary(
                id: $0.id,
                cwd: $0.cwd,
                name: titlesRepo.title(for: $0.id),
                preview: $0.firstMessage,
                path: $0.path.path,
                createdAt: Int64($0.updatedAt.timeIntervalSince1970),
                updatedAt: Int64($0.updatedAt.timeIntervalSince1970),
                archived: false
            )
        }
        applyThreads(threads)
    }

    func loadThreadsFromRuntime() async {
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let pageSize = 160
            var collected: [AgentThreadSummary] = []
            var seenIds = Set<String>()
            var cursor: String? = nil
            var page = 0

            // Pinned ids from Codex's global state. Used as the stop
            // condition for backfilling: keep paginating older threads
            // until every pinned id has been resolved. Without this the
            // sidebar drops pins whose updated_at falls outside the first
            // page (heavy users routinely have >1000 active threads).
            let pinnedTargets = Set(BackendStateReader.read().pinnedThreadIds)
            var resolvedPins = Set<String>()
            // Safety cap so a corrupt cursor or a stale pin id doesn't
            // turn this into an unbounded sweep.
            let maxPages = 12

            repeat {
                let result = try await clawix.listThreadsPage(
                    archived: false,
                    cursor: cursor,
                    limit: pageSize,
                    useStateDbOnly: true
                )
                for thread in result.threads where seenIds.insert(thread.id).inserted {
                    collected.append(thread)
                    if pinnedTargets.contains(thread.id) {
                        resolvedPins.insert(thread.id)
                    }
                }
                cursor = result.nextCursor
                page += 1
                if cursor == nil { break }
                if page == 1 && resolvedPins.count == pinnedTargets.count { break }
                if page >= maxPages { break }
            } while resolvedPins.count < pinnedTargets.count

            applyThreads(collected)
        } catch {
            appendRuntimeStatusError(L10n.runtimeIndexReadFailed("\(error)"))
        }
    }

    /// Pulls the threads belonging to a single project from the runtime
    /// and merges them into `chats`. The runtime's global `thread/list`
    /// is capped at 100 results, so projects whose recent activity sits
    /// outside that window otherwise appear empty in the sidebar; this
    /// fills them on demand when the user expands the accordion.
    func loadThreadsForProject(_ project: Project) async {
        guard let clawix, case .ready = clawix.status else { return }
        if lazyLoadedProjects.contains(project.id) { return }
        if loadingProjects.contains(project.id) { return }
        loadingProjects.insert(project.id)
        defer { loadingProjects.remove(project.id) }
        do {
            let threads = try await clawix.listThreads(
                archived: false,
                cwd: project.path,
                limit: 200,
                useStateDbOnly: true
            )
            mergeThreads(threads)
            lazyLoadedProjects.insert(project.id)
        } catch {
            appendRuntimeStatusError("Could not load threads for project \(project.name): \(error)")
        }
    }

    private func mergedProjects() -> [Project] {
        let localPaths = Set(projectsRepo.all().map(\.path).filter { !$0.isEmpty })
        let hidden = Set(hiddenRootsRepo.allHidden())
        // Drop Codex roots the user explicitly hid. Local projects with the
        // same path stay visible (hidden_codex_roots only filters the
        // backend-sourced bucket; the local entry is the user's own data).
        var result = backendState.workspaceRoots.filter { root in
            if hidden.contains(root.path) && !localPaths.contains(root.path) {
                return false
            }
            return true
        }
        var seen = Set(result.map { $0.path })
        for project in projectsRepo.all() {
            guard !project.path.isEmpty, !seen.contains(project.path) else { continue }
            seen.insert(project.path)
            result.append(Project(
                id: StableProjectID.uuid(for: project.path),
                name: project.name,
                path: project.path
            ))
        }
        return result
    }

    /// True when the path corresponds to a Codex-sourced workspace root
    /// that does NOT also exist as a local project. Used by the sidebar
    /// context menu to expose the "Hide from sidebar" affordance only on
    /// Codex roots; local projects offer "Delete" instead.
    func isCodexSourcedProject(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let isCodexRoot = backendState.workspaceRoots.contains(where: { $0.path == path })
        let isLocal = projectsRepo.all().contains(where: { $0.path == path })
        return isCodexRoot && !isLocal
    }

    func hideCodexRoot(path: String) {
        guard isCodexSourcedProject(path: path) else { return }
        hiddenRootsRepo.hide(path)
        projects = mergedProjects()
    }

    func showCodexRoot(path: String) {
        hiddenRootsRepo.show(path)
        projects = mergedProjects()
    }

    func hiddenCodexRoots() -> [String] {
        hiddenRootsRepo.allHidden()
    }

    /// True when the user has taken local control of pins (after the
    /// first pin/unpin/reorder action). False on a fresh install where
    /// pins still come from Codex's global state file.
    var pinsAreLocal: Bool { metaRepo.hasLocalPins }

    func localOverrideCounts() -> Database.LocalOverrideCounts {
        Database.LocalOverrideCounts(
            pins: pinsRepo.count(),
            projects: projectsRepo.count(),
            chatProjectOverrides: chatProjectsRepo.overridesCount(),
            projectlessThreads: chatProjectsRepo.projectlessCount(),
            archives: archivesRepo.count(),
            titles: titlesRepo.count(),
            hiddenRoots: hiddenRootsRepo.count()
        )
    }

    /// Wipe all local user-curated state and rebuild from the runtime on
    /// the next reload. Codex's data and other Codex apps are NOT
    /// touched. Triggered from Settings via the destructive confirmation
    /// dialog.
    func resetLocalOverrides() {
        Database.shared.resetLocalOverrides()
        // Refresh in-memory derived state so SwiftUI rerenders without
        // waiting for the next runtime reload.
        pinnedOrder = []
        projects = mergedProjects()
        titlesRepo.reload()
        Task { @MainActor in
            await loadThreadsFromRuntime()
        }
    }

    /// First-paint pre-population of `chats[]` and `pinnedOrder` from
    /// the SQLite snapshot of the last applied state. Reads at most
    /// `firstPaintLimit` rows so a huge thread history doesn't slow the
    /// initial paint; the rest is filled in when applyThreads runs.
    /// No-op when the snapshot is empty (the caller leaves chats empty
    /// like before, and the runtime fills them via applyThreads).
    private func applySnapshotForFirstPaint() {
        guard snapshotEnabled else { return }
        // Populate projects unconditionally so the sidebar's project
        // sections are present from the very first paint, even on a
        // fresh install where the snapshot is still empty.
        projects = mergedProjects()
        let firstPaintLimit = 200
        let rows = snapshotRepo.loadTop(limit: firstPaintLimit)
        guard !rows.isEmpty else { return }

        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })

        let restored: [Chat] = rows.compactMap { row in
            guard let id = UUID(uuidString: row.chatUuid) else { return nil }
            let projectId = row.projectPath
                .flatMap { path in projectByPath[path]?.id }
            return Chat(
                id: id,
                title: row.title,
                messages: [],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                clawixThreadId: row.threadId,
                rolloutPath: nil,
                historyHydrated: false,
                hasActiveTurn: false,
                projectId: projectId,
                isArchived: row.archived != 0,
                isPinned: row.pinned != 0,
                hasUnreadCompletion: false,
                cwd: row.cwd,
                hasGitRepo: false,
                branch: nil,
                availableBranches: [],
                uncommittedFiles: nil
            )
        }
        chats = restored

        let pinIds = metaRepo.hasLocalPins ? pinsRepo.orderedThreadIds() : backendState.pinnedThreadIds
        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    /// Rewrite the SQLite snapshot from the current in-memory `chats`
    /// list. Called after every applyThreads / mergeThreads. Skipped
    /// when fixtures drive the threads list so tests stay deterministic.
    /// The actual write goes off-main via GRDB's serialized queue.
    private func persistSidebarSnapshot() {
        guard snapshotEnabled else { return }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let now = Int64(Date().timeIntervalSince1970)
        let rows: [SidebarSnapshotRow] = chats.compactMap { chat in
            guard let threadId = chat.clawixThreadId else { return nil }
            return SidebarSnapshotRow(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectPath: chat.projectId.flatMap { projectsById[$0]?.path },
                updatedAt: Int64(chat.createdAt.timeIntervalSince1970),
                archived: chat.isArchived ? 1 : 0,
                pinned: chat.isPinned ? 1 : 0,
                capturedAt: now
            )
        }
        let repo = snapshotRepo
        Task.detached(priority: .background) {
            repo.replaceAll(rows)
        }
    }

    private func applyThreads(_ threads: [AgentThreadSummary]) {
        backendState = BackendStateReader.read()
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = metaRepo.hasLocalPins ? pinsRepo.orderedThreadIds() : backendState.pinnedThreadIds
        let pinnedSet = Set(pinIds)

        reconcileArchivesFromRuntime(threads)

        let oldByThread = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })

        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }
        chats = sorted.map { thread in
            chatFromThread(thread,
                           old: oldByThread[thread.id],
                           projectByPath: projectByPath,
                           pinnedSet: pinnedSet)
        }

        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
        writeE2EStateReportIfRequested()
        persistSidebarSnapshot()
    }

    /// Like `applyThreads` but additive: refreshes existing chats from the
    /// new payload and appends previously-unknown ones, instead of
    /// replacing the whole list. Used by per-project lazy loads so they
    /// don't wipe chats from other projects already in memory.
    private func mergeThreads(_ threads: [AgentThreadSummary]) {
        backendState = BackendStateReader.read()
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = metaRepo.hasLocalPins ? pinsRepo.orderedThreadIds() : backendState.pinnedThreadIds
        let pinnedSet = Set(pinIds)

        reconcileArchivesFromRuntime(threads)

        var indexByThread: [String: Int] = [:]
        for (idx, chat) in chats.enumerated() {
            if let tid = chat.clawixThreadId { indexByThread[tid] = idx }
        }

        var updated = chats
        for thread in threads {
            if let idx = indexByThread[thread.id] {
                updated[idx] = chatFromThread(thread,
                                              old: updated[idx],
                                              projectByPath: projectByPath,
                                              pinnedSet: pinnedSet)
            } else {
                updated.append(chatFromThread(thread,
                                              old: nil,
                                              projectByPath: projectByPath,
                                              pinnedSet: pinnedSet))
            }
        }
        chats = updated

        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
        writeE2EStateReportIfRequested()
        persistSidebarSnapshot()
    }

    private func chatFromThread(_ thread: AgentThreadSummary,
                                old: Chat?,
                                projectByPath: [String: Project],
                                pinnedSet: Set<String>) -> Chat {
        let rootPath = rootPath(for: thread, projectByPath: projectByPath)
        let archived = archivesRepo.isArchived(thread.id)
        return Chat(
            id: old?.id ?? UUID(),
            title: resolveTitle(for: thread),
            messages: old?.messages ?? [],
            createdAt: thread.updatedDate,
            clawixThreadId: thread.id,
            rolloutPath: thread.path.map { URL(fileURLWithPath: $0) },
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: old?.hasActiveTurn ?? false,
            projectId: rootPath.flatMap { projectByPath[$0]?.id },
            isArchived: archived,
            isPinned: !archived && pinnedSet.contains(thread.id),
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: thread.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles
        )
    }

    /// When sync is on, reflect the runtime's archive flag into local_archives.
    /// Captures changes made externally (Codex CLI, Electron app) so the next
    /// chatFromThread call sees the right state via the repo. No-op when sync
    /// is off — the local DB stays independent.
    private func reconcileArchivesFromRuntime(_ threads: [AgentThreadSummary]) {
        guard SyncSettings.syncArchiveWithCodex else { return }
        for thread in threads {
            let runtimeSays = thread.archived
            let localSays = archivesRepo.isArchived(thread.id)
            if runtimeSays == localSays { continue }
            if runtimeSays {
                archivesRepo.archive(thread.id)
            } else {
                archivesRepo.unarchive(thread.id)
            }
        }
    }

    private func rootPath(for thread: AgentThreadSummary, projectByPath: [String: Project]) -> String? {
        if chatProjectsRepo.isProjectless(thread.id) {
            return nil
        }
        if let local = chatProjectsRepo.overridePath(for: thread.id), projectByPath[local] != nil {
            return local
        }
        if backendState.projectlessThreadIds.contains(thread.id) {
            return nil
        }
        if let official = backendState.threadWorkspaceRootHints[thread.id], projectByPath[official] != nil {
            return official
        }
        guard let cwd = thread.cwd else { return nil }
        return bestProjectRoot(for: cwd, in: projectByPath.keys)
    }

    private func bestProjectRoot(for cwd: String, in roots: Dictionary<String, Project>.Keys) -> String? {
        let normalizedCwd = (cwd as NSString).expandingTildeInPath
        return roots
            .filter { root in
                normalizedCwd == root || normalizedCwd.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
            .max { $0.count < $1.count }
    }

    private func resolveTitle(for thread: AgentThreadSummary) -> String {
        if let name = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let preview = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty { return String(preview.prefix(60)) }
        return "Conversation"
    }

    private func appendRuntimeStatusError(_ message: String) {
        guard case let .chat(chatId) = currentRoute else { return }
        appendErrorBubble(chatId: chatId, message: message)
    }

    private func writeE2EStateReportIfRequested() {
        guard
            let raw = ProcessInfo.processInfo.environment["CLAWIX_E2E_STATE_REPORT"],
            !raw.isEmpty
        else { return }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let payload: [String: Any] = [
            "projects": projects.map { ["name": $0.name, "path": $0.path] },
            "chats": chats.map { chat in
                [
                    "threadId": chat.clawixThreadId ?? "",
                    "title": chat.title,
                    "projectPath": chat.projectId.flatMap { projectsById[$0]?.path } ?? "",
                    "isPinned": chat.isPinned,
                    "isArchived": chat.isArchived
                ] as [String: Any]
            },
            "pinnedCount": chats.filter { $0.isPinned }.count,
            "archivedCount": chats.filter { $0.isArchived }.count
        ]
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func applyLaunchRoute() {
        let arguments = ProcessInfo.processInfo.arguments
        let argumentRoute = arguments.indices
            .first(where: { arguments[$0] == "--route" && arguments.indices.contains($0 + 1) })
            .map { arguments[$0 + 1] }
        let env = ProcessInfo.processInfo.environment
        let legacyRouteKey = ["CLAWIX", "REP" + "LICA", "ROUTE"].joined(separator: "_")
        let route = argumentRoute ?? env["CLAWIX_ROUTE"] ?? env[legacyRouteKey] ?? ""
        switch route {
        case "search":
            currentRoute = .search
            searchQuery = "authentication"
            performSearch(searchQuery)
        case "plugins":
            currentRoute = .plugins
        case "automations":
            currentRoute = .automations
        case "project":
            currentRoute = .project
        case "settings":
            currentRoute = .settings
        case "chat":
            chats = [sampleChat]
            currentRoute = .chat(sampleChat.id)
        case "chat-browser":
            chats = [browserSampleChat, sampleChat]
            currentRoute = .chat(browserSampleChat.id)
        case "browser":
            currentRoute = .home
            openBrowser()
        default:
            currentRoute = .home
        }
    }

    func performSearch(_ query: String) {
        searchQuery = query
        guard !query.isEmpty else { searchResults = []; return }
        searchResults = [
            "main.swift — match for \"\(query)\" on line 12",
            "ContentView.swift — match for \"\(query)\" on line 34",
            "AppState.swift — match for \"\(query)\" on line 78"
        ]
    }

    func sendMessage() {
        let trimmed = composer.text.trimmingCharacters(in: .whitespaces)
        let attachments = composer.attachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let mentions = attachments.map { "@\($0.url.path)" }.joined(separator: " ")
        let combined: String
        if trimmed.isEmpty {
            combined = mentions
        } else if mentions.isEmpty {
            combined = trimmed
        } else {
            combined = mentions + "\n\n" + trimmed
        }

        let userMsg = ChatMessage(role: .user, content: combined, timestamp: Date())
        let chatId: UUID
        if case .chat(let id) = currentRoute,
           let idx = chats.firstIndex(where: { $0.id == id }) {
            chats[idx].messages.append(userMsg)
            chatId = id
        } else {
            // Create a new chat from home screen — inherits the project
            // currently selected in the composer pill (if any).
            let titleSeed = trimmed.isEmpty ? (attachments.first?.filename ?? "Adjuntos") : trimmed
            let newChat = Chat(
                id: UUID(),
                title: String(titleSeed.prefix(40)),
                messages: [userMsg],
                createdAt: Date(),
                projectId: selectedProject?.id
            )
            chats.insert(newChat, at: 0)
            currentRoute = .chat(newChat.id)
            chatId = newChat.id
        }
        composer.text = ""
        composer.attachments = []

        if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    /// Entry point used by the bridge that exposes the desktop app to the
    /// iOS companion. Mirrors the user-message half of `sendMessage()` but
    /// takes the chat id and text as parameters rather than reading from
    /// the composer; attachments and new-chat creation are out of scope
    /// for the MVP.
    @MainActor
    func sendUserMessageFromBridge(chatId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }

        let userMsg = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        chats[idx].messages.append(userMsg)

        if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: trimmed)
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    func addComposerAttachments(_ urls: [URL]) {
        let existing = Set(composer.attachments.map { $0.url.standardizedFileURL.path })
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !existing.contains(path) else { continue }
            composer.attachments.append(ComposerAttachment(url: url))
        }
    }

    func removeComposerAttachment(id: UUID) {
        composer.attachments.removeAll { $0.id == id }
    }

    /// Pulls keyboard focus back into the composer text field. Used by
    /// ⌘N (when the home screen is already mounted), chat switches and
    /// other places where the same composer view stays mounted but the
    /// user's intent is "let me start typing now".
    func requestComposerFocus() {
        composer.focusToken &+= 1
    }

    /// Called by ComposerView's Stop button.
    func interruptActiveTurn() {
        guard case let .chat(id) = currentRoute else { return }
        // Update UI synchronously so the "Thinking" shimmer disappears
        // immediately on click. The backend interrupt is fire-and-forget;
        // late-arriving deltas for this turn are dropped by ClawixService
        // via its interruptedTurnIds gate.
        finalizeOrRemoveAssistantPlaceholder(chatId: id)
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.interruptCurrentTurn(chatId: id)
        }
    }

    /// Drop the chat out of the "Pensando…" / streaming state right now.
    /// If the assistant placeholder is still empty (no text, no reasoning,
    /// no tool activity), remove it entirely so the chat ends on the user's
    /// message. If it has any visible content, freeze it as finished so the
    /// shimmer stops but the partial answer stays.
    func finalizeOrRemoveAssistantPlaceholder(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].hasActiveTurn = false
        guard let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant,
              !chats[idx].messages[last].streamingFinished
        else { return }
        let msg = chats[idx].messages[last]
        // A workSummary that's been initialized but never received items
        // (turn/started fired, then user stopped before any delta) renders
        // nothing on its own: the WorkSummaryHeader requires items, and the
        // timeline mirrors items 1:1. Treat that as empty so we drop the
        // placeholder entirely instead of leaving an invisible row whose
        // only visible artifact would be the trailing action bar.
        let workSummaryEmpty = msg.workSummary?.items.isEmpty ?? true
        let isEmpty = msg.content.isEmpty
            && msg.reasoningText.isEmpty
            && msg.timeline.isEmpty
            && workSummaryEmpty
        if isEmpty {
            chats[idx].messages.remove(at: last)
        } else {
            chats[idx].messages[last].streamingFinished = true
        }
    }

    // MARK: - Clawix bridge helpers

    /// CWD reported to thread/start. Falls back to $HOME so Clawix never
    /// refuses to start. Order: current chat's project > selectedProject > $HOME.
    var threadCwd: String {
        if case let .chat(id) = currentRoute,
           let chat = chats.first(where: { $0.id == id }),
           let pid = chat.projectId,
           let proj = projects.first(where: { $0.id == pid }) {
            let expanded = (proj.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        if let project = selectedProject {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Maps the dropdown label ("5.5", "5.4 Mini", …) to a Clawix slug.
    var clawixModelSlug: String? {
        let raw = selectedModel.lowercased().replacingOccurrences(of: " ", with: "-")
        return "gpt-\(raw)"
    }

    var clawixEffort: String? {
        selectedIntelligence.clawixEffort
    }

    /// "fast" → priority queue (1.5× faster, higher usage).
    /// `nil` → default tier. The schema also accepts "flex" but the
    /// composer does not expose it today.
    var clawixServiceTier: String? {
        switch selectedSpeed {
        case .standard: return nil
        case .fast:     return "fast"
        }
    }

    func ensureSelectedChat(triggerHistoryHydration: Bool = true) {
        guard case let .chat(id) = currentRoute,
              let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        if triggerHistoryHydration && !chats[idx].historyHydrated {
            hydrateHistoryIfNeeded(chatIndex: idx)
        }
    }

    private func hydrateHistoryIfNeeded(chatIndex: Int) {
        let chat = chats[chatIndex]
        guard !chat.historyHydrated else { return }
        if !chat.hasGitRepo, let cwd = chat.cwd {
            let git = GitInspector.inspect(cwd: cwd)
            chats[chatIndex].hasGitRepo = git.hasRepo
            chats[chatIndex].branch = git.branch
            chats[chatIndex].availableBranches = git.branches
            chats[chatIndex].uncommittedFiles = git.uncommittedFiles
        }
        if let path = chat.rolloutPath {
            let entries = RolloutReader.read(path: path)
            chats[chatIndex].messages = entries.map { e in
                ChatMessage(
                    role: e.role == .user ? .user : .assistant,
                    content: e.text,
                    reasoningText: "",
                    streamingFinished: true,
                    timestamp: e.timestamp,
                    timeline: e.timeline
                )
            }
        }
        chats[chatIndex].historyHydrated = true
        if let threadId = chat.clawixThreadId, let clawix {
            Task { @MainActor in
                await clawix.attach(chatId: chat.id, threadId: threadId)
            }
        }
    }

    /// Bridge entry point. Hydrates a chat's history from its rollout
    /// file the first time the iPhone opens it, mirroring what the Mac
    /// UI does the moment a chat row is clicked. Without this the
    /// iPhone gets `messagesSnapshot([])` for every `notLoaded` thread
    /// and the user only sees the "no messages loaded" empty state.
    /// Idempotent: subsequent calls for the same chat are no-ops.
    func hydrateHistoryFromBridge(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        hydrateHistoryIfNeeded(chatIndex: idx)
    }

    // MARK: - ClawixService callbacks

    func attachThreadId(_ threadId: String, to chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].clawixThreadId = threadId
        chats[idx].historyHydrated = true
        // Reflect any pre-attach state onto the freshly-known thread id:
        // a chat created already pinned, or with a project selected,
        // must persist now that we have an id to key by.
        let chat = chats[idx]
        if chat.isPinned {
            pinsRepo.setPinned(threadId, atEnd: true)
            metaRepo.hasLocalPins = true
        }
        if let pid = chat.projectId,
           let project = projects.first(where: { $0.id == pid }), !project.path.isEmpty {
            chatProjectsRepo.setOverride(threadId: threadId, projectPath: project.path)
        }
    }

    func appendAssistantPlaceholder(chatId: UUID) -> UUID? {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return nil }
        let msg = ChatMessage(
            role: .assistant,
            content: "",
            reasoningText: "",
            streamingFinished: false
        )
        chats[idx].messages.append(msg)
        return msg.id
    }

    func appendAssistantDelta(chatId: UUID, delta: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        chats[idx].messages[last].content += delta
        let cps = chats[idx].messages[last].streamCheckpoints
        let result = StreamingFade.ingest(
            delta: delta,
            pendingTail: chats[idx].messages[last].streamPendingTail,
            scheduledLength: cps.last?.prefixCount ?? 0,
            lastFadeStart: cps.last?.addedAt ?? .distantPast
        )
        if !result.newCheckpoints.isEmpty {
            chats[idx].messages[last].streamCheckpoints
                .append(contentsOf: result.newCheckpoints)
        }
        chats[idx].messages[last].streamPendingTail = result.pendingTail
    }

    func appendReasoningDelta(chatId: UUID, delta: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        chats[idx].messages[last].reasoningText += delta
        // Extend the trailing reasoning chunk in the timeline, or open a
        // new one if the last entry is a tools group (so the row order
        // becomes text → tools → text → tools → …).
        let timeline = chats[idx].messages[last].timeline
        let entryId: UUID
        let newText: String
        if let lastEntry = timeline.last,
           case .reasoning(let existingId, let existing) = lastEntry {
            entryId = existingId
            newText = existing + delta
            chats[idx].messages[last].timeline[timeline.count - 1] =
                .reasoning(id: entryId, text: newText)
        } else {
            entryId = UUID()
            newText = delta
            chats[idx].messages[last].timeline.append(
                .reasoning(id: entryId, text: newText)
            )
        }
        let bucket = chats[idx].messages[last].reasoningCheckpoints[entryId, default: []]
        let pending = chats[idx].messages[last].reasoningPendingTails[entryId, default: ""]
        let result = StreamingFade.ingest(
            delta: delta,
            pendingTail: pending,
            scheduledLength: bucket.last?.prefixCount ?? 0,
            lastFadeStart: bucket.last?.addedAt ?? .distantPast
        )
        if !result.newCheckpoints.isEmpty {
            chats[idx].messages[last].reasoningCheckpoints[entryId, default: []]
                .append(contentsOf: result.newCheckpoints)
        }
        chats[idx].messages[last].reasoningPendingTails[entryId] = result.pendingTail
    }

    func markAssistantCompleted(chatId: UUID, finalText: String?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        if let text = finalText, !text.isEmpty {
            // If the canonical final body differs from what we accumulated
            // from deltas, the existing per-word checkpoints don't line up
            // with the new characters. Replaying every word as a fresh
            // fade-in would look like the answer animates twice. Instead,
            // mark the entire replacement as already settled so the user
            // sees the final body at full opacity without another ramp.
            if text != chats[idx].messages[last].content {
                chats[idx].messages[last].streamCheckpoints = [
                    StreamCheckpoint(prefixCount: text.count, addedAt: .distantPast)
                ]
                chats[idx].messages[last].streamPendingTail = ""
            }
            chats[idx].messages[last].content = text
        }
        chats[idx].messages[last].streamingFinished = true
        // Flush any trailing partial word so its characters get a fade
        // schedule and don't sit at opacity 0 forever.
        let cps = chats[idx].messages[last].streamCheckpoints
        let pending = chats[idx].messages[last].streamPendingTail
        if !pending.isEmpty {
            let flushed = StreamingFade.ingest(
                delta: "",
                pendingTail: pending,
                scheduledLength: cps.last?.prefixCount ?? 0,
                lastFadeStart: cps.last?.addedAt ?? .distantPast,
                flush: true
            )
            if !flushed.newCheckpoints.isEmpty {
                chats[idx].messages[last].streamCheckpoints
                    .append(contentsOf: flushed.newCheckpoints)
            }
            chats[idx].messages[last].streamPendingTail = flushed.pendingTail
        }
        // Same for every reasoning chunk in the timeline.
        for entry in chats[idx].messages[last].timeline {
            guard case .reasoning(let entryId, _) = entry else { continue }
            let rcps = chats[idx].messages[last].reasoningCheckpoints[entryId] ?? []
            let rpending = chats[idx].messages[last].reasoningPendingTails[entryId] ?? ""
            guard !rpending.isEmpty else { continue }
            let flushed = StreamingFade.ingest(
                delta: "",
                pendingTail: rpending,
                scheduledLength: rcps.last?.prefixCount ?? 0,
                lastFadeStart: rcps.last?.addedAt ?? .distantPast,
                flush: true
            )
            if !flushed.newCheckpoints.isEmpty {
                chats[idx].messages[last].reasoningCheckpoints[entryId, default: []]
                    .append(contentsOf: flushed.newCheckpoints)
            }
            chats[idx].messages[last].reasoningPendingTails[entryId] = flushed.pendingTail
        }
        // If the user wasn't looking at this chat when the turn finished,
        // surface the soft-blue unread dot in the sidebar so they can spot
        // the freshly-arrived reply at a glance.
        if !isCurrentRoute(chatId: chatId) {
            chats[idx].hasUnreadCompletion = true
        }
    }

    private func isCurrentRoute(chatId: UUID) -> Bool {
        if case let .chat(id) = currentRoute, id == chatId { return true }
        return false
    }

    private func clearUnreadIfChatRoute() {
        guard case let .chat(id) = currentRoute,
              let idx = chats.firstIndex(where: { $0.id == id }),
              chats[idx].hasUnreadCompletion
        else { return }
        chats[idx].hasUnreadCompletion = false
    }

    func markChat(chatId: UUID, hasActiveTurn: Bool) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].hasActiveTurn = hasActiveTurn
    }

    /// Flip the sidebar's blue "unread" dot on the row, regardless of
    /// whether the user is currently looking at the chat. Used by the
    /// row's right-click "Mark as unread" / "Mark as read" actions.
    func toggleChatUnread(chatId: UUID) {
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            chats[idx].hasUnreadCompletion.toggle()
        } else if let idx = archivedChats.firstIndex(where: { $0.id == chatId }) {
            archivedChats[idx].hasUnreadCompletion.toggle()
        }
    }

    // MARK: - Plan mode

    /// Toggle the global plan-mode flag from the slash command, the
    /// "+" menu, or the composer pill. Wraps in a transaction so any
    /// observer (composer pill, sidebar) updates atomically.
    func togglePlanMode() {
        planMode.toggle()
    }

    /// Pending plan-mode question for the chat the user is currently
    /// looking at, if any. Drives the question card above the composer.
    var currentPendingPlanQuestion: PendingPlanQuestion? {
        guard case let .chat(id) = currentRoute else { return nil }
        return pendingPlanQuestions[id]
    }

    /// Stash a question coming from `item/tool/requestUserInput` so the
    /// chat view can render it. Called from ClawixService.
    func registerPendingPlanQuestion(_ question: PendingPlanQuestion) {
        pendingPlanQuestions[question.chatId] = question
    }

    /// Resolve the JSON-RPC request with the user's answers and clear
    /// the pending state. `answers` maps each question id to the option
    /// labels (or free text) the user picked.
    func submitPlanAnswers(chatId: UUID, answers: [String: [String]]) {
        guard let pending = pendingPlanQuestions[chatId] else { return }
        pendingPlanQuestions[chatId] = nil
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.respondToPlanQuestion(rpcId: pending.rpcId, answers: answers)
        }
    }

    /// Dismiss the question without picking an option. Sends an empty
    /// answers map so the runtime unblocks the turn.
    func dismissPlanQuestion(chatId: UUID) {
        guard let pending = pendingPlanQuestions[chatId] else { return }
        pendingPlanQuestions[chatId] = nil
        let empty: [String: [String]] = Dictionary(
            uniqueKeysWithValues: pending.questions.map { ($0.id, [String]()) }
        )
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.respondToPlanQuestion(rpcId: pending.rpcId, answers: empty)
        }
    }

    // MARK: - Branch switching (footer pill)

    /// Update the chat's current branch in-memory. The app does not
    /// shell out to `git checkout`; it only reflects the user's choice in
    /// the chrome.
    func switchBranch(chatId: UUID, to branch: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].branch = branch
        if !chats[idx].availableBranches.contains(branch) {
            chats[idx].availableBranches.insert(branch, at: 0)
        }
        chats[idx].uncommittedFiles = nil
    }

    /// Append a new branch to the chat's known list and switch to it.
    /// Mirrors the "Create and switch to a new branch..." flow.
    func createBranch(chatId: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        if !chats[idx].availableBranches.contains(trimmed) {
            chats[idx].availableBranches.insert(trimmed, at: 0)
        }
        chats[idx].branch = trimmed
        chats[idx].uncommittedFiles = nil
    }

    func updateTokenUsage(chatId: UUID, usage: ThreadTokenUsage) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].contextUsage = ContextUsage(
            usedTokens: usage.last.totalTokens,
            contextWindow: usage.modelContextWindow
        )
    }

    /// Context usage for whichever chat the user is currently looking at.
    /// nil when not in a chat route or before the first token-usage event.
    var currentContextUsage: ContextUsage? {
        guard case let .chat(id) = currentRoute,
              let chat = chats.first(where: { $0.id == id })
        else { return nil }
        return chat.contextUsage
    }

    // MARK: - Work summary updates (per assistant message)

    /// Initialize `workSummary` on the given assistant message if it
    /// doesn't have one yet. No-op if the start time is already set.
    func beginWorkSummary(chatId: UUID, messageId: UUID, startedAt: Date) {
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: startedAt, endedAt: nil, items: [])
            }
        }
    }

    /// Insert or update one tool item (commandExecution, fileChange, …)
    /// on the given assistant message. Lazily creates the WorkSummary if
    /// the start event was missed.
    func upsertWorkItem(chatId: UUID, messageId: UUID, item: WorkItem) {
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: Date(), endedAt: nil, items: [])
            }
            if let i = msg.workSummary!.items.firstIndex(where: { $0.id == item.id }) {
                msg.workSummary!.items[i] = item
            } else {
                msg.workSummary!.items.append(item)
            }

            // Mirror the upsert into the chronological timeline so the
            // chat row can render command rows interleaved with reasoning.
            // First try to update an existing entry that already holds
            // this item id (handles started→completed transitions).
            for tIdx in msg.timeline.indices {
                if case .tools(let gid, var items) = msg.timeline[tIdx],
                   let itemIdx = items.firstIndex(where: { $0.id == item.id }) {
                    items[itemIdx] = item
                    msg.timeline[tIdx] = .tools(id: gid, items: items)
                    return
                }
            }
            // New item: extend the trailing tools group only if the last
            // item there is the same family (commands merge, fileChanges
            // merge, everything else opens a fresh row). Matches the
            // rollout reader so live-streamed chats render identically to
            // hydrated history.
            let canMerge: Bool = {
                guard case .tools(_, let items) = msg.timeline.last,
                      let last = items.last else { return false }
                return TimelineFamily.from(last.kind).matches(item.kind)
            }()
            if canMerge, case .tools(let gid, let items) = msg.timeline.last {
                msg.timeline[msg.timeline.count - 1] =
                    .tools(id: gid, items: items + [item])
            } else {
                msg.timeline.append(.tools(id: UUID(), items: [item]))
            }
        }
    }

    /// Mark the WorkSummary as finished (turn/completed). Records the end
    /// time so the live counter freezes.
    func completeWorkSummary(chatId: UUID, messageId: UUID, endedAt: Date) {
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: endedAt, endedAt: endedAt, items: [])
            } else {
                msg.workSummary!.endedAt = endedAt
            }
        }
    }

    private func mutateMessage(chatId: UUID, messageId: UUID, _ body: (inout ChatMessage) -> Void) {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        body(&chats[cIdx].messages[mIdx])
    }

    /// Edit a previous user message and restart the conversation from
    /// that point. Mirrors how Clawix CLI's `thread/rollback` works:
    /// every turn after (and including) this user message is dropped
    /// both locally and on the backend thread, then a fresh `turn/start`
    /// is issued with the new prompt.
    func editUserMessage(chatId: UUID, messageId: UUID, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == messageId }),
              chats[cIdx].messages[mIdx].role == .user
        else { return }

        // A "turn" starts on each user message and runs until the next
        // user message. Number of turns to drop on the backend equals
        // the count of user messages from this index to the end.
        let tail = chats[cIdx].messages[mIdx...]
        let numTurns = tail.reduce(into: 0) { acc, msg in
            if msg.role == .user { acc += 1 }
        }

        // Truncate locally and re-append the edited user bubble so the
        // UI matches the new conversation state immediately.
        chats[cIdx].messages.removeSubrange(mIdx...)
        let edited = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        chats[cIdx].messages.append(edited)

        if let clawix {
            Task { @MainActor in
                await clawix.editAndResubmit(
                    chatId: chatId,
                    numTurnsToDrop: numTurns,
                    newText: trimmed
                )
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    func appendErrorBubble(chatId: UUID, message: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let bubble = ChatMessage(
            role: .assistant,
            content: "Error: \(message)",
            isError: true,
            timestamp: Date()
        )
        chats[idx].messages.append(bubble)
    }

    // MARK: - Titles

    /// Resolve the visible title for a session id. Layered sources:
    /// titlesRepo (manual user renames + generated overrides + runtime
    /// session index) > truncated first message > localized fallback.
    /// Manual renames win over runtime/generated through the latest
    /// updated_at fold inside the repository.
    private func resolveTitle(forSessionId id: String, firstMessage: String) -> String {
        if let stored = titlesRepo.title(for: id) {
            return stored
        }
        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Conversation" }
        return String(trimmed.prefix(60))
    }

    /// Persist a freshly-generated title and refresh the matching chat
    /// row. Called from TitleGenerator on the main actor.
    func applyGeneratedTitle(sessionId: String, title: String) {
        applyRuntimeTitle(threadId: sessionId, title: title)
    }

    /// Hook called by ClawixService when a turn completes. If the chat
    /// still has a fallback-style title, fire title generation now that
    /// we have at least one user + one assistant message in memory.
    func maybeGenerateTitleAfterTurn(chatId: UUID) {
        titledChatIds.insert(chatId)
    }

    // MARK: - Rename

    func renameChat(chatId: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        guard let threadId = chats[idx].clawixThreadId,
              let clawix,
              case .ready = clawix.status else {
            appendErrorBubble(chatId: chatId, message: "Renaming requires the runtime to be available.")
            return
        }
        var copy = chats
        copy[idx].title = trimmed
        chats = copy
        titlesRepo.upsertManual(threadId: threadId, title: trimmed)

        guard SyncSettings.syncRenamesWithCodex else { return }
        Task { @MainActor in
            do {
                try await clawix.setThreadName(threadId: threadId, name: trimmed)
            } catch {
                self.appendErrorBubble(chatId: chatId, message: "Could not rename on the runtime: \(error)")
            }
        }
    }

    func applyRuntimeTitle(threadId: String, title: String) {
        guard let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = chats
        copy[idx].title = trimmed
        chats = copy
    }

    func archiveChat(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let threadId = chats[idx].clawixThreadId

        // Dummy / in-memory chat (no runtime thread): just move it locally so
        // the archived UI is exercisable without a backend.
        guard let threadId else {
            archiveLocally(chatIndex: idx)
            return
        }

        // Local DB is the source of truth. Mark archived first; the runtime
        // call is an optional mirror gated by SyncSettings.
        archivesRepo.archive(threadId)
        markThreadArchived(threadId: threadId, archived: true)

        guard SyncSettings.syncArchiveWithCodex else { return }
        guard let clawix, case .ready = clawix.status else {
            // Sync requested but runtime not available: roll back local state
            // so the user is not silently divergent from Codex.
            archivesRepo.unarchive(threadId)
            markThreadArchived(threadId: threadId, archived: false)
            appendErrorBubble(chatId: chatId, message: "Archiving requires the runtime to be available.")
            return
        }
        Task { @MainActor in
            do {
                try await clawix.archiveThread(threadId: threadId)
            } catch {
                self.archivesRepo.unarchive(threadId)
                self.markThreadArchived(threadId: threadId, archived: false)
                self.appendErrorBubble(chatId: chatId, message: "Could not archive on the runtime: \(error)")
            }
        }
    }

    private func archiveLocally(chatIndex idx: Int) {
        var chat = chats[idx]
        chat.isArchived = true
        chat.isPinned = false
        chat.hasUnreadCompletion = false
        pinnedOrder.removeAll { $0 == chat.id }
        if case let .chat(id) = currentRoute, id == chat.id {
            currentRoute = .home
        }
        chats.remove(at: idx)
        archivedChats.insert(chat, at: 0)
        if archivedChats.count > Self.archivedSidebarLimit {
            archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
        }
    }

    func markThreadArchived(threadId: String, archived: Bool) {
        if archived {
            guard let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) else { return }
            var chat = chats[idx]
            chat.isArchived = true
            chat.isPinned = false
            chat.hasUnreadCompletion = false
            pinnedOrder.removeAll { $0 == chat.id }
            if case let .chat(id) = currentRoute, id == chat.id {
                currentRoute = .home
            }
            chats.remove(at: idx)
            archivedChats.removeAll { $0.clawixThreadId == threadId }
            archivedChats.insert(chat, at: 0)
            if archivedChats.count > Self.archivedSidebarLimit {
                archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
            }
        } else {
            if let idx = archivedChats.firstIndex(where: { $0.clawixThreadId == threadId }) {
                var chat = archivedChats[idx]
                chat.isArchived = false
                archivedChats.remove(at: idx)
                if !chats.contains(where: { $0.clawixThreadId == threadId }) {
                    chats.insert(chat, at: 0)
                }
            } else if let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) {
                chats[idx].isArchived = false
            }
        }
    }

    /// Lazy fetch of archived threads for the sidebar's archived section.
    /// First expand triggers the network round-trip; subsequent toggles
    /// reuse the cached list unless `force` is set.
    func loadArchivedChats(force: Bool = false) async {
        guard let clawix, case .ready = clawix.status else { return }
        if archivedLoading { return }
        if archivedLoaded && !force { return }
        archivedLoading = true
        defer { archivedLoading = false }
        do {
            let threads = try await clawix.listThreads(
                archived: true,
                limit: Self.archivedSidebarLimit,
                useStateDbOnly: true
            )
            let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
            let oldByThread = Dictionary(uniqueKeysWithValues: archivedChats.compactMap { chat in
                chat.clawixThreadId.map { ($0, chat) }
            })
            archivedChats = threads
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { thread in
                    chatFromThread(thread,
                                   old: oldByThread[thread.id],
                                   projectByPath: projectByPath,
                                   pinnedSet: [])
                }
            archivedLoaded = true
        } catch {
            // Non-fatal: the section will render empty + retryable next expand.
            archivedLoaded = false
        }
    }

    func unarchiveChat(chatId: UUID) {
        guard let idx = archivedChats.firstIndex(where: { $0.id == chatId }) else { return }
        let threadId = archivedChats[idx].clawixThreadId
        var moved = archivedChats[idx]
        moved.isArchived = false
        archivedChats.remove(at: idx)

        // Dummy / in-memory chat: pop it back into the active list and stop.
        guard let threadId else {
            chats.insert(moved, at: 0)
            return
        }

        // Local DB is the source of truth.
        archivesRepo.unarchive(threadId)
        if !chats.contains(where: { $0.clawixThreadId == threadId }) {
            chats.insert(moved, at: 0)
        }

        guard SyncSettings.syncArchiveWithCodex else { return }
        guard let clawix, case .ready = clawix.status else {
            // Sync requested but runtime not available: roll back local state.
            archivesRepo.archive(threadId)
            chats.removeAll { $0.id == chatId }
            moved.isArchived = true
            archivedChats.insert(moved, at: min(idx, archivedChats.count))
            return
        }
        Task { @MainActor in
            do {
                try await clawix.unarchiveThread(threadId: threadId)
                await self.loadThreadsFromRuntime()
            } catch {
                self.archivesRepo.archive(threadId)
                self.chats.removeAll { $0.id == chatId }
                moved.isArchived = true
                self.archivedChats.insert(moved, at: min(idx, self.archivedChats.count))
                self.appendErrorBubble(chatId: chatId, message: "Could not unarchive on the runtime: \(error)")
            }
        }
    }

    // MARK: - Pinning

    func togglePin(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        // Explicit array reassignment ensures @Published always fires
        // (subscript-mutation alone occasionally misses observers).
        var copy = chats
        copy[idx].isPinned.toggle()
        chats = copy
        if copy[idx].isPinned {
            if !pinnedOrder.contains(chatId) {
                pinnedOrder.append(chatId)
            }
            if let threadId = copy[idx].clawixThreadId {
                pinsRepo.setPinned(threadId, atEnd: true)
            }
        } else {
            pinnedOrder.removeAll { $0 == chatId }
            if let threadId = copy[idx].clawixThreadId {
                pinsRepo.unpin(threadId)
            }
        }
        metaRepo.hasLocalPins = true
    }

    /// Move a pinned chat to a new slot inside the pinned list. Pass the
    /// chat the moved row should land *before*, or `nil` to drop at the
    /// end. If the chat is not currently pinned (e.g. dragged in from a
    /// project) it is pinned first. Computing the destination relative
    /// to a sibling chat avoids the index-shift bug when the dragged row
    /// is above its target.
    func reorderPinned(chatId: UUID, beforeChatId: UUID?) {
        guard chatId != beforeChatId,
              let chatIdx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        if !copy[chatIdx].isPinned {
            copy[chatIdx].isPinned = true
            chats = copy
        }
        var order = pinnedOrder
        order.removeAll { $0 == chatId }
        if let beforeChatId, let idx = order.firstIndex(of: beforeChatId) {
            order.insert(chatId, at: idx)
        } else {
            order.append(chatId)
        }
        pinnedOrder = order
        let chatsById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        let orderedThreadIds = order.compactMap { chatsById[$0]?.clawixThreadId }
        pinsRepo.setOrder(orderedThreadIds)
        metaRepo.hasLocalPins = true
    }

    // MARK: - Project assignment

    func assignChat(chatId: UUID, toProject projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        chats = copy
        updateProjectOverride(for: copy[idx])
    }

    /// Drag-and-drop helper: drop a chat onto a project. Reassigns it and
    /// unpins it so it visibly leaves the pinned section and lands inside
    /// that project's body. Pass `nil` to drop into the projectless bucket.
    func moveChatToProject(chatId: UUID, projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        let wasPinned = copy[idx].isPinned
        if wasPinned {
            copy[idx].isPinned = false
            pinnedOrder.removeAll { $0 == chatId }
        }
        chats = copy
        if wasPinned, let threadId = copy[idx].clawixThreadId {
            pinsRepo.unpin(threadId)
        }
        updateProjectOverride(for: copy[idx])
    }

    private func updateProjectOverride(for chat: Chat) {
        guard let threadId = chat.clawixThreadId else { return }
        if let projectId = chat.projectId,
           let project = projects.first(where: { $0.id == projectId }) {
            chatProjectsRepo.setOverride(threadId: threadId, projectPath: project.path)
        } else {
            chatProjectsRepo.clearOverride(threadId: threadId)
            chatProjectsRepo.markProjectless(threadId)
        }
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(name: String, path: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = (path as NSString).expandingTildeInPath
        let project = Project(
            id: StableProjectID.uuid(for: normalizedPath.isEmpty ? UUID().uuidString : normalizedPath),
            name: trimmed.isEmpty ? "Untitled" : trimmed,
            path: normalizedPath
        )
        projects.append(project)
        if !project.path.isEmpty {
            projectsRepo.upsert(project)
            if SyncSettings.pushProjectsToCodex {
                CodexStateWriter.upsertWorkspaceRoot(path: project.path, label: project.name)
            }
        }
        return project
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        if selectedProject?.id == project.id { selectedProject = project }
        if !project.path.isEmpty {
            projectsRepo.upsert(project)
            if SyncSettings.pushProjectsToCodex {
                CodexStateWriter.upsertWorkspaceRoot(path: project.path, label: project.name)
            }
        }
    }

    /// Removes a project. Chats previously assigned to it become projectless.
    func deleteProject(_ projectId: UUID) {
        projects.removeAll { $0.id == projectId }
        for idx in chats.indices where chats[idx].projectId == projectId {
            chats[idx].projectId = nil
            updateProjectOverride(for: chats[idx])
        }
        if selectedProject?.id == projectId { selectedProject = nil }
        projectsRepo.delete(id: projectId)
    }

    func renameProject(id: UUID, newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        let projectPath = projects[idx].path
        if selectedProject?.id == id { selectedProject = projects[idx] }
        projectsRepo.rename(id: id, to: trimmed)
        if SyncSettings.pushProjectsToCodex, !projectPath.isEmpty {
            CodexStateWriter.renameWorkspaceLabel(path: projectPath, label: trimmed)
        }
    }

    /// Convenience: start a new chat scoped to a specific project.
    /// Selects the project in the composer pill and routes Home so the
    /// next message creates a chat associated with it.
    func startNewChat(in project: Project) {
        selectedProject = project
        currentRoute = .home
    }

    // MARK: - Sidebar (per-chat web tabs and file previews)

    private static let sidebarDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private static let chatSidebarsKey = "ChatSidebars"
    private static let hostFaviconsKey = "HostFavicons"
    private static let legacyBrowserStateKey = "BrowserTabs"
    private static let legacyBrowserActiveKey = "BrowserActiveTabId"

    /// UUID of the chat the user is currently viewing, if any. Returns nil
    /// for non-chat routes (home, settings, etc.) so write-time accessors
    /// silently no-op when there is no chat to attach state to.
    var currentChatId: UUID? {
        if case .chat(let id) = currentRoute { return id }
        return nil
    }

    /// Sidebar state for the active chat (or `.empty` outside chat
    /// routes). Setter persists and removes empty entries so the dict
    /// doesn't grow forever.
    var currentSidebar: ChatSidebarState {
        get {
            guard let id = currentChatId else { return .empty }
            return chatSidebars[id] ?? .empty
        }
        set {
            guard let id = currentChatId else { return }
            if newValue == .empty {
                chatSidebars.removeValue(forKey: id)
            } else {
                chatSidebars[id] = newValue
            }
            persistChatSidebars()
        }
    }

    var isRightSidebarOpen: Bool {
        get { currentSidebar.isOpen }
        set {
            var s = currentSidebar
            s.isOpen = newValue
            currentSidebar = s
        }
    }

    var sidebarItems: [SidebarItem] { currentSidebar.items }

    var activeSidebarItemId: UUID? {
        get { currentSidebar.activeItemId }
        set {
            var s = currentSidebar
            s.activeItemId = newValue
            currentSidebar = s
        }
    }

    var activeSidebarItem: SidebarItem? { currentSidebar.activeItem }

    /// Convenience for the corner-cutout colour sampling: returns the id
    /// of the active item only when it's a web tab (file previews don't
    /// sample a page colour).
    var activeWebTabId: UUID? {
        if case .web(let p) = activeSidebarItem { return p.id }
        return nil
    }

    func openBrowser(initialURL: URL = URL(string: "https://www.google.com")!) {
        guard currentChatId != nil else { return }
        var s = currentSidebar
        if let firstWeb = s.items.first(where: { if case .web = $0 { return true } else { return false } }) {
            s.activeItemId = firstWeb.id
        } else {
            let item = SidebarItem.web(.init(
                id: UUID(),
                url: initialURL,
                title: "",
                faviconURL: cachedFavicon(forSite: initialURL)
            ))
            s.items.append(item)
            s.activeItemId = item.id
        }
        s.isOpen = true
        currentSidebar = s
    }

    /// Tap target for any inline link inside chat content. Opens the URL in
    /// the active chat's sidebar and brings the panel forward, so the user
    /// never bounces out to the system browser. If the same URL is already
    /// open in an existing tab of this chat, that tab is activated and
    /// reloaded instead of duplicating it. `file://` URLs are routed to
    /// the file viewer instead of the browser tab so a `[abrir markdown]
    /// (/abs/path.md)` link from the assistant lands on the same preview
    /// surface as the trailing `ChangedFileCard` pill.
    func openLinkInBrowser(_ url: URL) {
        if url.isFileURL {
            openFileInSidebar(url.path)
            return
        }
        guard currentChatId != nil else { return }
        var s = currentSidebar
        let key = Self.browserDedupKey(for: url)
        if let existing = s.items.first(where: {
            if case .web(let p) = $0 { return Self.browserDedupKey(for: p.url) == key }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            pendingReloadTabId = existing.id
            return
        }
        let item = SidebarItem.web(.init(
            id: UUID(),
            url: url,
            title: "",
            faviconURL: cachedFavicon(forSite: url)
        ))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    /// Loose URL identity for "is this already open in a tab". Drops scheme,
    /// leading `www.`, trailing slash and fragment so a click on
    /// `clawix.com` matches a tab whose live URL is the post-redirect
    /// `https://www.clawix.com/`.
    private static func browserDedupKey(for url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        var path = url.path
        if path.isEmpty { path = "/" }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let query = url.query.map { "?" + $0 } ?? ""
        return host + path + query
    }

    /// Hides the right column for the active chat without losing its
    /// items, so reopening from the toggle restores whatever was there.
    func closeBrowserPanel() {
        var s = currentSidebar
        s.isOpen = false
        currentSidebar = s
    }

    /// Open an absolute file path in the active chat's sidebar. Used by
    /// `ChangedFileCard`'s primary "Open" tap so the user can preview the
    /// edited file in-app instead of bouncing out to an external editor.
    /// Re-activates an existing file tab for the same path instead of
    /// duplicating it.
    func openFileInSidebar(_ path: String) {
        guard currentChatId != nil else { return }
        var s = currentSidebar
        if let existing = s.items.first(where: {
            if case .file(let p) = $0 { return p.path == path }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            return
        }
        let item = SidebarItem.file(.init(id: UUID(), path: path))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    @discardableResult
    func newBrowserTab(url: URL = URL(string: "https://www.google.com")!) -> SidebarItem.WebPayload? {
        guard currentChatId != nil else { return nil }
        var s = currentSidebar
        let payload = SidebarItem.WebPayload(
            id: UUID(),
            url: url,
            title: "",
            faviconURL: cachedFavicon(forSite: url)
        )
        s.items.append(.web(payload))
        s.activeItemId = payload.id
        s.isOpen = true
        currentSidebar = s
        return payload
    }

    /// Remove an item (web or file) from the active chat's sidebar. If
    /// the closed tab was the active one, focus snaps to its neighbour.
    /// Closing the last item collapses the panel so the column animates
    /// away instead of leaving a chrome with no body.
    func closeSidebarItem(_ id: UUID) {
        var s = currentSidebar
        guard let idx = s.items.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = s.activeItemId == id
        s.items.remove(at: idx)
        browserPageBackgroundColors.removeValue(forKey: id)
        if wasActive && !s.items.isEmpty {
            let next = min(idx, s.items.count - 1)
            s.activeItemId = s.items[next].id
        }
        if s.items.isEmpty {
            s.activeItemId = nil
            s.isOpen = false
        }
        currentSidebar = s
    }

    /// Update the live web-tab fields (URL on navigation, title, favicon).
    /// The web view callbacks fire even when the user is on another chat,
    /// so the search scans every chat's sidebar instead of only the
    /// active one.
    func updateBrowserTab(
        _ id: UUID,
        url: URL? = nil,
        title: String? = nil,
        faviconURL: URL? = nil
    ) {
        for chatId in chatSidebars.keys {
            guard var s = chatSidebars[chatId],
                  let idx = s.items.firstIndex(where: { $0.id == id }),
                  case .web(var payload) = s.items[idx]
            else { continue }
            if let url { payload.url = url }
            if let title { payload.title = title }
            if let faviconURL {
                payload.faviconURL = faviconURL
                recordHostFavicon(faviconURL, for: payload.url)
            }
            s.items[idx] = .web(payload)
            chatSidebars[chatId] = s
            persistChatSidebars()
            return
        }
    }

    /// Drop the chat's sidebar entry (used when a chat is removed
    /// entirely; archiving keeps the entry so it comes back on
    /// unarchive).
    func discardSidebar(forChatId id: UUID) {
        guard chatSidebars[id] != nil else { return }
        chatSidebars.removeValue(forKey: id)
        persistChatSidebars()
    }

    private func loadChatSidebars() {
        let defaults = AppState.sidebarDefaults
        if let data = defaults.data(forKey: AppState.chatSidebarsKey),
           let saved = try? JSONDecoder().decode([String: ChatSidebarState].self, from: data) {
            var rebuilt: [UUID: ChatSidebarState] = [:]
            for (key, value) in saved {
                guard let id = UUID(uuidString: key) else { continue }
                rebuilt[id] = value
                for item in value.items {
                    if case .web(let p) = item, let favicon = p.faviconURL {
                        FaviconCache.shared.prefetch(favicon)
                    }
                }
            }
            chatSidebars = rebuilt
        }
        // Drop legacy global keys from earlier versions where browser tabs
        // were app-wide instead of per-chat. Without an owning chat there
        // is nowhere to migrate them to, so the cleanest path is to wipe
        // the keys and let the user reopen what they need.
        if defaults.object(forKey: AppState.legacyBrowserStateKey) != nil {
            defaults.removeObject(forKey: AppState.legacyBrowserStateKey)
        }
        if defaults.object(forKey: AppState.legacyBrowserActiveKey) != nil {
            defaults.removeObject(forKey: AppState.legacyBrowserActiveKey)
        }
    }

    private func persistChatSidebars() {
        let payload = Dictionary(uniqueKeysWithValues:
            chatSidebars.map { ($0.key.uuidString, $0.value) }
        )
        let defaults = AppState.sidebarDefaults
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: AppState.chatSidebarsKey)
        }
    }

    /// Returns the best known favicon URL for `siteURL`'s host, or nil
    /// when the user has never visited it. New tabs use this so the
    /// pill renders the real favicon on the first frame instead of the
    /// monogram while WKWebView spins up.
    func cachedFavicon(forSite siteURL: URL) -> URL? {
        guard let key = AppState.hostKey(siteURL) else { return nil }
        return hostFavicons[key]
    }

    /// Records the favicon discovered for the given site URL into the
    /// global host store, preferring real page-declared icons over the
    /// Google s2 fallback when both have been seen for the same host.
    private func recordHostFavicon(_ favicon: URL, for siteURL: URL) {
        guard let key = AppState.hostKey(siteURL) else { return }
        if let existing = hostFavicons[key],
           !AppState.isGoogleS2Favicon(existing),
           AppState.isGoogleS2Favicon(favicon) {
            return
        }
        if hostFavicons[key] == favicon { return }
        hostFavicons[key] = favicon
        persistHostFavicons()
    }

    private func loadHostFavicons() {
        let defaults = AppState.sidebarDefaults
        guard let data = defaults.data(forKey: AppState.hostFaviconsKey),
              let saved = try? JSONDecoder().decode([String: URL].self, from: data)
        else { return }
        hostFavicons = saved
        for url in saved.values {
            FaviconCache.shared.prefetch(url, priority: .userInitiated)
        }
    }

    private func persistHostFavicons() {
        let defaults = AppState.sidebarDefaults
        if let data = try? JSONEncoder().encode(hostFavicons) {
            defaults.set(data, forKey: AppState.hostFaviconsKey)
        }
    }

    private static func hostKey(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func isGoogleS2Favicon(_ url: URL) -> Bool {
        url.host == "www.google.com" && url.path == "/s2/favicons"
    }
}

// MARK: - Link metadata (lazy <title> resolution for the trailing card)

/// Lightweight async cache that resolves the HTML `<title>` for URLs the
/// chat wants to surface in the trailing "Website" card. It prefers the page
/// title there ("Memory" instead of "localhost:5299"). Falls back to
/// the URL host whenever the fetch fails or the document has no title.
@MainActor
final class LinkMetadataStore: ObservableObject {
    @Published private(set) var titles: [URL: String] = [:]
    private var inFlight: Set<URL> = []

    func title(for url: URL) -> String? {
        titles[url]
    }

    func ensureTitle(for url: URL) {
        if titles[url] != nil || inFlight.contains(url) { return }
        inFlight.insert(url)
        Task { [weak self] in
            let resolved = await Self.fetchTitle(url)
            await MainActor.run {
                guard let self else { return }
                self.titles[url] = resolved ?? Self.fallback(for: url)
                self.inFlight.remove(url)
            }
        }
    }

    static func fallback(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return url.absoluteString
    }

    private static func fetchTitle(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("Mozilla/5.0 (Macintosh) Clawix", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return parseTitle(from: html)
    }

    /// Tiny regex-free `<title>` extractor: tolerant of attributes on the
    /// open tag and of mixed casing. Returns nil when the document has no
    /// usable title.
    static func parseTitle(from html: String) -> String? {
        guard let openRange = html.range(of: "<title", options: .caseInsensitive),
              let openEnd = html[openRange.upperBound...].range(of: ">"),
              let closeRange = html[openEnd.upperBound...].range(of: "</title>", options: .caseInsensitive)
        else { return nil }
        let raw = html[openEnd.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}
