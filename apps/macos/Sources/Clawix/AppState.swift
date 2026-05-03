import SwiftUI
import Combine

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

/// What the right-hand panel is currently showing. Selected by the
/// "+" menu in the right sidebar chrome (RightSidebarAddMenu).
enum RightSidebarContent: Equatable {
    case empty
    case browser
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

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        reasoningText: String = "",
        streamingFinished: Bool = true,
        isError: Bool = false,
        timestamp: Date = Date(),
        workSummary: WorkSummary? = nil,
        timeline: [AssistantTimelineEntry] = []
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
    }

    enum MessageRole { case user, assistant }
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
/// entry or should each get their own row. Only `command` (and, for
/// future-proofing, `fileChange`) merge across calls; MCP/dynamic/image
/// tools always open a fresh group so "Se han usado Node Repl" never gets
/// folded into "Se han modificado 3 archivos".
enum TimelineFamily {
    case command, fileChange, other

    static func from(_ kind: WorkItemKind) -> TimelineFamily {
        switch kind {
        case .command:    return .command
        case .fileChange: return .fileChange
        default:          return .other
        }
    }

    func matches(_ kind: WorkItemKind) -> Bool {
        switch (self, kind) {
        case (.command, .command):       return true
        case (.fileChange, .fileChange): return true
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

struct BrowserTab: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var title: String
    var faviconURL: URL?

    init(id: UUID = UUID(), url: URL, title: String = "", faviconURL: URL? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconURL = faviconURL
    }
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
    /// Composer text + staged attachments + focus token live here so
    /// typing only fires `objectWillChange` on this child object,
    /// leaving AppState's other observers untouched.
    let composer = ComposerState()
    @Published var pinnedItems: [PinnedItem] = []
    @Published var isLeftSidebarOpen: Bool = true
    @Published var isRightSidebarOpen: Bool = false
    @Published var isCommandPaletteOpen: Bool = false
    @Published var rightSidebarContent: RightSidebarContent = .empty
    @Published var browserTabs: [BrowserTab] = []
    @Published var activeBrowserTabId: UUID?
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

    private let metadataStore = AppMetadataStore()
    private var metadata: AppMetadata = .empty
    private var backendState: BackendState = .empty

    /// Resolves session ids to thread names by aggregating the backend's
    /// session index and our own overrides JSONL (titles generated by
    /// TitleGenerator). User renames done from inside this app live in
    /// `metadata.chatTitleByThread` and are layered on top.
    private let titleStore = SessionTitleStore()
    /// Available only when ClawixBinary.resolve() returned a path. If
    /// nil, automatic title generation is silently disabled and
    /// historic sessions without an entry in titleStore keep their
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

        self.metadata = metadataStore.load()

        backendState = BackendStateReader.read()
        loadMockData()
        if let fixtureThreads = AgentThreadStore.fixtureThreads() {
            applyThreads(fixtureThreads)
        } else {
            applyThreads([])
        }
        loadBrowserState()
        applyLaunchRoute()

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
            }
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
                name: titleStore.title(for: $0.id),
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
            let active = try await clawix.listThreads(archived: false, limit: 160, useStateDbOnly: true)
            applyThreads(active)
        } catch {
            appendRuntimeStatusError("No se pudo leer el índice real del runtime: \(error)")
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
        var result = backendState.workspaceRoots
        var seen = Set(result.map { $0.path })
        for project in metadata.localProjects + metadata.projects {
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

    private func applyThreads(_ threads: [AgentThreadSummary]) {
        backendState = BackendStateReader.read()
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = metadata.hasLocalPins ? metadata.pinnedThreadIds : backendState.pinnedThreadIds
        let pinnedSet = Set(pinIds)

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
    }

    /// Like `applyThreads` but additive: refreshes existing chats from the
    /// new payload and appends previously-unknown ones, instead of
    /// replacing the whole list. Used by per-project lazy loads so they
    /// don't wipe chats from other projects already in memory.
    private func mergeThreads(_ threads: [AgentThreadSummary]) {
        backendState = BackendStateReader.read()
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = metadata.hasLocalPins ? metadata.pinnedThreadIds : backendState.pinnedThreadIds
        let pinnedSet = Set(pinIds)

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
    }

    private func chatFromThread(_ thread: AgentThreadSummary,
                                old: Chat?,
                                projectByPath: [String: Project],
                                pinnedSet: Set<String>) -> Chat {
        let rootPath = rootPath(for: thread, projectByPath: projectByPath)
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
            isArchived: thread.archived,
            isPinned: !thread.archived && pinnedSet.contains(thread.id),
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: thread.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles
        )
    }

    private func rootPath(for thread: AgentThreadSummary, projectByPath: [String: Project]) -> String? {
        if metadata.projectlessThreadIds.contains(thread.id) {
            return nil
        }
        if let local = metadata.chatProjectPathByThread[thread.id], projectByPath[local] != nil {
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
            searchQuery = "autenticación"
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

    // MARK: - ClawixService callbacks

    func attachThreadId(_ threadId: String, to chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].clawixThreadId = threadId
        chats[idx].historyHydrated = true
        persistMetadata()
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
        if let lastEntry = timeline.last,
           case .reasoning(let entryId, let existing) = lastEntry {
            chats[idx].messages[last].timeline[timeline.count - 1] =
                .reasoning(id: entryId, text: existing + delta)
        } else {
            chats[idx].messages[last].timeline.append(
                .reasoning(id: UUID(), text: delta)
            )
        }
    }

    func markAssistantCompleted(chatId: UUID, finalText: String?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        if let text = finalText, !text.isEmpty {
            chats[idx].messages[last].content = text
        }
        chats[idx].messages[last].streamingFinished = true
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

    /// Resolve the visible title for a session id, layering sources in
    /// priority order: user rename in this app > titleStore
    /// (runtime + generated overrides) > truncated first message >
    /// localized fallback placeholder.
    private func resolveTitle(forSessionId id: String, firstMessage: String) -> String {
        if let manual = metadata.chatTitleByThread[id]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return manual
        }
        if let stored = titleStore.title(for: id) {
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

        guard let clawix, case .ready = clawix.status else {
            appendErrorBubble(chatId: chatId, message: "Archiving requires the runtime to be available.")
            return
        }
        markThreadArchived(threadId: threadId, archived: true)
        Task { @MainActor in
            do {
                try await clawix.archiveThread(threadId: threadId)
            } catch {
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

        guard let clawix, case .ready = clawix.status else {
            // Runtime not available: roll back so a runtime-backed chat is
            // never silently surfaced into the active list without the
            // backend agreeing.
            moved.isArchived = true
            archivedChats.insert(moved, at: min(idx, archivedChats.count))
            return
        }

        if !chats.contains(where: { $0.clawixThreadId == threadId }) {
            chats.insert(moved, at: 0)
        }
        Task { @MainActor in
            do {
                try await clawix.unarchiveThread(threadId: threadId)
                await self.loadThreadsFromRuntime()
            } catch {
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
        } else {
            pinnedOrder.removeAll { $0 == chatId }
        }
        metadata.hasLocalPins = true
        persistMetadata()
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
        metadata.hasLocalPins = true
        persistMetadata()
    }

    // MARK: - Project assignment

    func assignChat(chatId: UUID, toProject projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        chats = copy
        updateProjectOverride(for: copy[idx])
        persistMetadata()
    }

    /// Drag-and-drop helper: drop a chat onto a project. Reassigns it and
    /// unpins it so it visibly leaves the pinned section and lands inside
    /// that project's body. Pass `nil` to drop into the projectless bucket.
    func moveChatToProject(chatId: UUID, projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        if copy[idx].isPinned {
            copy[idx].isPinned = false
            pinnedOrder.removeAll { $0 == chatId }
        }
        chats = copy
        updateProjectOverride(for: copy[idx])
        persistMetadata()
    }

    private func updateProjectOverride(for chat: Chat) {
        guard let threadId = chat.clawixThreadId else { return }
        if let projectId = chat.projectId,
           let project = projects.first(where: { $0.id == projectId }) {
            metadata.chatProjectPathByThread[threadId] = project.path
            metadata.projectlessThreadIds.removeAll { $0 == threadId }
        } else {
            metadata.chatProjectPathByThread.removeValue(forKey: threadId)
            if !metadata.projectlessThreadIds.contains(threadId) {
                metadata.projectlessThreadIds.append(threadId)
            }
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
            metadata.localProjects.removeAll { $0.path == project.path }
            metadata.localProjects.append(project)
        }
        persistMetadata()
        return project
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        if selectedProject?.id == project.id { selectedProject = project }
        if let localIdx = metadata.localProjects.firstIndex(where: { $0.id == project.id || $0.path == project.path }) {
            metadata.localProjects[localIdx] = project
        }
        persistMetadata()
    }

    /// Removes a project. Chats previously assigned to it become projectless.
    func deleteProject(_ projectId: UUID) {
        projects.removeAll { $0.id == projectId }
        for idx in chats.indices where chats[idx].projectId == projectId {
            chats[idx].projectId = nil
            updateProjectOverride(for: chats[idx])
        }
        if selectedProject?.id == projectId { selectedProject = nil }
        metadata.localProjects.removeAll { $0.id == projectId }
        persistMetadata()
    }

    func renameProject(id: UUID, newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        if selectedProject?.id == id { selectedProject = projects[idx] }
        if let localIdx = metadata.localProjects.firstIndex(where: { $0.id == id }) {
            metadata.localProjects[localIdx].name = trimmed
        }
        persistMetadata()
    }

    /// Convenience: start a new chat scoped to a specific project.
    /// Selects the project in the composer pill and routes Home so the
    /// next message creates a chat associated with it.
    func startNewChat(in project: Project) {
        selectedProject = project
        currentRoute = .home
    }

    // MARK: - Persistence

    private func persistMetadata() {
        var pathAssignments = metadata.chatProjectPathByThread
        var projectless = Set(metadata.projectlessThreadIds)
        let chatsById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        for chat in chats {
            guard let threadId = chat.clawixThreadId else { continue }
            if let pid = chat.projectId,
               let project = projects.first(where: { $0.id == pid }) {
                pathAssignments[threadId] = project.path
                projectless.remove(threadId)
            } else if projectless.contains(threadId) {
                pathAssignments.removeValue(forKey: threadId)
            }
        }
        // Preserve the manual pinned ordering. Any pinned chat missing
        // from `pinnedOrder` (older state, defensive fallback) is appended
        // so we don't silently lose a pin.
        var seen = Set<UUID>()
        var pinned: [String] = []
        for chatId in pinnedOrder {
            guard !seen.contains(chatId),
                  let chat = chatsById[chatId],
                  chat.isPinned,
                  let threadId = chat.clawixThreadId else { continue }
            seen.insert(chatId)
            pinned.append(threadId)
        }
        for chat in chats where chat.isPinned && !seen.contains(chat.id) {
            if let threadId = chat.clawixThreadId { pinned.append(threadId) }
        }
        let liveThreadIds = Set(chats.compactMap { $0.clawixThreadId })
        pathAssignments = pathAssignments.filter { liveThreadIds.contains($0.key) }
        let localRoots = metadata.localProjects.filter { !$0.path.isEmpty }
        metadata = AppMetadata(
            version: 2,
            projects: localRoots,
            pinnedThreadIds: pinned,
            chatProjectPathByThread: pathAssignments,
            projectlessThreadIds: Array(projectless).filter { liveThreadIds.contains($0) },
            hasLocalPins: metadata.hasLocalPins,
            localProjects: localRoots
        )
        metadataStore.scheduleSave(metadata)
    }

    // MARK: - Browser

    private static let browserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private static let browserStateKey = "BrowserTabs"
    private static let browserActiveKey = "BrowserActiveTabId"

    private struct PersistedBrowserTab: Codable {
        let id: UUID
        let url: String
        let title: String
    }

    func openBrowser(initialURL: URL = URL(string: "https://www.google.com")!) {
        if browserTabs.isEmpty {
            let tab = BrowserTab(url: initialURL)
            browserTabs.append(tab)
            activeBrowserTabId = tab.id
        } else if activeBrowserTabId == nil {
            activeBrowserTabId = browserTabs.first?.id
        }
        rightSidebarContent = .browser
        isRightSidebarOpen = true
        persistBrowserState()
    }

    /// Tap target for any inline link inside chat content. Always opens the
    /// URL in the right-sidebar browser as a fresh tab and brings the panel
    /// forward, so the user never bounces out to the system browser.
    func openLinkInBrowser(_ url: URL) {
        let tab = BrowserTab(url: url)
        browserTabs.append(tab)
        activeBrowserTabId = tab.id
        rightSidebarContent = .browser
        isRightSidebarOpen = true
        persistBrowserState()
    }

    func closeBrowserPanel() {
        rightSidebarContent = .empty
    }

    @discardableResult
    func newBrowserTab(url: URL = URL(string: "https://www.google.com")!) -> BrowserTab {
        let tab = BrowserTab(url: url)
        browserTabs.append(tab)
        activeBrowserTabId = tab.id
        persistBrowserState()
        return tab
    }

    func closeBrowserTab(_ id: UUID) {
        guard let idx = browserTabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeBrowserTabId == id
        browserTabs.remove(at: idx)
        if wasActive {
            if browserTabs.isEmpty {
                activeBrowserTabId = nil
            } else {
                let next = min(idx, browserTabs.count - 1)
                activeBrowserTabId = browserTabs[next].id
            }
        }
        persistBrowserState()
    }

    func updateBrowserTab(
        _ id: UUID,
        url: URL? = nil,
        title: String? = nil,
        faviconURL: URL? = nil
    ) {
        guard let idx = browserTabs.firstIndex(where: { $0.id == id }) else { return }
        if let url { browserTabs[idx].url = url }
        if let title { browserTabs[idx].title = title }
        if let faviconURL { browserTabs[idx].faviconURL = faviconURL }
        persistBrowserState()
    }

    private func loadBrowserState() {
        let defaults = AppState.browserDefaults
        guard let data = defaults.data(forKey: AppState.browserStateKey),
              let saved = try? JSONDecoder().decode([PersistedBrowserTab].self, from: data)
        else { return }
        browserTabs = saved.compactMap { p in
            guard let url = URL(string: p.url) else { return nil }
            return BrowserTab(id: p.id, url: url, title: p.title)
        }
        if let activeRaw = defaults.string(forKey: AppState.browserActiveKey),
           let activeId = UUID(uuidString: activeRaw),
           browserTabs.contains(where: { $0.id == activeId }) {
            activeBrowserTabId = activeId
        } else {
            activeBrowserTabId = browserTabs.first?.id
        }
    }

    private func persistBrowserState() {
        let payload = browserTabs.map {
            PersistedBrowserTab(id: $0.id, url: $0.url.absoluteString, title: $0.title)
        }
        let defaults = AppState.browserDefaults
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: AppState.browserStateKey)
        }
        if let active = activeBrowserTabId {
            defaults.set(active.uuidString, forKey: AppState.browserActiveKey)
        } else {
            defaults.removeObject(forKey: AppState.browserActiveKey)
        }
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
