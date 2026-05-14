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
    @Published private(set) var findMatches: [FindMatch] = []
    @Published var currentFindIndex: Int = 0
    @Published private(set) var findChatId: UUID? = nil
    private var findDebounce: DispatchWorkItem?
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

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let deepLink = ClawixDeepLink.parse(url) else { return false }
        switch deepLink {
        case .chat(let token):
            return openSessionDeepLink(token)
        }
    }

    @discardableResult
    private func openSessionDeepLink(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let id = UUID(uuidString: trimmed),
           let chat = chat(byId: id) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        let folded = trimmed.lowercased()
        if let chat = (chats + archivedChats).first(where: { $0.clawixThreadId?.lowercased() == folded }) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        if let chat = restoreSnapshotChat(matching: trimmed) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        return false
    }

    private func restoreSnapshotChat(matching token: String) -> Chat? {
        let row = snapshotRepo.load(chatUuid: token) ?? snapshotRepo.load(threadId: token)
        guard let row, let id = UUID(uuidString: row.chatUuid) else { return nil }

        if let chat = chat(byId: id) { return chat }
        if let chat = (chats + archivedChats).first(where: { $0.clawixThreadId?.caseInsensitiveCompare(row.threadId) == .orderedSame }) {
            return chat
        }

        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let archived = row.archived != 0
        let chat = Chat(
            id: id,
            title: row.title,
            messages: [],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
            clawixThreadId: row.threadId,
            rolloutPath: nil,
            historyHydrated: false,
            hasActiveTurn: false,
            projectId: row.projectPath.flatMap { projectByPath[$0]?.id },
            isArchived: archived,
            isPinned: !archived && pinsRepo.isPinned(row.threadId),
            hasUnreadCompletion: false,
            cwd: row.cwd,
            hasGitRepo: false,
            branch: nil,
            availableBranches: [],
            uncommittedFiles: nil
        )

        if archived {
            archivedChats.insert(chat, at: 0)
        } else {
            chats.insert(chat, at: 0)
        }
        return chat
    }

    private func handleNewChatIntent() {
        currentRoute = .home
        composer.text = ""
    }

    private func handleSendPromptIntent(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentRoute = .home
        composer.text = trimmed
        // Defer the actual submit so SwiftUI has settled the route
        // change before sendMessage() reads it.
        DispatchQueue.main.async { [weak self] in
            self?.sendMessage()
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

    func performSearch(_ query: String) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchResultRoutes = [:]
            return
        }

        var results: [String] = []
        var routes: [String: SidebarRoute] = [:]
        var seen: Set<String> = []
        let searchableChats = (chats + archivedChats)
            .filter { !$0.isQuickAskTemporary && !$0.isSideChat }

        func append(_ text: String, chat: Chat) {
            guard results.count < 50 else { return }
            let unique = uniqueSearchResult(text, seen: &seen)
            results.append(unique)
            routes[unique] = .chat(chat.id)
        }

        for chat in searchableChats {
            if chat.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                append("\(chat.title) — title match", chat: chat)
            }
            guard results.count < 50 else { break }

            var messageMatches = 0
            for message in chat.messages where !message.content.isEmpty {
                guard let range = message.content.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else {
                    continue
                }
                let role = message.role == .user ? "User" : "Assistant"
                append("\(chat.title) — \(role): \(searchSnippet(in: message.content, around: range))", chat: chat)
                messageMatches += 1
                if messageMatches >= 3 || results.count >= 50 { break }
            }
            if results.count >= 50 { break }
        }

        searchResults = results
        searchResultRoutes = routes
    }

    private func uniqueSearchResult(_ text: String, seen: inout Set<String>) -> String {
        guard seen.contains(text) else {
            seen.insert(text)
            return text
        }
        var counter = 2
        while seen.contains("\(text) (\(counter))") {
            counter += 1
        }
        let unique = "\(text) (\(counter))"
        seen.insert(unique)
        return unique
    }

    private func searchSnippet(in content: String, around range: Range<String.Index>) -> String {
        let start = content.startIndex
        let end = content.endIndex
        let lower = content.index(range.lowerBound, offsetBy: -80, limitedBy: start) ?? start
        let upper = content.index(range.upperBound, offsetBy: 80, limitedBy: end) ?? end
        var snippet = String(content[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while snippet.contains("  ") {
            snippet = snippet.replacingOccurrences(of: "  ", with: " ")
        }
        if lower > start { snippet = "…" + snippet }
        if upper < end { snippet += "…" }
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Find (in-page)

    /// True when ⌘F has somewhere meaningful to land. Only a chat view
    /// can hold a find bar today; routes like `.home`, `.search`, or
    /// `.settings` do not have searchable transcripts so the menu item
    /// disables there.
    var canOpenFindBar: Bool {
        if case .chat = currentRoute { return true }
        return false
    }

    func openFindBar() {
        guard case .chat(let id) = currentRoute else { return }
        findChatId = id
        isFindBarOpen = true
    }

    func closeFindBar() {
        isFindBarOpen = false
        findQuery = ""
        findMatches = []
        currentFindIndex = 0
        findChatId = nil
        isFinding = false
        findDebounce?.cancel()
        findDebounce = nil
    }

    /// Updates `findQuery` and recomputes matches over the active chat
    /// transcript with a short debounce so each keystroke doesn't burn a
    /// full pass over the message list. The spinner stays on while the
    /// debounce is pending so the bar shows visible feedback even on
    /// instant searches.
    func updateFindQuery(_ q: String) {
        findQuery = q
        findDebounce?.cancel()
        guard !q.isEmpty else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        isFinding = true
        let work = DispatchWorkItem { [weak self] in
            self?.runFindNow()
        }
        findDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(260), execute: work)
    }

    private func runFindNow() {
        guard let chatId = findChatId, let chat = chat(byId: chatId) else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        let q = findQuery
        guard !q.isEmpty else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        var out: [FindMatch] = []
        for msg in chat.messages {
            let haystack = msg.content as NSString
            var searchRange = NSRange(location: 0, length: haystack.length)
            while searchRange.location < haystack.length {
                let r = haystack.range(of: q, options: [.caseInsensitive], range: searchRange)
                if r.location == NSNotFound { break }
                out.append(FindMatch(messageId: msg.id, range: r))
                let next = r.location + max(r.length, 1)
                if next >= haystack.length { break }
                searchRange = NSRange(location: next, length: haystack.length - next)
            }
        }
        findMatches = out
        currentFindIndex = out.isEmpty ? 0 : 0
        isFinding = false
    }

    func nextFindMatch() {
        guard !findMatches.isEmpty else { return }
        currentFindIndex = (currentFindIndex + 1) % findMatches.count
    }

    func prevFindMatch() {
        guard !findMatches.isEmpty else { return }
        currentFindIndex = (currentFindIndex - 1 + findMatches.count) % findMatches.count
    }

    var currentFindMatch: FindMatch? {
        guard !findMatches.isEmpty,
              currentFindIndex >= 0,
              currentFindIndex < findMatches.count else { return nil }
        return findMatches[currentFindIndex]
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
            chats[idx].lastMessageAt = userMsg.timestamp
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
                projectId: selectedProject?.id,
                agentId: selectedAgentId,
                lastMessageAt: userMsg.timestamp
            )
            chats.insert(newChat, at: 0)
            currentRoute = .chat(newChat.id)
            chatId = newChat.id
        }
        composer.text = ""
        composer.attachments = []

        if let localModel = localModelName(forSelected: selectedModel) {
            let history = chats.first(where: { $0.id == chatId })?.messages ?? []
            LocalModelChat.shared.send(
                chatId: chatId,
                model: localModel,
                history: history,
                appState: self
            )
            return
        }

        if !FeatureFlags.shared.isVisible(.remoteMesh), !selectedMeshTarget.isLocal {
            selectedMeshTarget = .local
        }

        if FeatureFlags.shared.isVisible(.remoteMesh),
           case .peer(let nodeId) = selectedMeshTarget,
           let peer = meshStore.peers.first(where: { $0.nodeId == nodeId }) {
            dispatchRemoteMeshJob(peer: peer, chatId: chatId, prompt: combined)
            return
        }

        if clawJSSessionsCanonicalActive {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            Task { @MainActor in
                if await self.sendMessageViaClawJSSessions(chatId: chatId, text: combined, attachments: attachments) {
                    return
                }
                if let daemonBridgeClient = self.daemonBridgeClient {
                    daemonBridgeClient.sendPrompt(chatId: chatId, text: combined, attachments: self.wireAttachments(from: attachments))
                } else if let clawix = self.clawix {
                    await clawix.sendUserMessage(chatId: chatId, text: combined)
                    self.clawixBackendStatus = clawix.status
                }
            }
            return
        }

        if let daemonBridgeClient {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: combined, attachments: wireAttachments(from: attachments))
        } else if selectedAgentRuntime == .opencode {
            appendAssistantSystemMessage(
                to: chatId,
                text: "OpenCode runs through the background bridge. Enable the bridge, restart it, then send again."
            )
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    private func sendMessageViaClawJSSessions(
        chatId: UUID,
        text: String,
        attachments: [ComposerAttachment]
    ) async -> Bool {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return false }
        let client = ClawJSSessionsClient.local()
        let sessionId = chats[idx].clawixThreadId ?? chatId.uuidString
        let projectPath = chats[idx].projectId.flatMap { projectId in
            projects.first(where: { $0.id == projectId })?.path
        }
        do {
            let response = try await client.startTurn(
                sessionId: sessionId,
                input: .init(
                    prompt: text,
                    projectId: nil,
                    projectPath: projectPath,
                    cwd: projectPath,
                    title: chats[idx].title,
                    attachments: attachments.map { attachment in
                        .object([
                            "id": .string(attachment.id.uuidString),
                            "path": .string(attachment.url.path),
                            "filename": .string(attachment.filename)
                        ])
                    },
                    audioRef: nil,
                    fakeReply: nil
                )
            )
            guard let currentIdx = chats.firstIndex(where: { $0.id == chatId }) else { return true }
            chats[currentIdx].clawixThreadId = response.session?.id ?? sessionId
            chats[currentIdx].hasActiveTurn = false
            if let assistant = response.assistantMessage, !assistant.contentText.isEmpty {
                let now = Date()
                let summary = WorkSummary(
                    startedAt: now,
                    endedAt: now,
                    items: [
                        WorkItem(
                            id: assistant.id,
                            kind: .dynamicTool(name: "Codex"),
                            status: assistant.streamingState == "complete" ? .completed : .failed
                        )
                    ]
                )
                chats[currentIdx].messages.append(ChatMessage(
                    role: .assistant,
                    content: assistant.contentText,
                    timestamp: now,
                    workSummary: summary,
                    timeline: [
                        .tools(id: UUID(), items: summary.items),
                        .message(id: UUID(), text: assistant.contentText)
                    ]
                ))
                chats[currentIdx].lastMessageAt = now
            }
            return true
        } catch {
            appendErrorBubble(chatId: chatId, message: "Could not send through ClawJS sessions: \(error.localizedDescription)")
            return false
        }
    }

    private func wireAttachments(from attachments: [ComposerAttachment]) -> [WireAttachment] {
        attachments.compactMap { attachment in
            guard attachment.isImage,
                  let data = try? Data(contentsOf: attachment.url)
            else { return nil }
            return WireAttachment(
                id: attachment.id.uuidString,
                kind: .image,
                mimeType: mimeType(forImageURL: attachment.url),
                filename: attachment.filename,
                dataBase64: data.base64EncodedString()
            )
        }
    }

    private func mimeType(forImageURL url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    /// Outbound mesh dispatch. Validates that a remote workspace has
    /// been configured for this peer (without one, the remote daemon
    /// would always reject the job with `workspaceDenied`), starts
    /// the job through `MeshStore`, and surfaces a synthetic system
    /// message in the chat so the user has feedback that "this turn
    /// is running on a different Mac". The actual streaming card
    /// renders against `meshStore.activeJobs[…]` from `ChatView`.
    private func dispatchRemoteMeshJob(peer: PeerRecord, chatId: UUID, prompt: String) {
        let workspace = meshStore.remoteWorkspace(for: peer.nodeId)
        guard !workspace.isEmpty else {
            appendAssistantSystemMessage(
                to: chatId,
                text: "No remote workspace set for \(peer.displayName). Open Settings → Hosts and add one before sending."
            )
            return
        }
        Task { @MainActor in
            let result = await meshStore.startRemoteJob(
                peer: peer,
                workspacePath: workspace,
                prompt: prompt,
                chatId: chatId
            )
            switch result {
            case .success(let job):
                appendAssistantSystemMessage(
                    to: chatId,
                    text: "Running on \(peer.displayName) · job \(job.id.prefix(8))…"
                )
            case .failure(let error):
                appendAssistantSystemMessage(
                    to: chatId,
                    text: "Could not start remote job: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Append a transient system note to a chat. Used by the mesh
    /// dispatch path so the user always sees something happen even
    /// when the assistant reply is going to land on a remote Mac, and
    /// by the OpenCode-bridge nudge path that already called this
    /// helper before the function existed.
    func appendAssistantSystemMessage(to chatId: UUID, text: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let note = ChatMessage(role: .assistant, content: text, streamingFinished: true, timestamp: Date())
        chats[idx].messages.append(note)
    }

    /// Returns the bare Ollama model name (e.g. `llama3.2:3b`) when the
    /// composer's currently-selected model points at a local runtime
    /// model. The composer encodes this with the `ollama:` prefix so the
    /// rest of the app can keep treating `selectedModel` as an opaque
    /// string. Returns nil for the GPT/Codex options.
    func localModelName(forSelected raw: String) -> String? {
        guard FeatureFlags.shared.isVisible(.localModels) else { return nil }
        let prefix = "ollama:"
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    var openCodeModelSelection: String {
        if selectedModel.contains("/") { return selectedModel }
        return AgentRuntimeChoice.persistedOpenCodeModel()
    }

    func enforceExperimentalRuntimeVisibility() {
        guard !FeatureFlags.shared.isVisible(.openCode) else { return }
        if selectedAgentRuntime == .opencode {
            selectedAgentRuntime = .codex
        }
        if selectedModel.contains("/") {
            selectedModel = "5.5"
        }
        if let selectedAgent = AgentStore.shared.agent(id: selectedAgentId),
           selectedAgent.runtime != .codex {
            selectedAgentId = Agent.defaultCodexId
        }
        if QuickAskController.shared.quickAskDefaultModel?.contains("/") == true {
            QuickAskController.shared.quickAskDefaultModel = nil
        }
    }

    /// Submit a prompt from the QuickAsk HUD. Mirrors the home-route
    /// branch of `sendMessage()` (same daemon vs in-process dispatch)
    /// but takes the prompt directly so the main composer state is not
    /// touched. When `chatId` is nil a fresh chat is created and inserted
    /// at the top of the sidebar; the resolved id is returned so
    /// QuickAskController can persist it across hotkey presses.
    ///
    /// [QUICKASK<->CHAT PARITY] This function and `sendMessage()` are
    /// SISTER entry points to the same daemon dispatch. `sendMessage()`
    /// implicitly runs `openSession` via `currentRoute.didSet` because it
    /// switches the main route to `.chat(id)`. QuickAsk does NOT touch
    /// `currentRoute` (it would yank the user out of the HUD), so this
    /// function MUST call `daemonBridgeClient.openSession(resolvedId)` itself
    /// before `sendPrompt`. Without it the daemon receives the prompt but
    /// the BridgeBus has no subscription for this chatId, so
    /// `messageStreaming` / `messageAppended` frames are filtered out and
    /// the HUD never sees the assistant reply. References:
    ///   - BridgeIntent.swift `.sendPrompt` case (no auto-subscribe)
    ///   - BridgeBus.subscribe (idempotent set insert)
    ///   - BridgeProtocol.swift comment on `.newChat` ("auto-subscribes")
    ///   - sister bubble: `QuickAskMessageBubble` in QuickAskView.swift
    @discardableResult
    func submitQuickAsk(
        chatId: UUID?,
        text: String,
        attachments: [QuickAskAttachment] = [],
        temporary: Bool = false
    ) -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty || !attachments.isEmpty,
                     "submitQuickAsk requires non-empty text or at least one attachment")

        // Same convention as `sendMessage()` for the main composer:
        // attachments enter the prompt as `@<absolute-path>` mentions
        // so the daemon can resolve them server-side (image attachments
        // become `localImage` items, file paths get read into context).
        // Selection / clipboard chips that carry their own preview text
        // ride as a leading "Selected text:" / "Clipboard:" block
        // because the source isn't a file the agent can re-read.
        let mentions = attachments.compactMap { att -> String? in
            switch att.kind {
            case .file, .drop, .paste, .screenshot, .camera:
                return "@\(att.url.path)"
            case .clipboard:
                // Clipboard chips fall into two shapes: file URLs
                // (mention path) and inline text (skip; surfaced as
                // a "Clipboard:" prelude below).
                return att.previewText == nil ? "@\(att.url.path)" : nil
            case .selection:
                // Selection chips carry the verbatim text the user
                // wanted included; surface it as a quoted block
                // before the prompt rather than a path mention.
                return nil
            }
        }
        let preludes = attachments.compactMap { att -> String? in
            switch att.kind {
            case .selection:
                guard let text = att.previewText else { return nil }
                return "Selected text:\n\(text)"
            case .clipboard:
                guard let text = att.previewText else { return nil }
                return "Clipboard:\n\(text)"
            default:
                return nil
            }
        }

        let combined: String = {
            var parts: [String] = []
            if !preludes.isEmpty { parts.append(preludes.joined(separator: "\n\n")) }
            if !mentions.isEmpty { parts.append(mentions.joined(separator: " ")) }
            if !trimmed.isEmpty { parts.append(trimmed) }
            return parts.joined(separator: "\n\n")
        }()

        let userMsg = ChatMessage(role: .user, content: combined, timestamp: Date())
        let resolvedId: UUID
        if let id = chatId, let idx = chats.firstIndex(where: { $0.id == id }) {
            chats[idx].messages.append(userMsg)
            chats[idx].lastTurnInterrupted = false
            chats[idx].lastMessageAt = userMsg.timestamp
            resolvedId = id
        } else {
            let titleSeed = trimmed.isEmpty
                ? (attachments.first?.filename ?? "Attachments")
                : trimmed
            let newChat = Chat(
                id: UUID(),
                title: String(titleSeed.prefix(40)),
                messages: [userMsg],
                createdAt: Date(),
                projectId: selectedProject?.id,
                isQuickAskTemporary: temporary,
                agentId: selectedAgentId,
                lastMessageAt: userMsg.timestamp
            )
            chats.insert(newChat, at: 0)
            resolvedId = newChat.id
        }

        if let daemonBridgeClient {
            // sendMessage() reaches openSession implicitly via the
            // currentRoute didSet; QuickAsk doesn't switch the route
            // (the HUD stays on top of whatever the user was doing),
            // so we have to subscribe this chat to the bridge bus
            // explicitly. openSession is idempotent (Set.insert) so
            // calling it on every submit is safe and also covers the
            // re-subscribe-after-reconnect case.
            trackOptimisticUserMessage(chatId: resolvedId, messageId: userMsg.id)
            daemonBridgeClient.openSession(resolvedId)
            daemonBridgeClient.sendPrompt(chatId: resolvedId, text: combined)
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: resolvedId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }

        return resolvedId
    }

    /// Entry point used by the bridge that exposes the desktop app to the
    /// iOS companion. Mirrors the user-message half of `sendMessage()`
    /// but takes the chat id, text and inline attachments as parameters
    /// rather than reading from the composer.
    ///
    /// `attachments` carries images the iPhone composer encoded inline.
    /// They are spooled to a chat-scoped temp dir and forwarded as
    /// `localImage` items either through `daemonBridgeClient` (which
    /// reships the wire `WireAttachment`s to `clawix-bridge`) or
    /// straight into the in-process `ClawixService`. Sending an
    /// attachment-only message (empty `text`) is supported so the
    /// composer can ship a photo with no caption.
    /// Wrapper used by the Apps surface SDK (`window.clawix.agent.sendMessage`)
    /// to inject a synthetic user message into the chat that originally
    /// owned the app. Funnels through `sendUserMessageFromBridge` so
    /// the optimistic-message + bridge-roundtrip plumbing is shared.
    @MainActor
    func dispatchAppMessage(_ text: String, toChatId chatId: UUID) {
        sendUserMessageFromBridge(chatId: chatId, text: text, attachments: [])
    }

    @MainActor
    func sendUserMessageFromBridge(
        chatId: UUID,
        text: String,
        attachments: [WireAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }

        let imageAttachments = attachments.filter { $0.kind == .image }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        let preview = bridgeUserPreview(
            text: trimmed,
            imageCount: imageAttachments.count,
            hasAudio: !audioAttachments.isEmpty
        )
        let userMsg = ChatMessage(role: .user, content: preview, timestamp: Date())
        chats[idx].messages.append(userMsg)
        // Sending a fresh prompt closes any earlier interrupted-turn
        // pill: the user has acknowledged the gap and is moving on.
        chats[idx].lastTurnInterrupted = false

        // Audio attachments are stored locally (so the chat history
        // can replay the clip later) and never shipped to the model:
        // Codex doesn't accept audio, the iPhone composer already
        // transcribed via the `transcribeAudio` frame, and we use that
        // transcript as the prompt text.
        if !audioAttachments.isEmpty {
            ingestAudioFromBridge(
                attachments: audioAttachments,
                chatId: chatId,
                messageId: userMsg.id,
                transcript: trimmed
            )
        }

        if let daemonBridgeClient {
            // The daemon spools the attachments itself and emits
            // `localImage` paths to Codex; we just forward the raw
            // wire payload over loopback.
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        } else if let clawix {
            let imagePaths = AttachmentSpooler.write(
                attachments: imageAttachments,
                scope: chatId.uuidString
            )
            Task { @MainActor in
                await clawix.sendUserMessage(
                    chatId: chatId,
                    text: trimmed,
                    imagePaths: imagePaths
                )
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    /// Persist audio attachments coming off the bridge into
    /// `AudioMessageStore` and patch the user message with the
    /// resulting `audioRef` once the bytes land. Runs detached so the
    /// optimistic message bubble shows immediately; the bubble's
    /// playable state lights up as soon as ingest finishes.
    private func ingestAudioFromBridge(
        attachments: [WireAttachment],
        chatId: UUID,
        messageId: UUID,
        transcript: String
    ) {
        guard let attachment = attachments.first else { return }
        guard let data = Data(base64Encoded: attachment.dataBase64) else { return }
        let mime = attachment.mimeType
        // The local in-process server doesn't track Codex thread ids by
        // chat id (that lives inside `clawix`). Use the chat UUID as a
        // stable thread anchor instead — the store only uses it to
        // group entries for hydrate-time matching, which we don't
        // exercise in the in-process path (no rollout rebuild here).
        let threadId = chatId.uuidString
        let chatIdString = chatId.uuidString
        let messageIdString = messageId.uuidString
        Task { [weak self] in
            do {
                let entry = try await AudioMessageStore.shared.ingest(
                    threadId: threadId,
                    chatId: chatIdString,
                    messageId: messageIdString,
                    audioData: data,
                    mimeType: mime,
                    transcript: transcript
                )
                await MainActor.run {
                    guard let self else { return }
                    guard let cIdx = self.chats.firstIndex(where: { $0.id == chatId }),
                          let mIdx = self.chats[cIdx].messages.firstIndex(where: { $0.id == messageId })
                    else { return }
                    self.chats[cIdx].messages[mIdx].audioRef = entry.wireRef
                }
                // Dual-write into the framework audio catalog so new
                // ingests stay queryable via `audioGetBytes / audioList`
                // alongside the legacy on-disk store. Best effort: the
                // legacy store is still the source of truth this release.
                if let client = await MainActor.run(body: { AudioCatalogBootstrap.shared.currentClient }) {
                    _ = try? await client.register(.init(
                        id: entry.id,
                        kind: "user_message",
                        appId: "clawix",
                        originActor: "user",
                        mimeType: entry.mimeType,
                        bytesBase64: data.base64EncodedString(),
                        durationMs: entry.durationMs,
                        threadId: entry.threadId,
                        linkedMessageId: entry.messageId,
                        transcript: transcript.isEmpty ? nil : .init(
                            text: transcript,
                            role: "transcription",
                            provider: "transcribeAudio"
                        )
                    ))
                }
            } catch {
                // Soft fail: the user message is still in the chat;
                // the bubble simply won't have a play button.
            }
        }
    }

    /// Render a short preview for the optimistic user bubble that the
    /// macOS chat list (and the iPhone companion via bridge echo) shows
    /// while the turn is still running. Mirrors the daemon's preview so
    /// attachment counts read consistently across surfaces.
    private func bridgeUserPreview(text: String, imageCount: Int, hasAudio: Bool = false) -> String {
        guard imageCount > 0 else {
            return hasAudio && text.isEmpty ? "[voice]" : text
        }
        let label = imageCount == 1 ? "[image]" : "[\(imageCount) images]"
        return text.isEmpty ? label : "\(label) \(text)"
    }

    /// Bridge entry point for "tap the New Chat FAB on the iPhone": the
    /// client pre-mints the UUID and ships the first prompt in one shot.
    /// We create a Chat with that exact id, append the user message, and
    /// kick the turn off through whichever runtime is active. Mirrors
    /// the home-route branch of `sendMessage()` (lines around 1488),
    /// extended to forward inline image attachments to the active
    /// runtime via the same path `sendUserMessageFromBridge` uses.
    @MainActor
    func newChatFromBridge(
        chatId: UUID,
        text: String,
        attachments: [WireAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        // Idempotency: if the chat somehow already exists (re-delivery
        // or client retry), fall through to the "append to existing"
        // path so we don't duplicate it.
        if chats.contains(where: { $0.id == chatId }) {
            sendUserMessageFromBridge(chatId: chatId, text: trimmed, attachments: attachments)
            return
        }
        let imageAttachments = attachments.filter { $0.kind == .image }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        let preview = bridgeUserPreview(
            text: trimmed,
            imageCount: imageAttachments.count,
            hasAudio: !audioAttachments.isEmpty
        )
        let userMsg = ChatMessage(role: .user, content: preview, timestamp: Date())
        let titleSeed: String = {
            if !trimmed.isEmpty { return String(trimmed.prefix(40)) }
            if !imageAttachments.isEmpty { return imageAttachments.count == 1 ? "Image" : "Images" }
            if !audioAttachments.isEmpty { return "Voice note" }
            return "Conversation"
        }()
        let newChat = Chat(
            id: chatId,
            title: titleSeed,
            messages: [userMsg],
            createdAt: Date()
        )
        chats.insert(newChat, at: 0)

        if !audioAttachments.isEmpty {
            ingestAudioFromBridge(
                attachments: audioAttachments,
                chatId: chatId,
                messageId: userMsg.id,
                transcript: trimmed
            )
        }

        if let daemonBridgeClient {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        } else if let clawix {
            let imagePaths = AttachmentSpooler.write(
                attachments: imageAttachments,
                scope: chatId.uuidString
            )
            Task { @MainActor in
                await clawix.sendUserMessage(
                    chatId: chatId,
                    text: trimmed,
                    imagePaths: imagePaths
                )
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
        interruptActiveTurn(chatId: id)
    }

    /// Stop the in-flight turn for `chatId` regardless of the current
    /// route. Used by the iPhone bridge so a remote stop affects the
    /// right chat even when the Mac UI is focused on a different one.
    func interruptActiveTurn(chatId: UUID) {
        // Update UI synchronously so the "Thinking" shimmer disappears
        // immediately on click. The backend interrupt is fire-and-forget;
        // late-arriving deltas for this turn are dropped by ClawixService
        // via its interruptedTurnIds gate.
        finalizeOrRemoveAssistantPlaceholder(chatId: chatId)
        if let daemonBridgeClient {
            daemonBridgeClient.interruptTurn(chatId: chatId)
            return
        }
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.interruptCurrentTurn(chatId: chatId)
        }
    }

    /// Drop the chat out of the "Pensando…" / streaming state right now.
    /// If the assistant placeholder is still empty (no text, no reasoning,
    /// no tool activity), remove it entirely so the chat ends on the user's
    /// message. If it has any visible content, freeze it as finished so the
    /// shimmer stops but the partial answer stays.
    func finalizeOrRemoveAssistantPlaceholder(chatId: UUID) {
        // Flush coalesced deltas first so the `isEmpty` check below sees
        // the actual streamed content instead of an empty string from
        // the placeholder.
        flushPendingAssistantTextDeltas(chatId: chatId)
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
            // Freeze the elapsed-seconds counter at the moment of stop.
            // Without this, WorkSummaryHeader's TimelineView keeps ticking
            // because `summary.isActive` stays true while `endedAt` is nil.
            if chats[idx].messages[last].workSummary != nil,
               chats[idx].messages[last].workSummary?.endedAt == nil {
                chats[idx].messages[last].workSummary?.endedAt = Date()
            }
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
        guard selectedAgentRuntime == .codex else { return nil }
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

    /// Resolve the active skills set for a chat at the moment we're
    /// about to dispatch a `thread/start` or `turn/start`. Walks the
    /// global → project → chat hierarchy via `SkillsStore.resolveActive`
    /// and converts the result to the wire shape (`ActiveSkill`). Nil
    /// when the store hasn't been initialised yet (e.g. during preview
    /// rendering or extremely early bootstrap).
    func skillsActiveSnapshot(for chatId: UUID) -> [ActiveSkill]? {
        guard let store = skillsStore else { return nil }
        let projectId = chat(byId: chatId)?.projectId?.uuidString
        let states = store.resolveActive(projectId: projectId, chatId: chatId)
        guard !states.isEmpty else { return nil }
        return states.map { $0.toWire() }
    }

    func ensureSelectedChat(triggerHistoryHydration: Bool = true) {
        guard case let .chat(id) = currentRoute,
              let chat = chat(byId: id) else { return }
        if triggerHistoryHydration && shouldHydrateHistory(chat) {
            hydrateHistoryIfNeeded(chatId: id)
        }
    }

    private func shouldHydrateHistory(_ chat: Chat) -> Bool {
        if !chat.historyHydrated { return true }
        return chat.messages.isEmpty && (chat.rolloutPath != nil || chat.clawixThreadId != nil)
    }

    /// Find a chat by id across both the active and archived lists. The
    /// sidebar's archived section opens chats via the same `.chat(id)`
    /// route, so any view that resolves the current chat must accept ids
    /// from either bucket.
    func chat(byId id: UUID) -> Chat? {
        if let chat = chats.first(where: { $0.id == id }) { return chat }
        return archivedChats.first(where: { $0.id == id })
    }

    /// Apply `mutate` to whichever array currently holds the chat. No-op
    /// if the id is unknown. Used by hydration paths that need to write
    /// back into the chat regardless of its archived state.
    private func mutateChat(id: UUID, _ mutate: (inout Chat) -> Void) {
        if let idx = chats.firstIndex(where: { $0.id == id }) {
            mutate(&chats[idx])
        } else if let idx = archivedChats.firstIndex(where: { $0.id == id }) {
            mutate(&archivedChats[idx])
        }
    }

    private func hydrateHistoryIfNeeded(chatId: UUID, blocking: Bool = false) {
        guard let chat = chat(byId: chatId), shouldHydrateHistory(chat) else { return }
        if FeatureFlags.shared.isVisible(.git), !chat.hasGitRepo, let cwd = chat.cwd {
            if blocking {
                applyGitSnapshot(GitInspector.inspect(cwd: cwd), chatId: chatId)
            } else {
                scheduleGitInspection(chatId: chatId, cwd: cwd)
            }
        }
        if let threadId = chat.clawixThreadId {
            hydrateHistoryFromClawJSSessions(threadId: threadId, chatId: chatId, blocking: blocking)
        } else if let path = chat.rolloutPath {
            // Mac UI path (`blocking == false`): read off the main
            // actor AND only the trailing window of the JSONL so a
            // multi-hundred-MB rollout doesn't stall hydration. The
            // chat opens at the latest turn, the user almost never
            // scrolls hundreds of turns up immediately, and the
            // snapshot has already painted the sidebar; capping the
            // parse cost keeps "click chat → first paint" sub-second
            // regardless of total file size. iOS-bridge path
            // (`blocking == true`): the bridge composes its response
            // inline and needs the full history before it returns,
            // so keep the synchronous full read.
            if blocking {
                applyRolloutResult(RolloutReader.readWithStatus(path: path), chatId: chatId)
            } else {
                Task.detached(priority: .userInitiated) { [weak self] in
                    let result = RolloutReader.readTailWithStatus(path: path)
                    let messages = rolloutChatMessages(from: result)
                    await MainActor.run { [weak self] in
                        self?.applyRolloutMessages(
                            messages,
                            lastTurnInterrupted: result.lastTurnInterrupted,
                            chatId: chatId
                        )
                    }
                }
            }
        }
        if let threadId = chat.clawixThreadId, let clawix {
            Task { @MainActor in
                await clawix.attach(chatId: chat.id, threadId: threadId)
            }
        }
    }

    private func scheduleGitInspection(chatId: UUID, cwd: String) {
        guard gitInspectionTasks[chatId] == nil else { return }
        gitInspectionTasks[chatId] = Task.detached(priority: .utility) { [weak self] in
            let git = GitInspector.inspect(cwd: cwd)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gitInspectionTasks[chatId] = nil
                guard self.chat(byId: chatId)?.cwd == cwd else { return }
                self.applyGitSnapshot(git, chatId: chatId)
            }
        }
    }

    private func applyGitSnapshot(_ git: GitSnapshot, chatId: UUID) {
        mutateChat(id: chatId) { c in
            c.hasGitRepo = git.hasRepo
            c.branch = git.branch
            c.availableBranches = git.branches
            c.uncommittedFiles = git.uncommittedFiles
        }
    }

    private func applyRolloutResult(_ result: RolloutReader.ReadResult, chatId: UUID) {
        applyRolloutMessages(
            rolloutChatMessages(from: result),
            lastTurnInterrupted: result.lastTurnInterrupted,
            chatId: chatId
        )
    }

    private func hydrateHistoryFromClawJSSessions(threadId: String, chatId: UUID, blocking: Bool) {
        let client = ClawJSSessionsClient.local()
        if blocking {
            // The bridge entry point is synchronous. Do not fall back to
            // scanning Codex rollouts here; the daemon/session sidecar is the
            // boundary. The async UI path below will hydrate the chat when it
            // can reach the service.
            return
        }
        Task { @MainActor [weak self] in
            do {
                let records = try await client.listMessages(sessionId: threadId)
                let messages = records.map(Self.chatMessage(fromClawJSSessionMessage:))
                self?.applyRolloutMessages(
                    messages,
                    lastTurnInterrupted: false,
                    chatId: chatId
                )
            } catch {
                self?.appendRuntimeStatusError("Could not load ClawJS session history: \(error.localizedDescription)")
            }
        }
    }

    private static func chatMessage(fromClawJSSessionMessage record: ClawJSSessionsClient.MessageRecord) -> ChatMessage {
        let seconds = record.timestamp > 10_000_000_000 ? Double(record.timestamp) / 1000.0 : Double(record.timestamp)
        return ChatMessage(
            role: record.role == "user" ? .user : .assistant,
            content: record.contentText,
            reasoningText: "",
            streamingFinished: record.streamingState != "streaming",
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    private func applyRolloutMessages(
        _ messages: [ChatMessage],
        lastTurnInterrupted: Bool,
        chatId: UUID
    ) {
        mutateChat(id: chatId) { c in
            c.messages = messages
            c.lastTurnInterrupted = lastTurnInterrupted
            c.historyHydrated = true
        }
    }


    /// Bridge entry point. Hydrates a chat's history from its rollout
    /// file the first time the iPhone opens it, mirroring what the Mac
    /// UI does the moment a chat row is clicked. Without this the
    /// iPhone gets `messagesSnapshot([])` for every `notLoaded` thread
    /// and the user only sees the "no messages loaded" empty state.
    /// Idempotent: subsequent calls for the same chat are no-ops.
    func hydrateHistoryFromBridge(chatId: UUID) {
        guard chat(byId: chatId) != nil else { return }
        // Bridge response composes inline; the iPhone needs messages
        // before this returns. Keeps the legacy synchronous rollout
        // read for that one call site.
        hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
    }

    func applyDaemonChats(_ wireChats: [WireChat]) {
        cachedWireChats = wireChats
        // Refresh `projects` from the latest backendState before
        // resolving each wire chat's project: the daemon may have
        // delivered a snapshot that references workspace roots Codex
        // has just learned about, and `chat(from:wire,old:)` reads
        // through the in-memory `projects` array.
        projects = mergedProjects()
        let oldById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        let oldArchivedById = Dictionary(uniqueKeysWithValues: archivedChats.map { ($0.id, $0) })
        // Wire chats from the daemon mint their own UUIDs each
        // process restart, so matching `old` only by UUID misses
        // every persisted chat. Add a thread-id index so we recover
        // any per-chat metadata (messages, hasGitRepo, branch, etc.)
        // the GUI had cached against the previous daemon UUID.
        let oldByThreadId = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })
        let oldArchivedByThreadId = Dictionary(uniqueKeysWithValues: archivedChats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })
        func resolveOld(for wire: WireChat) -> Chat? {
            if let id = UUID(uuidString: wire.id) {
                if let hit = oldById[id] ?? oldArchivedById[id] { return hit }
            }
            if let tid = wire.threadId {
                return oldByThreadId[tid] ?? oldArchivedByThreadId[tid]
            }
            return nil
        }
        var nextChats: [Chat] = wireChats.compactMap { wire in
            guard !wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        var nextArchived: [Chat] = wireChats.compactMap { wire in
            guard wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        if case let .chat(id) = currentRoute,
           let selected = chat(byId: id),
           let threadId = selected.clawixThreadId,
           !wireChats.contains(where: { $0.threadId?.caseInsensitiveCompare(threadId) == .orderedSame }) {
            if selected.isArchived {
                if !nextArchived.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                    nextArchived.insert(selected, at: 0)
                }
            } else if !nextChats.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                nextChats.insert(selected, at: 0)
            }
        }
        // Fast path: the daemon resends the same chat snapshot on every
        // streaming delta. When nothing actually changed, skip the
        // assignment (which would trigger `objectWillChange` and fan
        // out a full sidebar re-render) and skip the pinnedOrder
        // recompute too (pins haven't moved if the chat list is
        // identical).
        if chats == nextChats && archivedChats == nextArchived { return }
        // Identity-only diff: same ids in the same order, only some
        // slot's contents differ. Mutate those slots in place so each
        // updated row publishes a single change instead of triggering
        // an animated insert/remove transition on every row of the
        // sidebar via `withAnimation` over a wholesale array copy.
        let sameIdentity = chats.count == nextChats.count
            && zip(chats, nextChats).allSatisfy { $0.id == $1.id }
            && archivedChats.count == nextArchived.count
            && zip(archivedChats, nextArchived).allSatisfy { $0.id == $1.id }
        if sameIdentity {
            for idx in nextChats.indices where chats[idx] != nextChats[idx] {
                chats[idx] = nextChats[idx]
            }
            for idx in nextArchived.indices where archivedChats[idx] != nextArchived[idx] {
                archivedChats[idx] = nextArchived[idx]
            }
        } else {
            // Structural diff (insert / remove / reorder). Animate so
            // rows slide in/out via the accordion's per-row transition.
            withAnimation(.easeOut(duration: 0.20)) {
                chats = nextChats
                archivedChats = nextArchived
            }
        }
        // Recompute `pinnedOrder` against the freshly applied chats:
        // either honour the user's local pin order (if they've taken
        // control) or fall back to Codex's global state. Without
        // this the Pinned section would render unsorted because the
        // daemon's wire chats have brand-new UUIDs every reconnect.
        let pinIds = pinsRepo.orderedThreadIds()
        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    func applyDaemonChat(_ wire: WireChat) {
        guard let id = UUID(uuidString: wire.id) else { return }
        if let idx = cachedWireChats.firstIndex(where: { $0.id == wire.id }) {
            cachedWireChats[idx] = wire
        } else {
            cachedWireChats.append(wire)
        }
        withAnimation(.easeOut(duration: 0.20)) {
            if wire.isArchived {
                let old = chats.first(where: { $0.id == id }) ?? archivedChats.first(where: { $0.id == id })
                chats.removeAll { $0.id == id }
                let chat = chat(from: wire, old: old)
                if let idx = archivedChats.firstIndex(where: { $0.id == id }) {
                    archivedChats[idx] = chat
                } else {
                    archivedChats.insert(chat, at: 0)
                }
                return
            }
            if let archivedIndex = archivedChats.firstIndex(where: { $0.id == id }) {
                let chat = chat(from: wire, old: archivedChats[archivedIndex])
                archivedChats.remove(at: archivedIndex)
                chats.insert(chat, at: 0)
                return
            }
            if let idx = chats.firstIndex(where: { $0.id == id }) {
                chats[idx] = chat(from: wire, old: chats[idx])
            } else {
                chats.insert(chat(from: wire, old: nil), at: 0)
            }
        }
    }

    func applyDaemonMessages(chatId: String, messages: [WireMessage], hasMore: Bool? = nil) {
        cachedWireMessagesByChat[chatId] = messages
        guard let id = UUID(uuidString: chatId) else { return }
        // Reset pagination state regardless of where the chat lives:
        // the snapshot is the new baseline. Treat absent metadata as
        // "no older history known" so legacy daemons keep their old
        // eager behaviour.
        messagesPaginationByChat[id] = ChatPagination(
            oldestKnownId: messages.first?.id,
            hasMore: hasMore ?? false,
            loadingOlder: false
        )
        guard let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        // Wholesale rehydrate from the daemon: drop any buffered text
        // delta that would otherwise pile on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        if messages.isEmpty,
           chats[idx].forkedFromChatId != nil,
           !chats[idx].messages.isEmpty {
            chats[idx].historyHydrated = true
            return
        }
        if messages.isEmpty,
           !chats[idx].messages.isEmpty,
           (chats[idx].rolloutPath != nil || chats[idx].clawixThreadId != nil) {
            chats[idx].historyHydrated = true
            return
        }
        // The daemon's `RolloutHistory` reader is intentionally minimal
        // and never populates `timeline` / `workSummary`, so a fresh
        // `messagesSnapshot` would wipe both fields off any local message
        // that already had them (e.g. hydrated from cache or seeded by an
        // earlier `RolloutReader` pass on this Mac). Carry them forward
        // by id so the chat row's "Worked for Xs" header doesn't flash
        // and disappear when the daemon snapshot lands.
        let oldById = Dictionary(uniqueKeysWithValues: chats[idx].messages.map { ($0.id, $0) })
        chats[idx].messages = messages.compactMap { wire in
            chatMessage(from: wire, fallbackingTo: UUID(uuidString: wire.id).flatMap { oldById[$0] })
        }
        optimisticUserMessageIdsByChat[id] = nil
        chats[idx].historyHydrated = true
    }

    func trackOptimisticUserMessage(chatId: UUID, messageId: UUID) {
        optimisticUserMessageIdsByChat[chatId, default: []].insert(messageId)
    }

    func appendDaemonMessage(chatId: String, message: WireMessage) {
        // Mirror first so the snapshot persist sees the same shape the
        // chat detail does, regardless of whether the chat exists in
        // the local model yet (newChat path lands a `messageAppended`
        // before `chatUpdated`).
        if let mIdx = cachedWireMessagesByChat[chatId]?.firstIndex(where: { $0.id == message.id }) {
            cachedWireMessagesByChat[chatId]?[mIdx] = message
        } else {
            cachedWireMessagesByChat[chatId, default: []].append(message)
        }
        guard let id = UUID(uuidString: chatId),
              let idx = chats.firstIndex(where: { $0.id == id })
        else { return }
        // Same fallback as `applyDaemonMessages`: preserve any local
        // `workSummary` / `timeline` the daemon's wire form drops on the
        // floor, keyed by message id.
        let existing = UUID(uuidString: message.id).flatMap { mid in
            chats[idx].messages.first(where: { $0.id == mid })
        }
        guard let msg = chatMessage(from: message, fallbackingTo: existing) else { return }
        // The daemon's wire message is authoritative; any locally
        // buffered delta would double-append on top of it.
        dropPendingAssistantText(chatId: id)
        if msg.role == .user,
           let replacementIdx = optimisticUserReplacementIndex(chatId: id, remote: msg, messages: chats[idx].messages) {
            let localId = chats[idx].messages[replacementIdx].id
            chats[idx].messages[replacementIdx] = msg
            optimisticUserMessageIdsByChat[id]?.remove(localId)
            if optimisticUserMessageIdsByChat[id]?.isEmpty == true {
                optimisticUserMessageIdsByChat[id] = nil
            }
            return
        }
        if let existingIdx = chats[idx].messages.firstIndex(where: { $0.id == msg.id }) {
            chats[idx].messages[existingIdx] = msg
        } else {
            chats[idx].messages.append(msg)
        }
    }

    private func optimisticUserReplacementIndex(
        chatId: UUID,
        remote: ChatMessage,
        messages: [ChatMessage]
    ) -> Int? {
        guard let pending = optimisticUserMessageIdsByChat[chatId], !pending.isEmpty else { return nil }
        if let exact = messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user && $0.content == remote.content
        }) {
            return exact
        }
        return messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user
        })
    }


    /// Daemon-bridge mode counterpart of `ClawixService.refreshRateLimits`:
    /// the GUI's own backend never bootstraps when the LaunchAgent owns
    /// Codex, so the daemon ships its `account/rateLimits/read` view
    /// over the bridge and we land it on the same `@Published` fields
    /// the sidebar / Settings → Usage page already render off.
    func applyDaemonRateLimits(
        snapshot: WireRateLimitSnapshot?,
        byLimitId: [String: WireRateLimitSnapshot]
    ) {
        rateLimits = snapshot.map(rateLimitSnapshot(from:))
        var mapped: [String: RateLimitSnapshot] = [:]
        for (key, value) in byLimitId {
            mapped[key] = rateLimitSnapshot(from: value)
        }
        rateLimitsByLimitId = mapped
    }

    private func rateLimitSnapshot(from wire: WireRateLimitSnapshot) -> RateLimitSnapshot {
        RateLimitSnapshot(
            primary: wire.primary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            secondary: wire.secondary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            credits: wire.credits.map { CreditsSnapshot(
                hasCredits: $0.hasCredits,
                unlimited: $0.unlimited,
                balance: $0.balance
            )},
            limitId: wire.limitId,
            limitName: wire.limitName
        )
    }

    func applyDaemonStreaming(
        chatId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    ) {
        guard let id = UUID(uuidString: chatId),
              let msgId = UUID(uuidString: messageId),
              let cIdx = chats.firstIndex(where: { $0.id == id })
        else { return }
        // Same reasoning as `appendDaemonMessage`: the daemon-supplied
        // content replaces ours wholesale, so any pending tick of
        // local deltas would double up on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        if let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == msgId }) {
            chats[cIdx].messages[mIdx].content = content
            chats[cIdx].messages[mIdx].reasoningText = reasoningText
            chats[cIdx].messages[mIdx].streamingFinished = finished
        } else {
            chats[cIdx].messages.append(ChatMessage(
                id: msgId,
                role: .assistant,
                content: content,
                reasoningText: reasoningText,
                streamingFinished: finished
            ))
        }
        chats[cIdx].hasActiveTurn = !finished
    }

    /// Apply a server-delivered page of older messages. Prepended to
    /// the chat's transcript, deduped by id. Updates the pagination
    /// cursor + clears the in-flight flag so the scroll-up sentinel
    /// can fire again. Mirrors `BridgeStore.applyMessagesPage`.
    func applyDaemonMessagesPage(chatId: String, messages: [WireMessage], hasMore: Bool) {
        guard let id = UUID(uuidString: chatId) else { return }
        var pag = messagesPaginationByChat[id] ?? ChatPagination(oldestKnownId: nil, hasMore: hasMore, loadingOlder: false)
        pag.loadingOlder = false
        pag.hasMore = hasMore
        messagesPaginationByChat[id] = pag
        guard !messages.isEmpty else { return }
        let existing = cachedWireMessagesByChat[chatId] ?? []
        let existingWireIds = Set(existing.map(\.id))
        let prependWire = messages.filter { !existingWireIds.contains($0.id) }
        guard !prependWire.isEmpty else { return }
        cachedWireMessagesByChat[chatId] = prependWire + existing
        mutateChat(id: id) { c in
            let existingChatIds = Set(c.messages.map(\.id))
            let toInsert = prependWire.compactMap { chatMessage(from: $0) }
                .filter { !existingChatIds.contains($0.id) }
            guard !toInsert.isEmpty else { return }
            c.messages.insert(contentsOf: toInsert, at: 0)
        }
        messagesPaginationByChat[id]?.oldestKnownId = cachedWireMessagesByChat[chatId]?.first?.id
    }

    /// Ask the daemon for the next page of older messages if we have a
    /// cursor, the daemon told us there are more, and we don't already
    /// have a page in flight. Called by the chat transcript's scroll-
    /// up sentinel; the guards short-circuit cheaply because the
    /// callback can fire on every onScrollGeometryChange tick.
    func requestOlderIfNeeded(chatId: UUID) {
        guard let pag = messagesPaginationByChat[chatId],
              pag.hasMore,
              !pag.loadingOlder,
              let cursor = pag.oldestKnownId else { return }
        messagesPaginationByChat[chatId]?.loadingOlder = true
        guard let client = daemonBridgeClient,
              client.loadOlderMessages(chatId: chatId, beforeMessageId: cursor)
        else {
            // No daemon attached: clear the flag so a future sentinel
            // firing can retry once the bridge connects.
            messagesPaginationByChat[chatId]?.loadingOlder = false
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self,
                  var pag = self.messagesPaginationByChat[chatId],
                  pag.loadingOlder,
                  pag.oldestKnownId == cursor
            else { return }
            pag.loadingOlder = false
            self.messagesPaginationByChat[chatId] = pag
        }
    }

    /// Restore the on-disk snapshot if one exists. Called once at
    /// startup right after `applySnapshotForFirstPaint()` so the chat
    /// detail renders the last-known transcript immediately while the
    /// daemon's `messagesSnapshot` is still in flight. Bridge frames
    /// shortly overwrite this with the canonical truth.
    func loadCachedSnapshot() {
        guard let payload = SnapshotCache.load() else { return }
        cachedWireChats = payload.chats
        cachedWireMessagesByChat = payload.messagesBySession
        if chats.isEmpty && archivedChats.isEmpty {
            // Fresh install / no SQLite: populate `chats` from the
            // snapshot. No animation; the user is staring at a launch
            // screen, not at a list mutating under their cursor.
            let active: [Chat] = payload.chats.compactMap { wire in
                guard !wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            let arch: [Chat] = payload.chats.compactMap { wire in
                guard wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            chats = active
            archivedChats = arch
        } else {
            // SQLite already populated `chats`. Just hydrate messages
            // for those that match a snapshot entry; leave the rest
            // alone so the daemon can fill them in or the rollout
            // fallback can.
            for (chatIdString, msgs) in payload.messagesBySession {
                guard let id = UUID(uuidString: chatIdString) else { continue }
                mutateChat(id: id) { c in
                    guard c.messages.isEmpty else { return }
                    c.messages = msgs.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
            }
        }
        // Seed pagination cursors so a scroll-up sentinel firing
        // before the daemon (re)delivers `messagesSnapshot` still has
        // an `oldestKnownId` to send. `hasMore` defaults to `false`
        // because we don't know yet; the daemon will refresh on
        // `messagesSnapshot`.
        for (chatIdString, msgs) in payload.messagesBySession {
            guard let id = UUID(uuidString: chatIdString) else { continue }
            messagesPaginationByChat[id] = ChatPagination(
                oldestKnownId: msgs.first?.id,
                hasMore: false,
                loadingOlder: false
            )
        }
    }

    /// Schedule a persist of the wire mirror after 500ms of quiet.
    /// Streaming chunks and rapid chat updates collapse into a single
    /// write; the IO runs on a background queue so the main thread is
    /// never blocked. Safe to call from any of the bridge inbound
    /// paths after a mutation.
    func persistSnapshotDebounced() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let chatsSnap = self.cachedWireChats
            let messagesSnap = self.cachedWireMessagesByChat
            await Task.detached(priority: .background) {
                SnapshotCache.save(chats: chatsSnap, messages: messagesSnap)
            }.value
        }
    }

    private func chat(from wire: WireChat, old: Chat?) -> Chat {
        // Wire chats from the daemon don't share UUIDs with our
        // persisted snapshot, so `old` is usually nil and the chat
        // arrives without `clawixThreadId` / `projectId`. The new
        // `wire.threadId` field (and the daemon's pin-aware
        // `wire.isPinned`) lets us reconstruct both: stamp the thread
        // id, then resolve the project via the same `rootPath`
        // logic `chatFromThread` uses for runtime-sourced summaries.
        let threadId = wire.threadId ?? old?.clawixThreadId
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let resolvedRoot = rootPath(
            threadId: threadId,
            cwd: wire.cwd ?? old?.cwd,
            projectByPath: projectByPath
        )
        let resolvedProjectId: UUID? = resolvedRoot.flatMap { projectByPath[$0]?.id } ?? old?.projectId
        return Chat(
            id: old?.id ?? UUID(uuidString: wire.id) ?? UUID(),
            title: wire.title,
            messages: old?.messages ?? [],
            createdAt: wire.lastMessageAt ?? wire.createdAt,
            clawixThreadId: threadId,
            rolloutPath: old?.rolloutPath,
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: wire.hasActiveTurn,
            projectId: resolvedProjectId,
            isArchived: wire.isArchived,
            isPinned: wire.isPinned,
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: wire.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: wire.branch ?? old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles,
            forkedFromChatId: old?.forkedFromChatId,
            forkedFromTitle: old?.forkedFromTitle,
            forkBannerAfterMessageId: old?.forkBannerAfterMessageId,
            lastTurnInterrupted: wire.lastTurnInterrupted
        )
    }

    private func chatMessage(from wire: WireMessage, fallbackingTo old: ChatMessage? = nil) -> ChatMessage? {
        guard let id = UUID(uuidString: wire.id) else { return nil }
        // Daemon-bridge mode: the helper's `RolloutHistory` reader does
        // not populate `timeline` / `workSummary` / `attachments` on the
        // wire. When this assistant message already exists locally with
        // those fields filled in (cache hydrate, earlier full-fidelity
        // rollout pass, live streaming via ClawixService), preserve them
        // so the chat row's "Worked for Xs" header and inline file/image
        // cards survive the snapshot replay.
        let timeline = wire.timeline.compactMap(timelineEntry(from:))
        let resolvedTimeline = timeline.isEmpty ? (old?.timeline ?? []) : timeline
        let resolvedSummary = wire.workSummary.map(workSummary(from:)) ?? old?.workSummary
        let resolvedAttachments = wire.attachments.isEmpty ? (old?.attachments ?? []) : wire.attachments
        return ChatMessage(
            id: id,
            role: wire.role == .user ? .user : .assistant,
            content: wire.content,
            reasoningText: wire.reasoningText,
            streamingFinished: wire.streamingFinished,
            isError: wire.isError,
            timestamp: wire.timestamp,
            workSummary: resolvedSummary,
            timeline: resolvedTimeline,
            audioRef: wire.audioRef,
            attachments: resolvedAttachments
        )
    }

    private func workSummary(from wire: WireWorkSummary) -> WorkSummary {
        WorkSummary(
            startedAt: wire.startedAt,
            endedAt: wire.endedAt,
            items: wire.items.compactMap(workItem(from:))
        )
    }

    private func timelineEntry(from wire: WireTimelineEntry) -> AssistantTimelineEntry? {
        switch wire {
        case .reasoning(let id, let text):
            return UUID(uuidString: id).map { .reasoning(id: $0, text: text) }
        case .message(let id, let text):
            return UUID(uuidString: id).map { .message(id: $0, text: text) }
        case .tools(let id, let items):
            guard let uuid = UUID(uuidString: id) else { return nil }
            return .tools(id: uuid, items: items.compactMap(workItem(from:)))
        }
    }

    private func workItem(from wire: WireWorkItem) -> WorkItem? {
        let status: WorkItemStatus
        switch wire.status {
        case .inProgress: status = .inProgress
        case .completed: status = .completed
        case .failed: status = .failed
        }
        let kind: WorkItemKind
        switch wire.kind {
        case "command":
            kind = .command(text: wire.commandText, actions: (wire.commandActions ?? []).map { CommandActionKind(rawValue: $0) ?? .unknown })
        case "fileChange":
            kind = .fileChange(paths: wire.paths ?? [])
        case "webSearch":
            kind = .webSearch
        case "mcpTool":
            // The browser-use plugin reports through the synthetic
            // `node_repl` MCP server. The daemon doesn't yet ship a
            // dedicated wire kind, so we relabel here so the live
            // streaming pill reads `Used Node Repl` instead of the raw
            // server/tool dump. Once we reload the chat from the rollout,
            // RolloutReader's classifier upgrades the browser calls to
            // `.jsCall(.browser)` so the timeline picks up the proper
            // `Used the browser` pill.
            let server = wire.mcpServer ?? ""
            let tool = wire.mcpTool ?? ""
            if server == "node_repl" {
                kind = tool == "js_reset"
                    ? .jsReset
                    : .jsCall(title: nil, flavor: .repl)
            } else {
                kind = .mcpTool(server: server, tool: tool)
            }
        case "dynamicTool":
            kind = .dynamicTool(name: wire.dynamicToolName ?? "")
        case "imageGeneration":
            kind = .imageGeneration
        case "imageView":
            kind = .imageView
        default:
            return nil
        }
        return WorkItem(
            id: wire.id,
            kind: kind,
            status: status,
            generatedImagePath: wire.generatedImagePath
        )
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
        guard FeatureFlags.shared.isVisible(.git) else { return }
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
        guard FeatureFlags.shared.isVisible(.git) else { return }
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
        // Drain any pending agent-message deltas FIRST so any text the
        // model emitted before this tool call lands in the timeline ahead
        // of the new `.tools` entry. Otherwise the buffered preamble
        // (flushed on the next runloop tick) would render after the tool.
        flushPendingAssistantTextDeltas(chatId: chatId)
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
        // UI matches the new conversation state immediately. Any text
        // deltas still buffered for this chat belong to the assistant
        // turn we're about to drop, so discard them.
        dropPendingAssistantText(chatId: chatId)
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

    /// Fork an existing chat into a new sibling conversation. Mirrors
    /// Codex Desktop's "Forked from conversation" affordance: the new
    /// chat starts as a verbatim copy of the parent's transcript up to
    /// (and including) the chosen anchor, plus a banner that links back
    /// to the parent. When the runtime is available we also call
    /// `thread/fork` so the server-side rollout carries the same prefix
    /// and the next turn resumes with full context.
    @discardableResult
    func forkConversation(
        chatId: UUID,
        atMessageId anchorMessageId: UUID? = nil,
        sourceSnapshot: Chat? = nil
    ) -> UUID? {
        guard let srcIdx = chats.firstIndex(where: { $0.id == chatId }) else { return nil }
        var source = chats[srcIdx]
        let snapshotMessages = sourceSnapshot.flatMap { $0.id == chatId ? $0.messages : nil } ?? []
        if source.messages.isEmpty, !snapshotMessages.isEmpty {
            source.messages = snapshotMessages
            source.historyHydrated = sourceSnapshot?.historyHydrated ?? source.historyHydrated
            if source.rolloutPath == nil {
                source.rolloutPath = sourceSnapshot?.rolloutPath
            }
        }
        let sourceMessages = forkableMessages(for: source, fallbackMessages: snapshotMessages)
        guard !sourceMessages.isEmpty else { return nil }

        let cutIndex: Int
        if let anchorMessageId,
           let mIdx = sourceMessages.firstIndex(where: { $0.id == anchorMessageId }) {
            cutIndex = mIdx
        } else {
            cutIndex = sourceMessages.count - 1
        }
        guard cutIndex >= 0 else { return nil }

        // Deep-copy each message with a fresh UUID so the transcript in
        // the forked chat is decoupled from the parent. Streaming state
        // is reset because the copied turns are by definition completed
        // history at fork time.
        let copied: [ChatMessage] = sourceMessages[0...cutIndex].map { msg in
            ChatMessage(
                id: UUID(),
                role: msg.role,
                content: msg.content,
                reasoningText: msg.reasoningText,
                streamingFinished: true,
                isError: msg.isError,
                timestamp: msg.timestamp,
                workSummary: msg.workSummary,
                timeline: msg.timeline,
                streamCheckpoints: msg.streamCheckpoints,
                streamPendingTail: "",
                reasoningCheckpoints: msg.reasoningCheckpoints,
                reasoningPendingTails: [:],
                audioRef: msg.audioRef,
                attachments: msg.attachments
            )
        }
        guard let bannerAfterId = copied.last?.id else { return nil }

        let newChat = Chat(
            id: UUID(),
            title: source.title,
            messages: copied,
            createdAt: Date(),
            clawixThreadId: nil,
            rolloutPath: nil,
            historyHydrated: true,
            hasActiveTurn: false,
            projectId: source.projectId,
            isArchived: false,
            isPinned: false,
            hasUnreadCompletion: false,
            cwd: source.cwd,
            hasGitRepo: source.hasGitRepo,
            branch: source.branch,
            availableBranches: source.availableBranches,
            uncommittedFiles: source.uncommittedFiles,
            forkedFromChatId: source.id,
            forkedFromTitle: source.title,
            forkBannerAfterMessageId: bannerAfterId
        )

        chats.insert(newChat, at: 0)
        currentRoute = .chat(newChat.id)
        requestComposerFocus()

        // Fire the runtime-side fork in the background so the new chat
        // resumes with the parent's full context the next time the user
        // sends a message. Failures are non-fatal — the forked chat
        // still works, it just starts a fresh thread on first send.
        if let parentThreadId = source.clawixThreadId,
           let clawix,
           case .ready = clawix.status {
            Task { @MainActor in
                do {
                    _ = try await clawix.forkThread(
                        parentThreadId: parentThreadId,
                        newChatId: newChat.id
                    )
                } catch {
                    // Swallow: the chat is usable even without the
                    // server-side fork. A future send will lazily
                    // create a fresh thread via ensureThread.
                }
            }
        }

        return newChat.id
    }

    private func forkableMessages(for source: Chat, fallbackMessages: [ChatMessage] = []) -> [ChatMessage] {
        if !source.messages.isEmpty {
            return source.messages
        }

        if !fallbackMessages.isEmpty {
            return fallbackMessages
        }

        if let cached = cachedWireMessagesByChat[source.id.uuidString], !cached.isEmpty {
            return cached.compactMap { chatMessage(from: $0) }
        }

        if let path = source.rolloutPath {
            return rolloutChatMessages(from: RolloutReader.readTailWithStatus(path: path))
        }

        return []
    }

    /// Silent variant of `forkConversation` that powers "Open in side
    /// chat". Spawns a sibling conversation that inherits the parent's
    /// full context server-side (via `clawix.forkThread`), but starts
    /// with an empty visible transcript and no fork banner so the
    /// experience reads as a fresh chat. The new chat is pinned to the
    /// parent's right sidebar as a `SidebarItem.chat` tab and is
    /// flagged `isSideChat` so the main sidebar list filters it out.
    /// Returns the new chat's id.
    @discardableResult
    func openInSideChat(parentChatId: UUID) -> UUID? {
        guard let srcIdx = chats.firstIndex(where: { $0.id == parentChatId }) else { return nil }
        let source = chats[srcIdx]

        let newChat = Chat(
            id: UUID(),
            title: "",
            messages: [],
            createdAt: Date(),
            clawixThreadId: nil,
            rolloutPath: nil,
            historyHydrated: true,
            hasActiveTurn: false,
            projectId: source.projectId,
            isArchived: false,
            isPinned: false,
            hasUnreadCompletion: false,
            cwd: source.cwd,
            hasGitRepo: source.hasGitRepo,
            branch: source.branch,
            availableBranches: source.availableBranches,
            uncommittedFiles: source.uncommittedFiles,
            forkedFromChatId: source.id,
            forkedFromTitle: source.title,
            // No banner: the side-chat UX is "looks like a fresh chat,
            // but the daemon side carries the parent's context".
            forkBannerAfterMessageId: nil,
            isSideChat: true
        )
        chats.insert(newChat, at: 0)

        // Mount the side chat as a tab in the parent's right sidebar.
        // We mutate the parent's `ChatSidebarState` directly (rather
        // than going through `currentSidebar`) so this works whether or
        // not the user is currently viewing the parent route.
        var sidebar = chatSidebars[parentChatId] ?? .empty
        sidebar.items.append(.chat(.init(id: newChat.id)))
        sidebar.activeItemId = newChat.id
        sidebar.isOpen = true
        chatSidebars[parentChatId] = sidebar
        persistChatSidebars()

        // Mirror the runtime fork so the side chat's first prompt
        // resumes inside the parent's full thread context. Failures
        // are non-fatal — if the runtime is down the side chat still
        // works as a fresh thread.
        if let parentThreadId = source.clawixThreadId,
           let clawix,
           case .ready = clawix.status {
            Task { @MainActor in
                do {
                    _ = try await clawix.forkThread(
                        parentThreadId: parentThreadId,
                        newChatId: newChat.id
                    )
                } catch {
                    // Swallow: see forkConversation for rationale.
                }
            }
        }

        return newChat.id
    }

    /// Send variant for a side-chat composer. Mirrors `sendMessage()`
    /// but drives an explicit chat id and an explicit, view-owned
    /// composer state — necessary because the side chat lives in the
    /// right sidebar and uses its own `ComposerState`, independent of
    /// `appState.composer` (the global one tied to the main route).
    func sendMessage(forChatId chatId: UUID, composer: ComposerState) {
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
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].messages.append(userMsg)
        chats[idx].lastTurnInterrupted = false
        // Side chats start with an empty title so the tab pill reads
        // "Side chat" until the user types. On the first message we
        // promote the prompt to the title — same convention as the
        // home-route new-chat branch in `sendMessage()`.
        if chats[idx].title.isEmpty {
            let titleSeed = trimmed.isEmpty
                ? (attachments.first?.filename ?? "Side chat")
                : trimmed
            chats[idx].title = String(titleSeed.prefix(40))
        }

        composer.text = ""
        composer.attachments = []

        if let daemonBridgeClient {
            // Same as `sendMessage()`: keep the BridgeBus subscription
            // explicit because we don't switch `currentRoute` here
            // (the user is still on the parent chat route).
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.openSession(chatId)
            daemonBridgeClient.sendPrompt(
                chatId: chatId,
                text: combined,
                attachments: wireAttachments(from: attachments)
            )
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: combined)
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
        guard let threadId = chats[idx].clawixThreadId else {
            var copy = chats
            copy[idx].title = trimmed
            chats = copy
            return
        }
        guard let clawix,
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
        if let daemonBridgeClient {
            archiveLocally(chatIndex: idx)
            daemonBridgeClient.archiveChat(chatId)
            return
        }
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
        Task { @MainActor in
            try? await ClawJSSessionsClient.local().updateSession(
                id: threadId,
                patch: ["archived": .bool(true), "pinned": .bool(false)]
            )
        }

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
        // Fixture / showcase mode is the source of truth for the
        // archived list — `applyThreads` already populates
        // `archivedChats` from the seeded JSON. Hitting the runtime here
        // would wipe that curated set with the (empty) real backend.
        if AgentThreadStore.fixtureThreads() != nil { return }
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
        if let daemonBridgeClient {
            var moved = archivedChats[idx]
            moved.isArchived = false
            archivedChats.remove(at: idx)
            chats.insert(moved, at: 0)
            daemonBridgeClient.unarchiveChat(chatId)
            return
        }
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
        Task { @MainActor in
            try? await ClawJSSessionsClient.local().updateSession(
                id: threadId,
                patch: ["archived": .bool(false), "sidebarVisible": .bool(true)]
            )
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
                Task { @MainActor in
                    try? await ClawJSSessionsClient.local().updateSession(id: threadId, patch: ["pinned": .bool(true)])
                }
            }
        } else {
            pinnedOrder.removeAll { $0 == chatId }
            if let threadId = copy[idx].clawixThreadId {
                pinsRepo.unpin(threadId)
                Task { @MainActor in
                    try? await ClawJSSessionsClient.local().updateSession(id: threadId, patch: ["pinned": .bool(false)])
                }
            }
        }
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
    }

    /// Move a project to a new slot in the manual ordering used by the
    /// sidebar's "Custom" sort mode. Pass the project the moved row should
    /// land *before*, or `nil` to drop at the end. Computing relative to a
    /// sibling avoids the index-shift bug when the dragged row is above
    /// its target. Persisted via `ProjectOrdersRepository`.
    func reorderProject(projectId: UUID, beforeProjectId: UUID?) {
        guard projectId != beforeProjectId else { return }
        // Build a complete ordering of the currently-visible projects so
        // the persisted list stays a superset of the live one. Projects
        // not yet in `manualProjectOrder` keep their natural order from
        // `projects` (creation/insertion order from `mergedProjects`).
        var order = manualProjectOrder
        let knownIds = Set(order)
        let livedIds = Set(projects.map(\.id))
        // Drop entries for projects that no longer exist (deleted /
        // hidden Codex roots) so the persisted list never grows
        // unbounded across launches.
        order.removeAll { !livedIds.contains($0) }
        // Append projects we've never positioned manually, in natural
        // order, so we have a position for every live project.
        for project in projects where !knownIds.contains(project.id) {
            order.append(project.id)
        }
        order.removeAll { $0 == projectId }
        if let beforeProjectId, let idx = order.firstIndex(of: beforeProjectId) {
            order.insert(projectId, at: idx)
        } else {
            order.append(projectId)
        }
        manualProjectOrder = order
        projectOrdersRepo.setOrder(order)
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
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().updateSession(
                    id: threadId,
                    patch: ["projectPath": .string(project.path)]
                )
            }
        } else {
            chatProjectsRepo.clearOverride(threadId: threadId)
            chatProjectsRepo.markProjectless(threadId)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().updateSession(
                    id: threadId,
                    patch: ["projectPath": .null]
                )
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
            projectsRepo.upsert(project)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: project.name,
                    path: project.path,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
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
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: project.name,
                    path: project.path,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
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
        Task { @MainActor in
            let client = ClawJSSessionsClient.local()
            guard let projects = try? await client.listProjects(),
                  let project = projects.first(where: { StableProjectID.uuid(for: $0.path) == projectId })
            else { return }
            try? await client.deleteProject(id: project.id)
        }
    }

    func renameProject(id: UUID, newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        let projectPath = projects[idx].path
        if selectedProject?.id == id { selectedProject = projects[idx] }
        projectsRepo.rename(id: id, to: trimmed)
        if !projectPath.isEmpty {
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: trimmed,
                    path: projectPath,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
            }
        }
    }

    /// Convenience: start a new chat scoped to a specific project.
    /// Selects the project in the composer pill and routes Home so the
    /// next message creates a chat associated with it.
    func startNewChat(in project: Project) {
        selectedProject = project
        currentRoute = .home
    }

}
