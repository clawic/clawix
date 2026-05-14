import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine


private let daemonBridgePort: UInt16 = 24080

private func rolloutChatMessages(from result: RolloutReader.ReadResult) -> [ChatMessage] {
    result.entries.map { e in
        ChatMessage(
            role: e.role == .user ? .user : .assistant,
            content: e.text,
            reasoningText: "",
            streamingFinished: true,
            timestamp: e.timestamp,
            workSummary: e.workSummary,
            timeline: e.timeline,
            attachments: e.attachments
        )
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var currentRoute: SidebarRoute = .home {
        didSet {
            let visibleRoute = currentRoute.visibleRoute(isVisible: FeatureFlags.shared.isVisible)
            if visibleRoute != currentRoute {
                currentRoute = visibleRoute
                return
            }
            clearUnreadIfChatRoute()
            if case let .chat(id) = currentRoute {
                daemonBridgeClient?.openSession(id)
            }
            persistLaunchRoute()
            // Scope only outlives the search popup itself; once the user
            // navigates anywhere else the chip gets cleared so the next
            // open lands on the unscoped pinned-chats view.
            if currentRoute != .search, searchScopedProjectId != nil {
                searchScopedProjectId = nil
            }
            // ⌘F binds to the chat that owned it; navigating away closes
            // the bar so the highlights don't bleed into the next view.
            if isFindBarOpen {
                if case .chat(let id) = currentRoute, id == findChatId {
                    // Same chat, keep the bar.
                } else {
                    closeFindBar()
                }
            }
        }
    }
    @Published var driveQuickUploadRequestID: UUID? = nil

    func navigate(to route: SidebarRoute) {
        let visibleRoute = route.visibleRoute(isVisible: FeatureFlags.shared.isVisible)
        guard currentRoute != visibleRoute else { return }
        currentRoute = visibleRoute
    }

    func enforceCurrentRouteVisibility() {
        navigate(to: currentRoute)
        if !FeatureFlags.shared.isVisible(.browserUsage) {
            removeWebTabsFromCurrentSidebar()
        }
        if !FeatureFlags.shared.isVisible(.remoteMesh), !selectedMeshTarget.isLocal {
            selectedMeshTarget = .local
        }
        if !FeatureFlags.shared.isVisible(.localModels), selectedModel.hasPrefix("ollama:") {
            selectedModel = "5.5"
        }
    }

    func requestDriveQuickUpload() {
        currentRoute = .driveAdmin
        driveQuickUploadRequestID = UUID()
    }

    func consumeDriveQuickUploadRequest(_ id: UUID) {
        guard driveQuickUploadRequestID == id else { return }
        driveQuickUploadRequestID = nil
    }

    @Published var searchQuery: String = ""
    @Published var searchResults: [String] = []
    @Published var searchResultRoutes: [String: SidebarRoute] = [:]
    /// In-page Find (⌘F) state. Operates on the chat that owns the
    /// current view; closes when the user navigates anywhere else.
    @Published var isFindBarOpen: Bool = false
    @Published var findQuery: String = ""
    @Published var isFinding: Bool = false
    @Published var findMatches: [FindMatch] = []
    @Published var currentFindIndex: Int = 0
    @Published var findChatId: UUID? = nil
    var findDebounce: DispatchWorkItem?
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
    let computerUseSampleChat: Chat
    @Published var plugins: [Plugin] = []
    @Published var automations: [Automation] = []
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    /// Manual ordering of projects for the sidebar's "Custom" sort mode.
    /// IDs not present here fall back to natural order from `projects`.
    /// Persisted via `ProjectOrdersRepository`.
    @Published var manualProjectOrder: [UUID] = []
    /// Currently selected agent for the next composer send. Defaults
    /// to the built-in Codex agent so legacy flows behave exactly like
    /// before. The composer dropdown writes this; `ChatView` reads it
    /// when minting a new chat. `AgentRuntimeChoice` below stays as
    /// the internal-resolved-runtime representation: the dropdown still
    /// derives runtime + model from the chosen agent so existing call
    /// sites that read `selectedAgentRuntime` keep working.
    @Published var selectedAgentId: String = Agent.defaultCodexId

    @Published var selectedAgentRuntime: AgentRuntimeChoice = .codex {
        didSet {
            guard oldValue != selectedAgentRuntime else { return }
            if selectedAgentRuntime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                selectedAgentRuntime = .codex
                return
            }
            if selectedAgentRuntime == .opencode, !selectedModel.contains("/") {
                selectedModel = AgentRuntimeChoice.persistedOpenCodeModel()
            } else if selectedAgentRuntime == .codex, selectedModel.contains("/") {
                selectedModel = "5.5"
            }
            AgentRuntimeChoice.persist(
                runtime: selectedAgentRuntime,
                openCodeModel: openCodeModelSelection
            )
        }
    }
    @Published var selectedModel: String = "5.5" {
        didSet {
            guard oldValue != selectedModel else { return }
            if selectedModel.contains("/"), !FeatureFlags.shared.isVisible(.openCode) {
                selectedModel = "5.5"
                return
            }
            if selectedAgentRuntime == .opencode {
                AgentRuntimeChoice.persist(
                    runtime: selectedAgentRuntime,
                    openCodeModel: openCodeModelSelection
                )
            }
        }
    }
    @Published var selectedIntelligence: IntelligenceLevel = .high
    @Published var selectedSpeed: SpeedLevel = .standard
    @Published var permissionMode: PermissionMode = .defaultPermissions {
        didSet {
            guard oldValue != permissionMode else { return }
            permissionMode.persist()
        }
    }
    @Published var personality: Personality = Personality.loadPersisted() {
        didSet {
            guard oldValue != personality else { return }
            personality.persist()
        }
    }
    /// Central library of Skills. Owns the catalog (built-ins + user
    /// + auto-imported), the active set per scope, and the registered
    /// sync targets. `nil` until `bootstrap()` wires it up so views can
    /// fall back to a local instance during preview-mode rendering.
    @Published var skillsStore: SkillsStore? = nil
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
    /// Remote Agent Mesh state (paired Macs, allowed workspaces,
    /// outbound jobs in flight). Refreshed lazily from the Settings
    /// page and the composer's "Run on" menu. Initialised in the
    /// init body (not as a default expression) so that calling a
    /// `@MainActor` initialiser does not defer past the rest of the
    /// stored-property setup the rest of init relies on.
    let meshStore: MeshStore
    /// Currently-selected destination for outbound prompts. `.local`
    /// runs through the regular Codex/daemon path. `.peer(nodeId)`
    /// routes through `/v1/mesh/remote-jobs` instead.
    @Published var selectedMeshTarget: MeshTarget = .local
    @Published var pinnedItems: [PinnedItem] = []
    @Published var isLeftSidebarOpen: Bool = AppState.sidebarDefaults.object(forKey: AppState.leftSidebarOpenKey) as? Bool ?? true
    @Published var isCommandPaletteOpen: Bool = false
    /// When non-nil, the global search popup is currently scoped to
    /// this project. The sidebar's per-project "View all" footer sets
    /// this and routes to `.search` so the same popup the user already
    /// likes (`SearchPopoverOverlay`) doubles as the project's "all
    /// chats" surface, with the project name shown as a removable
    /// filter chip.
    @Published var searchScopedProjectId: UUID? = nil
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
    /// Right-sidebar state used on every non-chat route (home / new
    /// conversation, search, plugins, automations, project, settings).
    /// Without this the toggle would no-op outside chats because
    /// `currentSidebar`'s setter has nowhere to attach the state.
    /// Persisted independently from per-chat sidebars so Home browser tabs
    /// survive relaunches without leaking into individual conversations.
    @Published var globalSidebar: ChatSidebarState = .empty
    /// Cross-tab favicon memory keyed by the registrable host. A tab freshly
    /// opened to a host visited before therefore renders its real favicon
    /// from the very first frame instead of cycling through the monogram and
    /// the Google s2 fallback while WKWebView re-extracts the page's
    /// `<link rel="icon">`. Persisted to UserDefaults under
    /// `HostFavicons` so it survives relaunches.
    @Published var hostFavicons: [String: URL] = [:]
    /// One-shot signal consumed by `BrowserView` to reload the active web
    /// view. Set when `openLinkInBrowser` is asked to open a URL already
    /// present in the strip and the user expects the existing tab to refresh
    /// instead of a duplicate opening. The view resets it back to nil after
    /// firing the reload.
    @Published var pendingReloadTabId: UUID?
    /// One-shot command the menu / keyboard shortcuts dispatch toward the
    /// active browser tab. `BrowserView` consumes this via `.onChange`,
    /// translates it to a controller method, and resets it to nil. We use a
    /// counter-tagged value so two consecutive same-action presses (e.g.
    /// Cmd+R twice) still fire as distinct events even if the enum case
    /// matches.
    @Published var pendingBrowserCommand: BrowserCommandRequest?
    /// Tagged signal for the URL field to grab focus and pre-fill with the
    /// full URL. Carries the active tab's id at dispatch time so a stale
    /// view in another tab doesn't hijack the focus.
    @Published var pendingFocusURLBar: BrowserFocusURLBarRequest?
    /// Per-tab "is the WKWebView currently navigating" mirror. The
    /// `BrowserTabController` keeps the source-of-truth as `@Published
    /// isLoading`, but the tab-strip pills live outside that observation
    /// chain, so we forward the bit here so each pill can show a spinner
    /// without needing a reference to the live controller.
    @Published var browserTabsLoading: Set<UUID> = []
    /// Per-web-tab live page background colour sampled from the bottom-left
    /// pixel of each browser webview. Keyed by the web item's id so the
    /// bottom-trailing rounded-corner cutout blends with whatever the
    /// active page is currently painting at that edge.
    @Published var browserPageBackgroundColors: [UUID: Color] = [:]
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
    /// Paths whose right-sidebar file viewer is rendering raw text with
    /// line numbers and basic syntax tinting instead of the parsed
    /// markdown body. Toggled from the breadcrumb's ellipsis menu via
    /// "Disable rich view" / "Enable rich view". In-memory only.
    @Published var richViewDisabledPaths: Set<String> = []
    /// Paths whose raw / plain file view (and only raw / plain) wraps
    /// long lines instead of showing a horizontal scroll. Same source
    /// of truth as the breadcrumb's "Enable word wrap" toggle.
    @Published var wordWrapEnabledPaths: Set<String> = []
    /// When true, fenced code blocks rendered in chat messages wrap
    /// long lines so everything is visible without a horizontal scroll.
    /// Toggled from the small wrap button next to each code block's
    /// copy action; the choice is global because the same code is often
    /// quoted across messages.
    @Published var chatCodeBlockWordWrap: Bool = true
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
    /// Diagnostic only: counts every `objectWillChange` fired by AppState so
    /// `RenderProbe` shows how chatty the publisher is. Each tick on this
    /// counter explains one downstream `SidebarView` invalidation.
    private var willChangeProbe: AnyCancellable?
    /// Bag of per-property publish probes. Each one ticks
    /// `AppState.<propname>` whenever that `@Published` property is set,
    /// so the render log can attribute every `AppState.willChange` to a
    /// specific source.
    private var publishProbes: [AnyCancellable] = []
    /// Most recent auto-reload time. Used to debounce the focus-driven
    /// reload to at most one trigger per second.
    var lastAutoReloadAt: Date?
    var focusReloadObserver: NSObjectProtocol?

    /// Local-network WS server that exposes this AppState to the iOS
    /// companion. Lazily created so the property doesn't take a
    /// reference to `self` before init finishes.
    private var bridgeServer: BridgeServer?
    private var daemonBridgeClient: DaemonBridgeClient?

    private let projectsRepo = ProjectsRepository()
    private let projectOrdersRepo = ProjectOrdersRepository()
    private let pinsRepo = PinsRepository()
    private let chatProjectsRepo = ChatProjectsRepository()
    private let metaRepo = MetaRepository()
    private let archivesRepo = ArchivesRepository()
    private let hiddenRootsRepo = HiddenRootsRepository()
    private var clawJSSessionsCanonicalActive = false
    /// Persistent cache of the sidebar's last applied state. Used to
    /// paint Pinned + chat list instantly at launch from local SQLite,
    /// before the runtime bootstraps and paginates the real thread list.
    /// Rewritten at the end of every applyThreads / mergeThreads.
    private let snapshotRepo = SnapshotRepository()
    private static let launchRouteKindKey = "LaunchRouteKind"
    private static let launchRouteChatUuidKey = "LaunchRouteChatUuid"
    private static let launchRouteThreadIdKey = "LaunchRouteThreadId"
    private let dummyModeActive: Bool = ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] == "1"
    /// True when the snapshot cache is active. Disabled while fixtures
    /// are driving the threads list (CLAWIX_THREAD_FIXTURE) so tests
    /// stay deterministic and the snapshot table never sees fixture
    /// data.
    private let snapshotEnabled: Bool = (AgentThreadStore.fixtureThreads() == nil
                                         && ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] != "1")
    private var backendState: BackendState = .empty

    /// Resolves user renames and generated titles persisted by Clawix.
    /// Runtime titles arrive from the ClawJS sessions adapter.
    private let titlesRepo = SessionTitlesRepository()
    /// Available only when ClawixBinary.resolve() returned a path. If
    /// nil, automatic title generation is silently disabled and
    /// historic sessions without an entry in titlesRepo keep their
    /// firstMessage fallback.
    private let titleGenerator: TitleGenerator?
    /// Chats already considered for post-turn title generation. Prevents
    /// re-firing on every turn of the same chat.
    private var titledChatIds: Set<UUID> = []

    /// Per-chat pagination state for the bridge's `loadOlderMessages`
    /// flow. Mirrors the iOS `BridgeStore` model: `oldestKnownId` is the
    /// cursor passed to the next request, `hasMore` is whether the
    /// daemon told us older history exists, `loadingOlder` guards
    /// against duplicate requests when the scroll-up sentinel
    /// re-materializes during fast scrolls. Reset whenever a fresh
    /// `messagesSnapshot` arrives for the chat.
    struct ChatPagination: Equatable {
        var oldestKnownId: String?
        var hasMore: Bool
        var loadingOlder: Bool
    }
    @Published var messagesPaginationByChat: [UUID: ChatPagination] = [:]

    /// Wire mirror of what the daemon (or the on-disk snapshot) last
    /// delivered, kept in lock-step with `chats` / `chats[i].messages`
    /// so we can persist the same `WireChat` / `WireMessage` shapes the
    /// iPhone uses without round-tripping through `Chat`/`ChatMessage`.
    /// Updated by every `applyDaemon*` and `appendDaemonMessage` path.
    /// Streaming partials are deliberately NOT mirrored here: the on-
    /// disk snapshot only holds settled messages, matching iOS.
    private var cachedWireChats: [WireChat] = []
    private var cachedWireMessagesByChat: [String: [WireMessage]] = [:]
    private var optimisticUserMessageIdsByChat: [UUID: Set<UUID>] = [:]
    /// Drives `SnapshotCache.save` after a quiet 500ms window. Each
    /// call cancels the previous in-flight task; streaming bursts and
    /// rapid chat updates collapse into a single write. The actual IO
    /// runs on a background priority Task so the main thread stays out
    /// of the file-system path entirely.
    private var persistTask: Task<Void, Never>?
    /// Per-chat git probes. `git status` can block on large repos or
    /// filesystem state, so chat navigation must never wait on it.
    private var gitInspectionTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        // Mesh store has to be wired before any other stored-property
        // assignment that uses `self`, because Swift's definite-init
        // analysis treats any read of `self.foo` as requiring every
        // stored property to already be in place.
        self.meshStore = MeshStore()
        // Initial language: read directly from persisted storage so the
        // didSet observer doesn't fire (and re-apply) during init.
        // ClawixApp.init() has already called AppLanguage.bootstrap()
        // before AppState is constructed, so AppLocale.current and the
        // AppleLanguages override are already in place.
        self.preferredLanguage = AppLanguage.loadPersisted()
        self.permissionMode = PermissionMode.loadPersisted()
        let persistedRuntime = AgentRuntimeChoice.loadPersisted()
        self.selectedAgentRuntime = persistedRuntime
        if persistedRuntime == .opencode {
            self.selectedModel = AgentRuntimeChoice.persistedOpenCodeModel()
        }
        self.skillsStore = SkillsStore()

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

        let computerUseStart = Date().addingTimeInterval(-90)
        let computerUseEnd = computerUseStart.addingTimeInterval(28)
        computerUseSampleChat = Chat(
            id: UUID(uuidString: "A11CE000-CAFE-4BAB-9B0E-C001A11CE001")!,
            title: "Inspect the current Mac app",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Inspect the screen and tell me what is open.",
                    timestamp: computerUseStart
                ),
                ChatMessage(
                    role: .assistant,
                    content: "The active window is visible and ready.",
                    timestamp: computerUseEnd,
                    workSummary: WorkSummary(
                        startedAt: computerUseStart,
                        endedAt: computerUseEnd,
                        items: [
                            WorkItem(
                                id: "tool-computer-use-1",
                                kind: .mcpTool(server: "computer_use", tool: "get_app_state"),
                                status: .completed
                            )
                        ]
                    ),
                    timeline: [
                        .tools(
                            id: UUID(uuidString: "C0A111CE-0000-4000-8000-C0A111CE0001")!,
                            items: [
                                WorkItem(
                                    id: "tool-computer-use-1",
                                    kind: .mcpTool(server: "computer_use", tool: "get_app_state"),
                                    status: .completed
                                )
                            ]
                        ),
                        .message(
                            id: UUID(uuidString: "C0A111CE-0000-4000-8000-C0A111CE0002")!,
                            text: "The active window is visible and ready."
                        )
                    ]
                )
            ],
            createdAt: computerUseStart
        )

        let resolvedBinary = ClawixBinary.resolve()
        self.clawixBinary = resolvedBinary
        self.clawix = resolvedBinary.map { ClawixService(binary: $0) }
        self.titleGenerator = nil

        manualProjectOrder = projectOrdersRepo.orderedIds()
        loadMockData()
        if let fixtureThreads = AgentThreadStore.fixtureThreads() {
            applyThreads(fixtureThreads)
        } else if dummyModeActive {
            chats = [computerUseSampleChat, browserSampleChat, sampleChat]
            currentRoute = .chat(computerUseSampleChat.id)
        } else {
            // First paint: build chats[] + pinnedOrder from the SQLite
            // snapshot of the last applied state. Falls back to an empty
            // list (existing behavior) when the snapshot is empty
            // (fresh install / post-resetLocalOverrides). The runtime
            // reconciles via applyThreads once clawix.bootstrap()
            // resolves, preserving Chat.id thanks to oldByThread.
            applySnapshotForFirstPaint()
            // Hydrate the most-recent transcripts from the on-disk
            // bridge snapshot (~/Library/Application Support/clawix/
            // snapshot.json) so a tap on a chat in the sidebar lands
            // immediately on the last-known body instead of an empty
            // ScrollView while the daemon's `messagesSnapshot` races
            // back. Idempotent / silent if the file is missing.
            loadCachedSnapshot()
            Task { @MainActor in
                await ClawJSAppStateCacheSync.refreshFromCanonicalStore()
                applySnapshotForFirstPaint()
            }
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
        // also rebuild when login / logout state flips. Coalesce bursts
        // into one tick per 150 ms: auth flips are user-visible but
        // never urgent, and an unthrottled forward fans out an
        // `objectWillChange` storm to every `@EnvironmentObject`
        // observer (sidebar, chat, composer, message rows, ...).
        auth.bootstrap()
        authObserver = auth.objectWillChange
            .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
        willChangeProbe = objectWillChange.sink { _ in
            RenderProbe.tick("AppState.willChange")
        }
        // Per-property publish probes. `$prop` for an `@Published var prop`
        // emits each time the value is set, so each tick on `AppState.<x>`
        // tells us what slice of state mutated immediately before a
        // matching `AppState.willChange` tick. The `dropFirst()` skips the
        // synchronous initial value emission.
        publishProbes = [
            $chats.dropFirst().sink { _ in RenderProbe.tick("AppState.chats") },
            $pinnedOrder.dropFirst().sink { _ in RenderProbe.tick("AppState.pinnedOrder") },
            $archivedChats.dropFirst().sink { _ in RenderProbe.tick("AppState.archivedChats") },
            $archivedLoading.dropFirst().sink { _ in RenderProbe.tick("AppState.archivedLoading") },
            $projects.dropFirst().sink { _ in RenderProbe.tick("AppState.projects") },
            $selectedProject.dropFirst().sink { _ in RenderProbe.tick("AppState.selectedProject") },
            $currentRoute.dropFirst().sink { _ in RenderProbe.tick("AppState.currentRoute") },
            $pendingPlanQuestions.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingPlanQuestions") },
            $clawixBackendStatus.dropFirst().sink { _ in RenderProbe.tick("AppState.clawixBackendStatus") },
            $rateLimits.dropFirst().sink { _ in RenderProbe.tick("AppState.rateLimits") },
            $rateLimitsByLimitId.dropFirst().sink { _ in RenderProbe.tick("AppState.rateLimitsByLimitId") },
            $hostFavicons.dropFirst().sink { _ in RenderProbe.tick("AppState.hostFavicons") },
            $browserPageBackgroundColors.dropFirst().sink { _ in RenderProbe.tick("AppState.browserPageBackgroundColors") },
            $chatSidebars.dropFirst().sink { _ in RenderProbe.tick("AppState.chatSidebars") },
            $pendingReloadTabId.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingReloadTabId") },
            $richViewDisabledPaths.dropFirst().sink { _ in RenderProbe.tick("AppState.richViewDisabledPaths") },
            $wordWrapEnabledPaths.dropFirst().sink { _ in RenderProbe.tick("AppState.wordWrapEnabledPaths") },
            $isLeftSidebarOpen.dropFirst().sink { open in
                AppState.sidebarDefaults.set(open, forKey: AppState.leftSidebarOpenKey)
                RenderProbe.tick("AppState.isLeftSidebarOpen")
            },
            $isRightSidebarMaximized.dropFirst().sink { _ in RenderProbe.tick("AppState.isRightSidebarMaximized") },
            $isCommandPaletteOpen.dropFirst().sink { _ in RenderProbe.tick("AppState.isCommandPaletteOpen") },
            $imagePreviewURL.dropFirst().sink { _ in RenderProbe.tick("AppState.imagePreviewURL") },
            $pendingRenameChat.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingRenameChat") },
            $pendingConfirmation.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingConfirmation") },
            $searchQuery.dropFirst().sink { _ in RenderProbe.tick("AppState.searchQuery") },
            $searchResults.dropFirst().sink { _ in RenderProbe.tick("AppState.searchResults") },
        ]

        // `isActive`, not `isEnabled`: SMAppService.status is bundle-
        // relative, so a daemon registered by the npm CLI doesn't show
        // up as enabled for the GUI's own SMAppService.agent. Treat any
        // reachable daemon on loopback as authoritative — otherwise the
        // GUI would race the CLI-installed daemon for Codex ownership.
        //
        // Fixture mode (showcase / dummy / E2E) overrides this: the
        // fixture is the canonical dataset and the daemon owns the
        // user's REAL Codex sessions, so connecting would let the
                // daemon's `sessionsSnapshot` overwrite the curated fixture chats
        // with live data and leak the user's real chats into a recording.
        let fixtureActive = AgentThreadStore.fixtureThreads() != nil || dummyModeActive
        let daemonBridgeEnabled = !fixtureActive && BackgroundBridgeService.shared.isActive
        clawix?.appState = self
        if let clawix,
           ProcessInfo.processInfo.environment["CLAWIX_DISABLE_BACKEND"] != "1",
           !daemonBridgeEnabled {
            Task { @MainActor in
                await clawix.bootstrap()
                self.clawixBackendStatus = clawix.status
                if let firstThreadId = self.chats.first(where: { $0.clawixThreadId != nil })?.clawixThreadId,
                   case .ready = clawix.status {
                    // No-op: threads are resumed lazily on user click.
                    _ = firstThreadId
                }
                await self.seedArchivesIfNeeded()
                // Refresh every project's chat list in the background
                // so opening any folder is instant. The first paint
                // already hydrated `chats[]` from the SQLite snapshot;
                // this just diff-merges any updates the daemon has
                // beyond what we persisted last session, animated.
                Task.detached(priority: .utility) { [weak self] in
                    await self?.preWarmAllProjects()
                }
            }
        }

        // Bridge to the iOS companion. Always-on so the pairing UI
        // can show a QR the iPhone scans without flipping any env
        // var. Disabled with CLAWIX_BRIDGE_DISABLE=1 for tests or
        // multi-instance debugging.
        if ProcessInfo.processInfo.environment["CLAWIX_BRIDGE_DISABLE"] != "1",
           !daemonBridgeEnabled {
            let server = BridgeServer(host: self, port: PairingService.shared.port)
            server.start()
            self.bridgeServer = server
            Self.publishPairingForDevMenu(PairingService.shared)
        } else if daemonBridgeEnabled {
            // Bridge state (bearer token, paired peers) lives in the
            // public `clawix.bridge` suite so the daemon (started with
            // CLAWIX_BRIDGE_DEFAULTS_SUITE=clawix.bridge) and a future
            // standalone CLI surface share the same bearer.
            let pairing = PairingService(defaults: UserDefaults(suiteName: "clawix.bridge") ?? .standard,
                                         port: daemonBridgePort)
            let client = DaemonBridgeClient(appState: self, pairing: pairing)
            daemonBridgeClient = client
            client.connect()
            Self.publishPairingForDevMenu(pairing)
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
        // AppIntents → AppState bridge (#13). Shortcuts.app posts
        // these notifications when the user invokes NewChat or
        // SendPrompt; we react by routing to home (so the composer
        // is in scope) and, for SendPrompt, prefilling the composer
        // and submitting.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("clawix.intent.newChat"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleNewChatIntent() }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("clawix.intent.sendPrompt"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let prompt = note.userInfo?["prompt"] as? String ?? ""
            Task { @MainActor in self?.handleSendPromptIntent(prompt) }
        }
        NotificationCenter.default.addObserver(
            forName: .clawixOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor in
                _ = self?.handleOpenURL(url)
            }
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

        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        selectedProject = nil

        pinnedItems = []
    }

    func loadThreadsFromRuntime() async {
        // When a thread fixture drives the sidebar (showcase / E2E /
        // demo recordings), the runtime is intentionally empty and a
        // runtime sweep here would call `applyThreads([])`, wiping the
        // curated dataset. The fixture is the source of truth for the
        // whole session.
        if AgentThreadStore.fixtureThreads() != nil { return }
        if await loadThreadsFromClawJSSessions() {
            return
        }
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let pageSize = 160
            var collected: [AgentThreadSummary] = []
            var seenIds = Set<String>()
            var cursor: String? = nil
            var page = 0

            // Pinned ids from the startup global-state snapshot. Used as the
            // stop condition for backfilling: keep paginating older threads
            // until every pinned id has been resolved.
            let pinnedTargets = Set(backendState.pinnedThreadIds)
            var resolvedPins = Set<String>()
            // Safety cap so a corrupt cursor or a stale pin id doesn't
            // turn this into an unbounded sweep. Adaptive: scales with
            // the number of pins so heavy users (dozens of pins
            // scattered across years of history) actually resolve them
            // all, with an absolute ceiling for the pathological case.
            let maxPages = min(200, max(60, pinnedTargets.count * 4))

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

    private func loadThreadsFromClawJSSessions() async -> Bool {
        let client = ClawJSSessionsClient.local()
        do {
            _ = try await client.probeHealth()
            _ = try? await client.importCodex()
            let canonicalProjects = try await client.listProjects(hidden: false, archived: false)
            let nextProjects = canonicalProjects.map { project in
                Project(
                    id: StableProjectID.uuid(for: project.path),
                    name: project.displayName,
                    path: project.path
                )
            }
            let sessions = try await client.listSessions(archived: false, sidebarVisible: true)
            clawJSSessionsCanonicalActive = true
            projects = nextProjects
            let threads = sessions.map { session in
                AgentThreadSummary(
                    id: session.id,
                    cwd: session.cwd ?? session.projectPath,
                    name: session.title,
                    preview: "",
                    path: nil,
                    createdAt: session.createdAt / 1000,
                    updatedAt: (session.lastMessageAt ?? session.createdAt) / 1000,
                    archived: session.archived
                )
            }
            applyThreads(threads)
            let archivedSessions = try await client.listSessions(archived: true)
            archivedChats = archivedSessions.map { session in
                chatFromThread(
                    AgentThreadSummary(
                        id: session.id,
                        cwd: session.cwd ?? session.projectPath,
                        name: session.title,
                        preview: "",
                        path: nil,
                        createdAt: session.createdAt / 1000,
                        updatedAt: (session.lastMessageAt ?? session.createdAt) / 1000,
                        archived: true
                    ),
                    old: archivedChats.first(where: { $0.clawixThreadId == session.id }),
                    projectByPath: Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) }),
                    pinnedSet: []
                )
            }
            archivedLoaded = true
            return true
        } catch {
            clawJSSessionsCanonicalActive = false
            return false
        }
    }

    /// Refreshes the chat list for a single project in the background.
    /// The sidebar's first paint already hydrated `chats[]` from the
    /// SQLite snapshot, so this is purely a diff-merge: any chats the
    /// runtime knows about but the snapshot didn't appear with the
    /// usual insertion animation, and existing rows update in place.
    /// Skipped when this project was refreshed less than
    /// `projectRefreshDebounce` ago so a flurry of accordion toggles
    /// or focus events doesn't hammer the runtime.
    func loadThreadsForProject(_ project: Project) async {
        guard let clawix, case .ready = clawix.status else { return }
        if let last = lastProjectRefreshAt[project.path],
           Date().timeIntervalSince(last) < Self.projectRefreshDebounce {
            return
        }
        lastProjectRefreshAt[project.path] = Date()
        do {
            let threads = try await clawix.listThreads(
                archived: false,
                cwd: project.path,
                limit: Self.snapshotPerProjectCap,
                useStateDbOnly: true
            )
            withAnimation(.easeOut(duration: 0.20)) {
                mergeThreads(threads)
            }
            persistProjectIndexFor(project)
        } catch {
            appendRuntimeStatusError("Could not load threads for project \(project.name): \(error)")
        }
    }

    /// Fetches a generous slice of a project's threads — enough to
    /// power the per-project "View all" popup — and merges them into
    /// `chats[]` so navigation lands on a fully populated chat. The
    /// sidebar accordion's per-project cap is intentionally tiny (10);
    /// this routine bypasses that cap and the debounce because the
    /// user explicitly asked to see everything in this folder.
    /// `useStateDbOnly` keeps the call latency down to a SQLite read.
    func loadAllThreadsForProject(_ project: Project) async {
        // Fixture / dummy mode: `chats[]` is already pre-loaded from
        // the seeded thread fixture, and the runtime backend that
        // would otherwise serve `listThreads` is ephemeral. Skipping
        // the round-trip avoids replacing the curated dataset with an
        // empty result on the first popup open.
        if AgentThreadStore.fixtureThreads() != nil { return }
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let threads = try await clawix.listThreads(
                archived: false,
                cwd: project.path,
                limit: Self.popupFullProjectFetchLimit,
                useStateDbOnly: true
            )
            withAnimation(.easeOut(duration: 0.20)) {
                mergeThreads(threads)
            }
            persistProjectIndexFor(project)
        } catch {
            appendRuntimeStatusError("Could not load threads for project \(project.name): \(error)")
        }
    }

    /// Refreshes every known project's chat list in parallel (capped
    /// at `preWarmConcurrency` simultaneous requests so the loopback
    /// JSON-RPC pipe doesn't saturate). Diff-merges into `chats[]`
    /// inside an animation so newly-discovered threads slide into the
    /// accordion instead of popping in.
    private func preWarmAllProjects() async {
        let snapshot = self.projects
        guard !snapshot.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = snapshot.makeIterator()
            var inFlight = 0
            while inFlight < Self.preWarmConcurrency, let next = iterator.next() {
                group.addTask { [weak self] in
                    await self?.refreshProjectIndex(next)
                }
                inFlight += 1
            }
            for await _ in group {
                if let next = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.refreshProjectIndex(next)
                    }
                }
            }
        }
    }

    /// Background-only project refresh used by `preWarmAllProjects`.
    /// Identical to `loadThreadsForProject` but silent on error: the
    /// pre-warm is best-effort, an occasional failure on one project
    /// shouldn't surface as a runtime status error. Runs on the main
    /// actor because `AppState` is `@MainActor`-isolated; the heavy
    /// network work happens inside the `await` and lands on a
    /// background executor without blocking the main thread.
    private func refreshProjectIndex(_ project: Project) async {
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let threads = try await clawix.listThreads(
                archived: false,
                cwd: project.path,
                limit: Self.snapshotPerProjectCap,
                useStateDbOnly: true
            )
            self.lastProjectRefreshAt[project.path] = Date()
            withAnimation(.easeOut(duration: 0.20)) {
                self.mergeThreads(threads)
            }
            self.persistProjectIndexFor(project)
        } catch {
            // Best-effort: the SQLite snapshot already hydrated this
            // project's chats. A failed pre-warm just means the user
            // opens the folder with slightly stale data.
        }
    }

    /// Persists the in-memory chats for a single project to
    /// `sidebar_snapshot_project`. Called after a per-project refresh
    /// so the next cold start hydrates this project from the freshest
    /// data we have seen, without rewriting every other project's rows.
    private func persistProjectIndexFor(_ project: Project) {
        guard snapshotEnabled else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let cap = Self.snapshotPerProjectCap
        var bucket: [SidebarSnapshotProjectRow] = []
        for chat in chats where !chat.isArchived
            && chat.projectId == project.id {
            guard let threadId = chat.clawixThreadId else { continue }
            bucket.append(SidebarSnapshotProjectRow(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectPath: project.path,
                updatedAt: Int64(chat.createdAt.timeIntervalSince1970),
                archived: 0,
                pinned: chat.isPinned ? 1 : 0,
                capturedAt: now
            ))
        }
        bucket.sort { $0.updatedAt > $1.updatedAt }
        let trimmed = Array(bucket.prefix(cap))
        let path = project.path
        let repo = snapshotRepo
        Task.detached(priority: .background) {
            repo.replaceProjectIndexFor(path: path, rows: trimmed)
        }
    }

    /// Tracks the last successful per-project refresh so accordion
    /// toggles or focus events don't fire a fresh RPC every time.
    private var lastProjectRefreshAt: [String: Date] = [:]
    /// Skip a per-project refresh if the previous one finished less
    /// than this many seconds ago. Tuned so a user toggling an
    /// accordion shut and back open feels instant without a redundant
    /// round-trip, while still picking up changes the daemon makes
    /// outside the bridge's notification path.
    private static let projectRefreshDebounce: TimeInterval = 2.0
    /// Maximum simultaneous per-project refreshes during pre-warm.
    /// Three is the empirical sweet spot: fewer leaves users with 30+
    /// projects waiting tens of seconds for the last one; more
    /// saturates the loopback RPC pipe.
    private static let preWarmConcurrency = 3

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
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
    }

    func showCodexRoot(path: String) {
        hiddenRootsRepo.show(path)
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
    }

    func hiddenCodexRoots() -> [String] {
        hiddenRootsRepo.allHidden()
    }

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
        manualProjectOrder = []
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        titlesRepo.reload()
        Task { @MainActor in
            await loadThreadsFromRuntime()
        }
    }

    /// First-paint pre-population of `chats[]` and `pinnedOrder` from
    /// the SQLite snapshots of the last applied state. Two layers:
    /// 1. `sidebar_snapshot` (top-N globally-recent) gives Pinned +
    ///    Chronological an immediate, high-fidelity first paint.
    /// 2. `sidebar_snapshot_project` adds every other chat we know
    ///    about per project, deduplicated against (1). The result is
    ///    that every accordion in the sidebar already has its rows in
    ///    memory before any RPC fires, so expanding a folder is
    ///    instant on cold start.
    /// No-op when both snapshots are empty (fresh install).
    private func applySnapshotForFirstPaint() {
        guard snapshotEnabled else { return }
        // Populate projects unconditionally so the sidebar's project
        // sections are present from the very first paint, even on a
        // fresh install where the snapshot is still empty.
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })

        var restored: [Chat] = []
        var seenThreadIds = Set<String>()

        // Drive `isPinned` from the live local repo (which already
        // mirrors Codex on boot) rather than the snapshot's `pinned`
        // column, so a pin added in Codex CLI shows up on first paint
        // even though the snapshot was written before that pin existed.
        let pinIds = pinsRepo.orderedThreadIds()
        let pinnedSet = Set(pinIds)

        let firstPaintLimit = 200
        let topRows = snapshotRepo.loadTop(limit: firstPaintLimit)
        for row in topRows {
            guard let id = UUID(uuidString: row.chatUuid) else { continue }
            let projectId = row.projectPath.flatMap { path in projectByPath[path]?.id }
            let archived = row.archived != 0
            restored.append(Chat(
                id: id,
                title: row.title,
                messages: [],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                clawixThreadId: row.threadId,
                rolloutPath: nil,
                historyHydrated: false,
                hasActiveTurn: false,
                projectId: projectId,
                isArchived: archived,
                isPinned: !archived && pinnedSet.contains(row.threadId),
                hasUnreadCompletion: false,
                cwd: row.cwd,
                hasGitRepo: false,
                branch: nil,
                availableBranches: [],
                uncommittedFiles: nil
            ))
            seenThreadIds.insert(row.threadId)
        }

        // Per-project rows. Skip anything already restored from the
        // global snapshot; the goal is to fill in chats that were
        // outside the top-N global cut but are still the freshest in
        // their project. `project_path` is non-optional in this table,
        // so we drop rows whose project is no longer known (the user
        // hid the workspace root or removed the local project).
        let projectRows = snapshotRepo.loadAllProjectIndexed()
        for row in projectRows where !seenThreadIds.contains(row.threadId) {
            guard let id = UUID(uuidString: row.chatUuid) else { continue }
            guard let project = projectByPath[row.projectPath] else { continue }
            let archived = row.archived != 0
            restored.append(Chat(
                id: id,
                title: row.title,
                messages: [],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                clawixThreadId: row.threadId,
                rolloutPath: nil,
                historyHydrated: false,
                hasActiveTurn: false,
                projectId: project.id,
                isArchived: archived,
                isPinned: !archived && pinnedSet.contains(row.threadId),
                hasUnreadCompletion: false,
                cwd: row.cwd,
                hasGitRepo: false,
                branch: nil,
                availableBranches: [],
                uncommittedFiles: nil
            ))
            seenThreadIds.insert(row.threadId)
        }

        guard !restored.isEmpty else { return }

        // Single sort by recency so Pinned and Chronological land in
        // the order the runtime would have produced.
        restored.sort { $0.createdAt > $1.createdAt }
        chats = restored

        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    /// Rewrite the SQLite snapshots from the current in-memory `chats`
    /// list. Called after every applyThreads / mergeThreads. Skipped
    /// when fixtures drive the threads list so tests stay deterministic.
    /// The actual writes go off-main via GRDB's serialized queue.
    ///
    /// Two snapshots:
    ///  - `sidebar_snapshot`: every chat (Pinned + Chrono first paint).
    ///  - `sidebar_snapshot_project`: capped per-project so the next
    ///    cold start can hydrate every accordion's contents before any
    ///    RPC fires. Cap aligns with the per-project `listThreads`
    ///    limit so the persisted set is never larger than what a
    ///    refresh would replace.
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

        // Per-project view: chats whose project is resolved, archived
        // ones dropped (sidebar accordions never list them). Group by
        // project_path, sort each bucket by recency, truncate to the
        // per-project cap.
        let perProjectCap = Self.snapshotPerProjectCap
        let globalCap = Self.snapshotGlobalCap
        var bucketed: [String: [SidebarSnapshotProjectRow]] = [:]
        for chat in chats where !chat.isArchived {
            guard let threadId = chat.clawixThreadId else { continue }
            guard
                let projectId = chat.projectId,
                let project = projectsById[projectId]
            else { continue }
            let row = SidebarSnapshotProjectRow(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectPath: project.path,
                updatedAt: Int64(chat.createdAt.timeIntervalSince1970),
                archived: 0,
                pinned: chat.isPinned ? 1 : 0,
                capturedAt: now
            )
            bucketed[project.path, default: []].append(row)
        }
        var perProjectRows: [SidebarSnapshotProjectRow] = []
        for var bucket in bucketed.values {
            bucket.sort { $0.updatedAt > $1.updatedAt }
            perProjectRows.append(contentsOf: bucket.prefix(perProjectCap))
        }
        if perProjectRows.count > globalCap {
            perProjectRows.sort { $0.updatedAt > $1.updatedAt }
            perProjectRows = Array(perProjectRows.prefix(globalCap))
        }

        let repo = snapshotRepo
        Task.detached(priority: .background) {
            repo.replaceAll(rows)
            repo.replaceProjectIndex(perProjectRows)
        }
    }

    /// Per-project cap when persisting `sidebar_snapshot_project` and
    /// the matching `listThreads` limit. The sidebar accordion only
    /// renders 5 chats by default and 10 after "Show more", so caching
    /// past 10 is wasted work — anything beyond that is reachable
    /// through the per-project "View all" popup, which fetches its own
    /// page on open. Keeps the in-memory `chats[]` list and the
    /// `sidebar_snapshot_project` table tight even for power users
    /// with thousands of conversations per workspace root.
    static let snapshotPerProjectCap = 10
    /// Hard global cap on `sidebar_snapshot_project` rows. Bounds disk
    /// use for power users with hundreds of workspace roots.
    private static let snapshotGlobalCap = 5000
    /// Page size for the per-project "View all" popup fetch. Generous
    /// enough that a typical workspace fully materialises on open
    /// (so the popup's local title filter sees every chat) without
    /// merging tens of thousands of rows for a power user — those
    /// surface through subsequent server-side searches.
    static let popupFullProjectFetchLimit = 500

    private func applyThreads(_ threads: [AgentThreadSummary]) {
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = pinsRepo.orderedThreadIds()
        let pinnedSet = Set(pinIds)

        reconcileArchivesFromRuntime(threads)

        let oldByThread = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })
        let oldArchivedByThread = Dictionary(uniqueKeysWithValues: archivedChats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })

        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }
        let selectedSnapshotChat: Chat?
        if case let .chat(id) = currentRoute,
           let selected = chat(byId: id),
           let threadId = selected.clawixThreadId,
           !sorted.contains(where: { $0.id.caseInsensitiveCompare(threadId) == .orderedSame }) {
            selectedSnapshotChat = selected
        } else {
            selectedSnapshotChat = nil
        }
        var nextChats: [Chat] = []
        var nextArchived: [Chat] = []
        nextChats.reserveCapacity(sorted.count)
        for thread in sorted {
            let old = oldByThread[thread.id] ?? oldArchivedByThread[thread.id]
            let chat = chatFromThread(thread,
                                      old: old,
                                      projectByPath: projectByPath,
                                      pinnedSet: pinnedSet)
            if chat.isArchived {
                nextArchived.append(chat)
            } else {
                nextChats.append(chat)
            }
        }
        if let selectedSnapshotChat {
            if selectedSnapshotChat.isArchived {
                if !nextArchived.contains(where: { $0.id == selectedSnapshotChat.id || $0.clawixThreadId == selectedSnapshotChat.clawixThreadId }) {
                    nextArchived.insert(selectedSnapshotChat, at: 0)
                }
            } else if !nextChats.contains(where: { $0.id == selectedSnapshotChat.id || $0.clawixThreadId == selectedSnapshotChat.clawixThreadId }) {
                nextChats.insert(selectedSnapshotChat, at: 0)
            }
        }
        chats = nextChats
        // Only overwrite archivedChats when the payload actually carries
        // archived rows (fixture / showcase mode). The runtime path calls
        // `applyThreads` with `archived: false` only, so an empty
        // `nextArchived` here means "no info", not "the archived list is
        // empty" — preserve whatever `loadArchivedChats` already cached.
        if !nextArchived.isEmpty {
            archivedChats = Array(nextArchived.prefix(Self.archivedSidebarLimit))
            archivedLoaded = true
        }

        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
        openFirstE2EChatIfRequested()
        writeE2EStateReportIfRequested()
        persistSidebarSnapshot()
    }

    /// Like `applyThreads` but additive: refreshes existing chats from the
    /// new payload and appends previously-unknown ones, instead of
    /// replacing the whole list. Used by per-project lazy loads so they
    /// don't wipe chats from other projects already in memory.
    private func mergeThreads(_ threads: [AgentThreadSummary]) {
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = pinsRepo.orderedThreadIds()
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
        rootPath(threadId: thread.id, cwd: thread.cwd, projectByPath: projectByPath)
    }

    /// Same project-resolution logic as the `AgentThreadSummary`
    /// variant but parameterised on the thread id + cwd directly so
    /// wire chats coming from the daemon (which carry both via the
    /// `threadId` field added to `WireChat`) can be reconciled
    /// without first being re-wrapped as an `AgentThreadSummary`.
    /// Returns nil when the
    /// thread id is missing (legacy daemons that don't emit it yet),
    /// preserving the previous "stay in flat list" behaviour.
    private func rootPath(threadId: String?, cwd: String?, projectByPath: [String: Project]) -> String? {
        if let threadId {
            if chatProjectsRepo.isProjectless(threadId) {
                return nil
            }
            if let local = chatProjectsRepo.overridePath(for: threadId), projectByPath[local] != nil {
                return local
            }
            if backendState.projectlessThreadIds.contains(threadId) {
                return nil
            }
            if let official = backendState.threadWorkspaceRootHints[threadId], projectByPath[official] != nil {
                return official
            }
        }
        guard let cwd else { return nil }
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
        if ProcessInfo.processInfo.environment["CLAWIX_E2E_HYDRATE_REPORT"] == "1" {
            for chatId in (chats + archivedChats).map(\.id) {
                hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
            }
        }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let payload: [String: Any] = [
            "projects": projects.map { ["name": $0.name, "path": $0.path] },
            "chats": chats.map { chat in
                [
                    "threadId": chat.clawixThreadId ?? "",
                    "title": chat.title,
                    "projectPath": chat.projectId.flatMap { projectsById[$0]?.path } ?? "",
                    "isPinned": chat.isPinned,
                    "isArchived": chat.isArchived,
                    "messages": chat.messages.map { message in
                        let renderedUser = message.role == .user
                            ? UserBubbleContent.parse(message.content, attachments: message.attachments)
                            : nil
                        return [
                            "role": message.role == .user ? "user" : "assistant",
                            "content": message.content,
                            "attachmentCount": message.attachments.count,
                            "renderedText": renderedUser?.text ?? message.content,
                            "renderedImageCount": renderedUser?.images.count ?? 0,
                            "workElapsedSeconds": message.workSummary.map { $0.elapsedSeconds(asOf: Date()) } ?? NSNull()
                        ] as [String: Any]
                    },
                    "toolRows": e2eToolRows(for: chat)
                ] as [String: Any]
            },
            "pinnedCount": chats.filter { $0.isPinned }.count,
            "archivedCount": chats.filter { $0.isArchived }.count,
            "featureVisibility": [
                "remoteMesh": FeatureFlags.shared.isVisible(.remoteMesh)
            ],
            "visibleSettingsCategories": SettingsCategory.visibleCases(isVisible: FeatureFlags.shared.isVisible).map(\.rawValue),
            "selectedMeshTarget": selectedMeshTarget.isLocal ? "local" : "peer"
        ]
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func e2eToolRows(for chat: Chat) -> [[String: String]] {
        chat.messages.flatMap { message in
            message.timeline.flatMap { entry -> [[String: String]] in
                guard case .tools(_, let items) = entry else { return [] }
                return ToolTimelinePresentation.aggregateRows(for: items).map {
                    ["id": $0.id, "icon": $0.icon, "text": $0.text]
                }
            }
        }
    }

    private func openFirstE2EChatIfRequested() {
        guard ProcessInfo.processInfo.environment["CLAWIX_E2E_OPEN_FIRST_CHAT"] == "1",
              let first = chats.first
        else { return }
        currentRoute = .chat(first.id)
        hydrateHistoryIfNeeded(chatId: first.id, blocking: true)
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
        case "chat-computer-use":
            chats = [computerUseSampleChat, sampleChat]
            currentRoute = .chat(computerUseSampleChat.id)
        case "browser":
            currentRoute = .home
            openBrowser()
        default:
            if !restorePersistedLaunchRoute() {
                currentRoute = .home
            }
        }
        if currentRoute == .secretsHome, !FeatureFlags.shared.isVisible(.secrets) {
            currentRoute = .home
        }
    }

    private func restorePersistedLaunchRoute() -> Bool {
        let defaults = Self.sidebarDefaults
        guard defaults.string(forKey: Self.launchRouteKindKey) == "chat" else {
            return false
        }

        let tokens = [
            defaults.string(forKey: Self.launchRouteThreadIdKey),
            defaults.string(forKey: Self.launchRouteChatUuidKey)
        ]
        for token in tokens.compactMap({ $0 }) {
            if openSessionDeepLink(token) {
                return true
            }
        }
        return false
    }

    private func persistLaunchRoute() {
        let defaults = Self.sidebarDefaults
        switch currentRoute {
        case .chat(let id):
            guard let chat = chat(byId: id) else { return }
            defaults.set("chat", forKey: Self.launchRouteKindKey)
            defaults.set(chat.id.uuidString, forKey: Self.launchRouteChatUuidKey)
            if let threadId = chat.clawixThreadId {
                defaults.set(threadId, forKey: Self.launchRouteThreadIdKey)
            } else {
                defaults.removeObject(forKey: Self.launchRouteThreadIdKey)
            }
        case .home:
            defaults.set("home", forKey: Self.launchRouteKindKey)
            defaults.removeObject(forKey: Self.launchRouteChatUuidKey)
            defaults.removeObject(forKey: Self.launchRouteThreadIdKey)
        default:
            break
        }
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

    /// Pending text deltas keyed by chat ID. The bridge can fire many
    /// `nAgentMsgDelta` notifications per main-runloop tick (the daemon
    /// emits per-token); mutating `chats` once per token publishes
    /// `@Published var chats` once per token, which invalidates every
    /// subscribed view body in the transcript per token. Buffering and
    /// applying once per tick collapses that to a single publish per
    /// frame, dropping invalidation work by ~10x without changing the
    /// observable streaming semantics (the user still sees per-word
    /// fades because the StreamCheckpoint schedule keeps its leaky-
    /// bucket spacing inside `applyAssistantTextDelta`).
    ///
    /// Only the assistant's text content is coalesced. Reasoning deltas
    /// interleave with tool-item events and have to land in arrival
    /// order against the timeline, so they keep their per-call publish.
    private var pendingAssistantTextBuffers: [UUID: String] = [:]
    private var assistantTextFlushScheduled = false

    func appendAssistantDelta(chatId: UUID, delta: String) {
        if delta.isEmpty { return }
        pendingAssistantTextBuffers[chatId, default: ""] += delta
        scheduleAssistantTextFlush()
    }

    /// Mark the most-recent assistant placeholder of a chat as finished.
    /// Used by the local-model (Ollama) chat path which doesn't go
    /// through the Codex turn-completion machinery.
    func markAssistantFinished(chatId: UUID, messageId: UUID) {
        flushPendingAssistantTextDeltas(chatId: chatId)
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].id == messageId
        else { return }
        chats[idx].messages[last].streamingFinished = true
    }

    /// Replace the in-flight assistant placeholder with an error message.
    func markAssistantFailed(chatId: UUID, messageId: UUID, error: String) {
        dropPendingAssistantText(chatId: chatId)
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].id == messageId
        else { return }
        let display = chats[idx].messages[last].content.isEmpty
            ? error
            : "\(chats[idx].messages[last].content)\n\n[error: \(error)]"
        chats[idx].messages[last].content = display
        chats[idx].messages[last].isError = true
        chats[idx].messages[last].streamingFinished = true
    }

    private func scheduleAssistantTextFlush() {
        guard !assistantTextFlushScheduled else { return }
        assistantTextFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingAssistantTextDeltas()
        }
    }

    /// Flush every chat's pending text. Called once per main-runloop
    /// tick by the scheduler. Safe to call directly when an external
    /// event needs the buffer drained synchronously (e.g. before
    /// finalizing a turn).
    func flushPendingAssistantTextDeltas() {
        assistantTextFlushScheduled = false
        guard !pendingAssistantTextBuffers.isEmpty else { return }
        let buffers = pendingAssistantTextBuffers
        pendingAssistantTextBuffers.removeAll(keepingCapacity: true)
        for (chatId, delta) in buffers where !delta.isEmpty {
            applyAssistantTextDelta(chatId: chatId, delta: delta)
        }
    }

    /// Drain a single chat's buffered deltas synchronously. Call this
    /// before any code path that reads or replaces
    /// `messages[last].content` on that chat (turn completion, daemon
    /// rehydrate, interrupt) so the buffer never lags behind the
    /// authoritative state.
    func flushPendingAssistantTextDeltas(chatId: UUID) {
        guard let delta = pendingAssistantTextBuffers.removeValue(forKey: chatId),
              !delta.isEmpty
        else { return }
        applyAssistantTextDelta(chatId: chatId, delta: delta)
    }

    /// Drop any pending text for a chat without applying it. Used when
    /// the daemon hands us the canonical content (`applyDaemonStreaming`,
    /// `appendDaemonMessage`) so we don't double-append after the
    /// authoritative replace.
    private func dropPendingAssistantText(chatId: UUID) {
        pendingAssistantTextBuffers.removeValue(forKey: chatId)
    }

    private func applyAssistantTextDelta(chatId: UUID, delta: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        let t0 = streamingPerfLogEnabled ? CFAbsoluteTimeGetCurrent() : 0
        chats[idx].messages[last].content += delta
        // Mirror into the chronological timeline so message text
        // interleaves with reasoning and tool groups in arrival order
        // instead of always rendering after them as a separate block.
        let timeline = chats[idx].messages[last].timeline
        if let lastEntry = timeline.last,
           case .message(let existingId, let existing) = lastEntry {
            chats[idx].messages[last].timeline[timeline.count - 1] =
                .message(id: existingId, text: existing + delta)
        } else {
            chats[idx].messages[last].timeline.append(
                .message(id: UUID(), text: delta)
            )
        }
        let cps = chats[idx].messages[last].streamCheckpoints
        let lastAt = cps.last?.addedAt ?? .distantPast
        let result = StreamingFade.ingest(
            delta: delta,
            pendingTail: chats[idx].messages[last].streamPendingTail,
            scheduledLength: cps.last?.prefixCount ?? 0,
            lastFadeStart: lastAt
        )
        if !result.newCheckpoints.isEmpty {
            chats[idx].messages[last].streamCheckpoints
                .append(contentsOf: result.newCheckpoints)
        }
        chats[idx].messages[last].streamPendingTail = result.pendingTail
        if streamingPerfLogEnabled {
            let t1 = CFAbsoluteTimeGetCurrent()
            let dt = lastDeltaArrivalTime > 0 ? (t0 - lastDeltaArrivalTime) * 1000 : 0
            lastDeltaArrivalTime = t0
            let queueDepth = max(0, lastAt.timeIntervalSinceNow * 1000)
            let totalLen = chats[idx].messages[last].content.count
            let totalCps = chats[idx].messages[last].streamCheckpoints.count
            let line = String(
                format: "delta dt=%.1fms size=%d totalLen=%d ingest=%.2fms +cps=%d totalCps=%d pendTail=%d queueAheadMs=%.1f",
                dt, delta.count, totalLen, (t1 - t0) * 1000,
                result.newCheckpoints.count, totalCps,
                result.pendingTail.count, queueDepth
            )
            streamingPerfLog.log("\(line, privacy: .public)")
        }
    }
    /// Wall-clock of the previous `applyAssistantTextDelta` call, used by
    /// the perf log to surface inter-arrival jitter.
    private var lastDeltaArrivalTime: Double = 0

    func appendReasoningDelta(chatId: UUID, delta: String) {
        // Drain any pending agent-message deltas FIRST so the text the
        // model emitted before this reasoning chunk lands in the timeline
        // ahead of the new `.reasoning` entry. Without this, buffered text
        // applied a runloop tick later would appear after reasoning that
        // arrived later in the stream.
        flushPendingAssistantTextDeltas(chatId: chatId)
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
        // Drain any text deltas still buffered for this chat before we
        // fold in the canonical body / mark the turn finished.
        flushPendingAssistantTextDeltas(chatId: chatId)
        guard let idx = chats.firstIndex(where: { $0.id == chatId }),
              let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant
        else { return }
        // Fresh turn closed cleanly. Drop any "Interrupted" pill that
        // a previous hydration may have raised.
        chats[idx].lastTurnInterrupted = false
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

}
