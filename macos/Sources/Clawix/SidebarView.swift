import SwiftUI
import UniformTypeIdentifiers

/// Custom URL scheme used by project rows in the sidebar's "Custom" sort
/// mode to encode the dragged project's id as `clawix-project:<UUID>`.
/// NSURL drags conform to `public.url` (a sibling of
/// `public.utf8-plain-text` under `public.data`), so the project reorder
/// drag does NOT match `ChatDropTarget`'s `.onDrop(of: [.text])` and
/// can't be misrouted into `moveChatToProject`. Going through a system
/// UTI also sidesteps having to declare a custom UTI in `Info.plist`,
/// which `UTType(importedAs:)` without an `Info.plist` declaration
/// requires for SwiftUI's `.onDrop(of:)` filter to recognise it.
let clawixProjectURLScheme = "clawix-project"

/// Custom URL scheme used by tool rows in the sidebar's "Tools" section
/// when reordering. Same rationale as `clawixProjectURLScheme`: registering
/// the drag as `public.url` keeps it invisible to chat / project drop
/// targets, which match different schemes.
let clawixToolURLScheme = "clawix-tool"

/// Catalog of every entry rendered in the sidebar's `Tools` section.
/// The IDs are stable strings (NOT route descriptions) so the user's
/// custom order persists even if a route's path changes; new tools added
/// in future releases simply append at the bottom of the saved order on
/// first launch.
enum SidebarToolIcon: Equatable {
    case system(String)
    case secrets
    case clawixLogo
}

struct SidebarToolEntry: Identifiable, Equatable {
    let id: String
    let title: LocalizedStringKey
    let titleString: String
    let icon: SidebarToolIcon
    let route: SidebarRoute

    static func == (lhs: SidebarToolEntry, rhs: SidebarToolEntry) -> Bool {
        lhs.id == rhs.id
            && lhs.titleString == rhs.titleString
            && lhs.icon == rhs.icon
            && lhs.route == rhs.route
    }
}

enum SidebarToolsCatalog {
    static let entries: [SidebarToolEntry] = [
        SidebarToolEntry(id: "home",      title: "Home",      titleString: "Home",
                         icon: .system("house"),                     route: .iotHome),
        SidebarToolEntry(id: "tasks",     title: "Tasks",     titleString: "Tasks",
                         icon: .system("checkmark.circle"),          route: .databaseCollection("tasks")),
        SidebarToolEntry(id: "goals",     title: "Goals",     titleString: "Goals",
                         icon: .system("flag"),                      route: .databaseCollection("goals")),
        SidebarToolEntry(id: "notes",     title: "Notes",     titleString: "Notes",
                         icon: .system("note.text"),                 route: .databaseCollection("notes")),
        SidebarToolEntry(id: "calendar",  title: "Calendar",  titleString: "Calendar",
                         icon: .system("calendar"),                  route: .calendarHome),
        SidebarToolEntry(id: "contacts",  title: "Contacts",  titleString: "Contacts",
                         icon: .system("person.crop.circle"),        route: .contactsHome),
        SidebarToolEntry(id: "projects",  title: "Projects",  titleString: "Projects",
                         icon: .system("square.stack.3d.up"),        route: .databaseCollection("projects")),
        SidebarToolEntry(id: "secrets",   title: "Secrets",   titleString: "Secrets",
                         icon: .secrets,                             route: .secretsHome),
        SidebarToolEntry(id: "memory",    title: "Memory",    titleString: "Memory",
                         icon: .system("brain"),                     route: .memoryHome),
        SidebarToolEntry(id: "database",  title: "Database",  titleString: "Database",
                         icon: .system("cylinder.split.1x2"),        route: .databaseHome),
        SidebarToolEntry(id: "index",     title: "Index",     titleString: "Index",
                         icon: .system("books.vertical"),            route: .indexHome),
        SidebarToolEntry(id: "marketplace", title: "Marketplace", titleString: "Marketplace",
                         icon: .system("handshake"),                 route: .marketplaceHome),
        SidebarToolEntry(id: "photos",    title: "Photos",    titleString: "Photos",
                         icon: .system("photo.on.rectangle.angled"), route: .drivePhotos),
        SidebarToolEntry(id: "documents", title: "Documents", titleString: "Documents",
                         icon: .system("doc.text"),                  route: .driveDocuments),
        SidebarToolEntry(id: "recent",    title: "Recent",    titleString: "Recent",
                         icon: .system("clock.arrow.circlepath"),    route: .driveRecent),
        SidebarToolEntry(id: "drive",     title: "Drive",     titleString: "Drive",
                         icon: .system("internaldrive"),             route: .driveAdmin),
        SidebarToolEntry(id: "agents",    title: "Agents",    titleString: "Agents",
                         icon: .clawixLogo,                          route: .agentsHome),
        SidebarToolEntry(id: "personalities", title: "Personalities", titleString: "Personalities",
                         icon: .system("theatermasks"),              route: .personalitiesHome),
        SidebarToolEntry(id: "skillCollections", title: "Skill Collections", titleString: "Skill Collections",
                         icon: .system("square.stack"),              route: .skillCollectionsHome),
        SidebarToolEntry(id: "connections", title: "Connections", titleString: "Connections",
                         icon: .system("link.circle"),               route: .connectionsHome),
        SidebarToolEntry(id: "publishing",    title: "Publishing",    titleString: "Publishing",
                         icon: .system("megaphone"),                 route: .publishingHome),
    ]

    static func entry(byId id: String) -> SidebarToolEntry? {
        entries.first { $0.id == id }
    }

    static func gatedFeature(for id: String) -> AppFeature? {
        switch id {
        case "home":             return .iotHome
        case "calendar":         return .calendar
        case "contacts":         return .contacts
        case "secrets":          return .secrets
        case "database":         return .database
        case "index":            return .index
        case "marketplace":      return .marketplace
        case "agents":           return .agents
        case "personalities":    return .agents
        case "skillCollections": return .skillCollections
        case "connections":      return .agents
        case "publishing":           return .publishing
        default:                 return nil
        }
    }
}

/// Top-level layout of the chat list. Either group chats under their
/// project (with a "Chats" bucket for the projectless ones) or render a
/// single flat chronological list.
enum SidebarViewMode: String { case grouped, chronological }

/// How projects are ordered when `viewMode == .grouped`. `.custom` lets
/// the user drag-reorder the list; the order is persisted via
/// `ProjectOrdersRepository`.
enum ProjectSortMode: String { case recent, creation, name, custom }

/// Legacy mode kept only for one-shot migration. Older builds wrote
/// values from this enum into `SidebarOrganizationMode`. Removed from the
/// UI; `migrateLegacySidebarPrefs()` translates remaining values into
/// `SidebarViewMode` + `ProjectSortMode` on first launch.
private enum LegacySidebarOrganizationMode: String {
    case byProject, recentProjects, chronological
}

/// UserDefaults suite used to persist sidebar preferences across launches.
/// Same suite already used for the main window frame and browser state.
enum SidebarPrefs {
    static let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard

    /// Read a Bool with a fallback for keys that have never been written.
    /// `UserDefaults.bool(forKey:)` returns `false` for missing keys, which
    /// would silently flip our "expanded by default" sections on first run.
    static func bool(forKey key: String, default fallback: Bool) -> Bool {
        if store.object(forKey: key) == nil { return fallback }
        return store.bool(forKey: key)
    }

    /// Translate the old `SidebarOrganizationMode` value (if present) into
    /// the new `SidebarViewMode` + `ProjectSortMode` keys, then delete the
    /// legacy key so subsequent launches are no-ops. Idempotent.
    /// Mappings:
    ///   byProject       -> grouped + custom (insertion-order ≈ manual)
    ///   recentProjects  -> grouped + recent
    ///   chronological   -> chronological (sort key untouched)
    static func migrateLegacySidebarPrefs() {
        let legacyKey = "SidebarOrganizationMode"
        guard let raw = store.string(forKey: legacyKey),
              let legacy = LegacySidebarOrganizationMode(rawValue: raw) else {
            return
        }
        // Don't clobber values the user has already set explicitly via the
        // new UI on a previous launch.
        let viewKey = "SidebarViewMode"
        let sortKey = "ProjectSortMode"
        let alreadyMigrated = store.string(forKey: viewKey) != nil
        if !alreadyMigrated {
            switch legacy {
            case .byProject:
                store.set(SidebarViewMode.grouped.rawValue, forKey: viewKey)
                store.set(ProjectSortMode.custom.rawValue, forKey: sortKey)
            case .recentProjects:
                store.set(SidebarViewMode.grouped.rawValue, forKey: viewKey)
                store.set(ProjectSortMode.recent.rawValue, forKey: sortKey)
            case .chronological:
                store.set(SidebarViewMode.chronological.rawValue, forKey: viewKey)
            }
        }
        store.removeObject(forKey: legacyKey)
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vault: SecretsManager
    @EnvironmentObject var flags: FeatureFlags
    @State private var settingsPopoverOpen: Bool = false
    @State private var projectEditor: ProjectEditorContext?
    @State private var projectRenameTarget: Project?
    @State private var projectMenuOpenId: UUID?
    @State private var expandedProjects: Set<UUID> = []
    /// Projects that the user has expanded past the default 5-chat
    /// preview by tapping "Show more" in their accordion. Cleared on
    /// collapse so reopening a project comes back to the trimmed view.
    @State private var projectsShowingExtended: Set<UUID> = []
    @State private var projectsHeaderHovered: Bool = false
    @State private var newProjectMenuOpen: Bool = false
    @State private var organizeMenuOpen: Bool = false
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarViewMode, store: SidebarPrefs.store)
    private var viewModeRaw: String = SidebarViewMode.grouped.rawValue
    @AppStorage(ClawixPersistentSurfaceKeys.projectSortMode, store: SidebarPrefs.store)
    private var projectSortModeRaw: String = ProjectSortMode.recent.rawValue
    @State private var pinnedExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarPinnedExpanded, default: true)
    @State private var pinnedFilterMenuOpen: Bool = false
    /// Comma-separated list of disabled pinned-filter tokens. UUIDs identify
    /// projects; the literal `__none__` represents the implicit "no project"
    /// bucket. Persisted as a single string so the existing `SidebarPrefs`
    /// `UserDefaults` suite can hold it without a custom codec.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarPinnedFilterDisabled, store: SidebarPrefs.store)
    private var pinnedFilterDisabledRaw: String = ""
    /// Mirror of `pinnedFilterDisabledRaw` for the chronological "All chats"
    /// list. Same comma-separated UUID + `__none__` sentinel format. Edited
    /// from inside the Organize popup's "Filter > By project" submenu.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarChronoFilterDisabled, store: SidebarPrefs.store)
    private var chronoFilterDisabledRaw: String = ""
    @State private var chronoExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarChronoExpanded, default: true)
    @State private var noProjectExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarNoProjectExpanded, default: true)
    @State private var projectsExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarProjectsExpanded, default: true)
    @State private var archivedExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarArchivedExpanded, default: false)
    @State private var toolsExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarToolsExpanded, default: true)
    /// Master switch for the Apps surface. Mirrors the Settings toggle
    /// that lives on `SidebarPrefs.store`; defaults on for new users.
    @AppStorage(ClawixPersistentSurfaceKeys.appsFeatureEnabled, store: SidebarPrefs.store)
    private var appsFeatureEnabled: Bool = true
    /// Custom order of tools, persisted as a comma-separated list of
    /// catalog ids. Empty string means "use the catalog's natural order".
    /// New tools added to the catalog in future releases append at the
    /// end of the saved order on first launch.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarToolsOrder, store: SidebarPrefs.store)
    private var toolsOrderRaw: String = ""
    /// Hidden tools, persisted as a comma-separated list of catalog ids.
    /// Toggled from the section's filter popup; tools in this set are
    /// dropped from the rendered list but stay in the saved order so
    /// re-enabling them restores their previous position.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarToolsHidden, store: SidebarPrefs.store)
    private var toolsHiddenRaw: String = ""
    @State private var toolsFilterMenuOpen: Bool = false
    @State private var chronoLimit: Int = 100

    private var viewMode: SidebarViewMode {
        SidebarViewMode(rawValue: viewModeRaw) ?? .grouped
    }

    private var projectSortMode: ProjectSortMode {
        ProjectSortMode(rawValue: projectSortModeRaw) ?? .recent
    }

    /// One-shot derivation of every list the sidebar needs from
    /// `appState.chats`, computed in a single pass instead of three
    /// separate filter+sort traversals (plus another pass per project).
    /// With ~160 chats and dozens of projects the previous code did
    /// O(N · M) work per render — this is O(N + M log M).
    fileprivate struct SidebarSnapshot {
        let pinned: [Chat]
        /// Chats per project, sorted by recency and capped at 10 to
        /// match the previous `projectChats(_:)` contract.
        let byProject: [UUID: [Chat]]
        /// Most-recent chat date per project, used to order projects in
        /// `recentProjects` mode without re-scanning chats per project.
        let recentDateByProject: [UUID: Date]
        /// Chronological list (excludes pinned, sorted desc).
        let chrono: [Chat]
    }

    private func makeSnapshot() -> SidebarSnapshot {
        PerfSignpost.uiSidebar.interval("snapshot") {
        RenderProbe.time("makeSnapshot") {
            let order = appState.pinnedOrder
            let pinIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            var pinnedRaw: [Chat] = []
            var byProjectRaw: [UUID: [Chat]] = [:]
            var chronoRaw: [Chat] = []
            for chat in appState.chats {
                // Side chats live only inside their parent's right
                // sidebar; never surface them in the main sidebar list
                // (chrono, per-project, or pinned).
                if chat.isSideChat { continue }
                if chat.isPinned {
                    pinnedRaw.append(chat)
                    continue
                }
                if let pid = chat.projectId {
                    byProjectRaw[pid, default: []].append(chat)
                }
                chronoRaw.append(chat)
            }
            pinnedRaw.sort { lhs, rhs in
                let li = pinIndex[lhs.id] ?? Int.max
                let ri = pinIndex[rhs.id] ?? Int.max
                if li != ri { return li < ri }
                return lhs.createdAt > rhs.createdAt
            }
            chronoRaw.sort { $0.createdAt > $1.createdAt }
            var byProject: [UUID: [Chat]] = [:]
            var recentDateByProject: [UUID: Date] = [:]
            byProject.reserveCapacity(byProjectRaw.count)
            recentDateByProject.reserveCapacity(byProjectRaw.count)
            for (pid, list) in byProjectRaw {
                let sortedList = list.sorted { $0.createdAt > $1.createdAt }
                byProject[pid] = Array(sortedList.prefix(10))
                recentDateByProject[pid] = sortedList.first?.createdAt
            }
            return SidebarSnapshot(
                pinned: pinnedRaw,
                byProject: byProject,
                recentDateByProject: recentDateByProject,
                chrono: chronoRaw
            )
        }
        }
    }

    private func recentChatCallbacks(for chat: Chat, archived: Bool) -> RecentChatRowCallbacks {
        makeRecentChatCallbacks(appState: appState, chat: chat, archived: archived)
    }

    /// One project row inside the sidebar's grouped view: the existing
    /// `ChatDropTarget` (so chats can be dragged onto a project to be
    /// reassigned) wrapping a `ProjectAccordion`. Extracted so both the
    /// `LazyVStack` (regular sort modes) and `ProjectReorderableList`
    /// (custom sort mode) call sites render identical content.
    @ViewBuilder
    private func projectRow(
        _ project: Project,
        snapshot: SidebarSnapshot,
        currentChatId: UUID?
    ) -> some View {
        ChatDropTarget { droppedId in
            appState.moveChatToProject(chatId: droppedId, projectId: project.id)
            return true
        } content: {
            ProjectAccordion(
                project: project,
                expanded: expandedProjects.contains(project.id),
                chats: snapshot.byProject[project.id] ?? [],
                showingExtended: projectsShowingExtended.contains(project.id),
                onToggle: {
                    if expandedProjects.contains(project.id) {
                        expandedProjects.remove(project.id)
                        // Re-collapsing a project resets the extended
                        // 10-chat slice so the next open lands back on
                        // the 5-chat preview, per design.
                        projectsShowingExtended.remove(project.id)
                    } else {
                        expandedProjects.insert(project.id)
                        // Fire-and-forget refresh. The accordion already
                        // has its rows from the SQLite snapshot; this
                        // diff-merges any updates the daemon has beyond
                        // what the pre-warm caught, animated.
                        Task.detached(priority: .userInitiated) {
                            await appState.loadThreadsForProject(project)
                        }
                    }
                },
                onMenuToggle: {
                    projectMenuOpenId = projectMenuOpenId == project.id ? nil : project.id
                },
                onNewChat: {
                    appState.startNewChat(in: project)
                },
                onShowMore: {
                    let pid = project.id
                    withAnimation(.easeOut(duration: 0.22)) {
                        _ = projectsShowingExtended.insert(pid)
                    }
                },
                onViewAll: {
                    appState.searchScopedProjectId = project.id
                    appState.currentRoute = .search
                },
                menuOpen: projectMenuOpenId == project.id,
                selectedChatId: currentChatId,
                chatCallbacks: { recentChatCallbacks(for: $0, archived: false) }
            )
            .equatable()
        }
    }

    private var selectedChatId: UUID? {
        if case let .chat(id) = appState.currentRoute { return id }
        return nil
    }

    private func sortedProjects(snapshot: SidebarSnapshot) -> [Project] {
        switch projectSortMode {
        case .recent:
            return appState.projects.sorted { lhs, rhs in
                let l = snapshot.recentDateByProject[lhs.id] ?? .distantPast
                let r = snapshot.recentDateByProject[rhs.id] ?? .distantPast
                return l > r
            }
        case .creation:
            return appState.projects
        case .name:
            return appState.projects.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .custom:
            let positionById: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: appState.manualProjectOrder.enumerated().map { ($1, $0) }
            )
            let naturalIdx: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: appState.projects.enumerated().map { ($1.id, $0) }
            )
            return appState.projects.sorted { lhs, rhs in
                let l = positionById[lhs.id] ?? Int.max
                let r = positionById[rhs.id] ?? Int.max
                if l != r { return l < r }
                return (naturalIdx[lhs.id] ?? 0) < (naturalIdx[rhs.id] ?? 0)
            }
        }
    }

    @ViewBuilder
    private func sidebarScrollContent(snapshot: SidebarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if flags.isVisible(.secrets) {
                toolsSection
            }

            if appsFeatureEnabled && flags.isVisible(.apps) {
                AppsSidebarSection(appsStore: .shared)
            }

            if flags.isVisible(.design) {
                DesignSidebarSection()
            }

            if flags.isVisible(.life) {
                LifeSidebarSection()
            }

            if !snapshot.pinned.isEmpty {
                let pinnedSources = pinnedFilterSources(from: snapshot.pinned)
                let visiblePinned = applyPinnedFilter(to: snapshot.pinned)
                let canFilterPinned = pinnedSources.count >= 2
                BasicSectionHeader(
                    title: "Pinned",
                    expanded: $pinnedExpanded,
                    leadingIcon: AnyView(PinIcon(size: 15.0, lineWidth: 1.5)),
                    trailingIcon: canFilterPinned ? AnyView(pinnedFilterButton) : nil,
                    trailingForceVisible: pinnedFilterMenuOpen
                )
                SidebarAccordion(
                    expanded: pinnedExpanded,
                    targetHeight: visiblePinned.isEmpty
                        ? 26 + SidebarRowMetrics.sectionEdgePadding
                        : CGFloat(visiblePinned.count) * 35
                            + SidebarRowMetrics.sectionEdgePadding
                ) {
                    // Populated case: `PinnedReorderableList.trailingSlotZone`
                    // already ends with a `sectionEdgePadding`-tall strip that
                    // provides the bottom gap and the drop-at-end target, so
                    // we don't add a parent spacer there. The empty case has
                    // no list, so we add the spacer manually to match the
                    // bottom gap every other closable section shows.
                    if visiblePinned.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text("No pinned chats match the filter")
                                .font(BodyFont.system(size: 13.5, wght: 500))
                                .foregroundColor(Color(white: 0.40))
                                .padding(.leading, 34)
                                .padding(.vertical, 4)
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    } else {
                        PinnedReorderableList(
                            appState: appState,
                            pinned: visiblePinned,
                            selectedChatId: selectedChatId
                        )
                        .equatable()
                        .padding(.leading, 8)
                        .padding(.trailing, 0)
                    }
                }
            }

            if viewMode == .chronological {
                chronoHeader
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .sidebarHover { projectsHeaderHovered = $0 }
                let visibleChrono = applyChronoFilter(to: snapshot.chrono)
                let chronoCount = min(visibleChrono.count, chronoLimit)
                let chronoFilterActive = !effectiveDisabledTokens(
                    chronoFilterDisabled,
                    sources: chronoFilterSources(from: snapshot.chrono)
                ).isEmpty
                let showEmptyState = visibleChrono.isEmpty
                SidebarAccordion(
                    expanded: chronoExpanded,
                    targetHeight: showEmptyState
                        ? 26 + SidebarRowMetrics.sectionEdgePadding
                        : SidebarRowMetrics.recentChats(count: chronoCount)
                            + SidebarRowMetrics.sectionEdgePadding
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            if showEmptyState {
                                Text(chronoFilterActive && !snapshot.chrono.isEmpty
                                     ? "No chats match the filter"
                                     : "No chats")
                                    .font(BodyFont.system(size: 13.5, wght: 500))
                                    .foregroundColor(Color(white: 0.40))
                                    .padding(.leading, 34)
                                    .padding(.vertical, 4)
                            } else {
                                let currentChatId = selectedChatId
                                ForEach(visibleChrono.prefix(chronoLimit), id: \.id) { chat in
                                    RecentChatRow(
                                        chat: chat,
                                        isSelected: currentChatId == chat.id,
                                        leadingIcon: .pinOnHover,
                                        callbacks: recentChatCallbacks(for: chat, archived: false)
                                    )
                                    .equatable()
                                }
                            }
                        }
                        .padding(.leading, 8)
                        if !showEmptyState {
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    }
                }
            } else {
                let projectlessChats = snapshot.chrono.filter { $0.projectId == nil }
                if !projectlessChats.isEmpty {
                    sectionHeader(
                        "Chats",
                        expanded: $noProjectExpanded,
                        leadingIcon: AnyView(
                            LucideIcon(.messageCircle, size: 13)
                        )
                    )
                    SidebarAccordion(
                        expanded: noProjectExpanded,
                        targetHeight: SidebarRowMetrics.recentChats(count: projectlessChats.count)
                            + SidebarRowMetrics.sectionEdgePadding
                    ) {
                        let currentChatId = selectedChatId
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(projectlessChats) { chat in
                                    RecentChatRow(
                                        chat: chat,
                                        isSelected: currentChatId == chat.id,
                                        leadingIcon: .pinOnHover,
                                        callbacks: recentChatCallbacks(for: chat, archived: false)
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.leading, 8)
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    }
                }

                projectsHeader
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .sidebarHover { projectsHeaderHovered = $0 }

                // Projects list. We add/remove the whole subtree when
                // toggling. Wrapping in `ExpandableContainer` collapses the
                // section to 0pt on first layout: its measurement twin sees
                // each `ProjectAccordion` clip its inner `SmoothAccordion`
                // to height 0 while collapsed, so the height preference
                // arrives as 0 and never recovers.
                if projectsExpanded {
                    let currentChatId = selectedChatId
                    let projectsList = sortedProjects(snapshot: snapshot)
                    // Same pattern as every other collapsible section: render
                    // `sectionEdgePadding` as a real `Color.clear` spacer at
                    // the end of the accordion's content. `SidebarAccordion`
                    // takes `max(target, measured)` for the frame, so the
                    // visible bottom gap is governed by the content's
                    // intrinsic size — which always includes the spacer —
                    // rather than by `targetHeight` overshoot. Earlier this
                    // section relied on overshoot to "produce" the buffer
                    // and the row-height estimate (28pt) was too low vs the
                    // actual ~35pt rows; `measured > target` ate the buffer
                    // entirely, so Projects appeared glued to Archived
                    // while Pinned/Chats had a generous gap.
                    let projectRowHeightEstimate: CGFloat = 28
                    let projectsListHeightEstimate = CGFloat(projectsList.count) * projectRowHeightEstimate
                        + CGFloat(max(projectsList.count - 1, 0)) * 4
                    SidebarAccordion(
                        expanded: true,
                        targetHeight: projectsListHeightEstimate
                            + SidebarRowMetrics.sectionEdgePadding
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if projectSortMode == .custom {
                                    // `ProjectReorderableList` adds drag-and-drop
                                    // gap zones between every row and persists the
                                    // resulting order via `appState.reorderProject`.
                                    // It uses a non-lazy `VStack` because measuring
                                    // row frames for the drag chip needs every row
                                    // to be in the layout tree.
                                    ProjectReorderableList(
                                        appState: appState,
                                        projects: projectsList
                                    ) { project in
                                        projectRow(
                                            project,
                                            snapshot: snapshot,
                                            currentChatId: currentChatId
                                        )
                                    }
                                } else {
                                    // `LazyVStack` instead of `VStack` so accordion
                                    // bodies for projects scrolled out of view never
                                    // instantiate. Visible projects still re-evaluate
                                    // normally; the saving is the long tail of
                                    // off-screen ones (~70-90 out of ~100 in a
                                    // typical sidebar).
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(projectsList) { project in
                                            projectRow(
                                                project,
                                                snapshot: snapshot,
                                                currentChatId: currentChatId
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 8)
                            // Only the alphabetical (LazyVStack) path needs an
                            // explicit trailing spacer; in `.custom` mode
                            // `ProjectReorderableList.trailingSlotZone` already
                            // ends with a `sectionEdgePadding` strip that
                            // doubles as the section gap. Adding a parent
                            // spacer in custom mode would stack on top of that
                            // strip and bloat the gap.
                            if projectSortMode != .custom {
                                Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            archivedSection
        }
        .padding(.bottom, 10)
        .onChange(of: pinnedExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarPinnedExpanded) }
        .onChange(of: chronoExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarChronoExpanded) }
        .onChange(of: noProjectExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarNoProjectExpanded) }
        .onChange(of: projectsExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarProjectsExpanded) }
        .onChange(of: archivedExpanded) { _, v in
            SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarArchivedExpanded)
            if v { Task { await appState.loadArchivedChats() } }
        }
        .onChange(of: toolsExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarToolsExpanded) }
        .task {
            if archivedExpanded { await appState.loadArchivedChats() }
        }
    }

    /// Sentinel token used inside `pinnedFilterDisabledRaw` to represent
    /// pinned chats with no associated project. Distinct from any UUID
    /// string so it can coexist with project ids in the same set.
    private static let pinnedFilterNoProjectToken = "__none__"

    private var pinnedFilterDisabled: Set<String> {
        let parts = pinnedFilterDisabledRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setPinnedFilterDisabled(_ next: Set<String>) {
        pinnedFilterDisabledRaw = next.sorted().joined(separator: ",")
    }

    /// Distinct buckets present across the loaded pinned chats: each
    /// project that has at least one pinned chat, plus a synthetic
    /// "no project" entry when any chat has `projectId == nil`. Sorted
    /// alphabetically so the popup is stable across renders.
    private func pinnedFilterSources(from pinned: [Chat]) -> [PinnedFilterSource] {
        var hasNoProject = false
        var projectIds: Set<UUID> = []
        for chat in pinned {
            if let pid = chat.projectId {
                projectIds.insert(pid)
            } else {
                hasNoProject = true
            }
        }
        let projectsById = Dictionary(uniqueKeysWithValues: appState.projects.map { ($0.id, $0) })
        var sources: [PinnedFilterSource] = projectIds.compactMap { id in
            guard let p = projectsById[id] else { return nil }
            return PinnedFilterSource(
                token: id.uuidString,
                label: p.name,
                isNoProject: false
            )
        }
        sources.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        if hasNoProject {
            sources.append(PinnedFilterSource(
                token: Self.pinnedFilterNoProjectToken,
                label: String(localized: "Without project", bundle: AppLocale.packageBundle),
                isNoProject: true
            ))
        }
        return sources
    }

    /// Drops chats whose source bucket is in the disabled set. Empty set
    /// short-circuits to the original list so the renderer's hot path
    /// stays cheap when no filter is active.
    private func applyPinnedFilter(to pinned: [Chat]) -> [Chat] {
        let disabled = effectiveDisabledTokens(
            pinnedFilterDisabled,
            sources: pinnedFilterSources(from: pinned)
        )
        guard !disabled.isEmpty else { return pinned }
        return pinned.filter { chat in
            if let pid = chat.projectId {
                return !disabled.contains(pid.uuidString)
            }
            return !disabled.contains(Self.pinnedFilterNoProjectToken)
        }
    }

    /// Tools the user has hidden via the filter popup. Stored as a
    /// comma-separated string of catalog ids inside
    /// `toolsHiddenRaw` so the existing `SidebarPrefs` UserDefaults
    /// suite holds it without a custom codec.
    private var toolsHidden: Set<String> {
        let parts = toolsHiddenRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setToolsHidden(_ next: Set<String>) {
        toolsHiddenRaw = next.sorted().joined(separator: ",")
    }

    /// Catalog entries laid out in the user's custom order. New tools
    /// (i.e. entries in the catalog whose id isn't in the saved order)
    /// append at the end in catalog order, so adding a new tool in a
    /// future release lands it predictably without erasing the user's
    /// arrangement of the existing ones.
    private var orderedTools: [SidebarToolEntry] {
        let saved = toolsOrderRaw.split(separator: ",").map(String.init)
        var seen: Set<String> = []
        var result: [SidebarToolEntry] = []
        for id in saved {
            guard !seen.contains(id), let entry = SidebarToolsCatalog.entry(byId: id) else { continue }
            result.append(entry)
            seen.insert(id)
        }
        for entry in SidebarToolsCatalog.entries where !seen.contains(entry.id) {
            result.append(entry)
        }
        return result
    }

    private var visibleTools: [SidebarToolEntry] {
        let hidden = toolsHidden
        return orderedTools.filter { entry in
            if hidden.contains(entry.id) { return false }
            if let feature = SidebarToolsCatalog.gatedFeature(for: entry.id),
               !flags.isVisible(feature) {
                return false
            }
            return true
        }
    }

    /// Persists a reorder of the tools list. `beforeId == nil` drops the
    /// tool at the end. Operates on the FULL ordered list (including
    /// hidden tools) so toggling a tool's visibility doesn't lose its
    /// position in the user's arrangement.
    fileprivate func reorderTools(toolId: String, beforeId: String?) {
        var current = orderedTools.map(\.id)
        current.removeAll { $0 == toolId }
        if let beforeId, let idx = current.firstIndex(of: beforeId) {
            current.insert(toolId, at: idx)
        } else {
            current.append(toolId)
        }
        toolsOrderRaw = current.joined(separator: ",")
    }

    /// Funnel button anchoring `ToolsFilterPopup`. Mirrors
    /// `pinnedFilterButton` so both filter affordances share the same
    /// visual language and animation.
    private var toolsFilterButton: some View {
        HeaderHoverIcon(tooltip: "Show or hide tools") {
            toolsFilterMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: ToolsFilterAnchorKey.self, value: .bounds) { anchor in
            toolsFilterMenuOpen ? anchor : nil
        }
    }

    /// Funnel button anchoring `PinnedFilterPopup`. Same icon shape as
    /// the `Organize` button on Projects/All chats so the two filter
    /// affordances share the same visual language across the sidebar.
    private var pinnedFilterButton: some View {
        HeaderHoverIcon(tooltip: "Filter pinned by project") {
            pinnedFilterMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: PinnedFilterAnchorKey.self, value: .bounds) { anchor in
            pinnedFilterMenuOpen ? anchor : nil
        }
    }

    private var chronoFilterDisabled: Set<String> {
        let parts = chronoFilterDisabledRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setChronoFilterDisabled(_ next: Set<String>) {
        chronoFilterDisabledRaw = next.sorted().joined(separator: ",")
    }

    /// Mirrors `pinnedFilterSources(from:)` for the chronological list:
    /// distinct project buckets present plus an optional "no project"
    /// entry, sorted alphabetically.
    private func chronoFilterSources(from chrono: [Chat]) -> [PinnedFilterSource] {
        var hasNoProject = false
        var projectIds: Set<UUID> = []
        for chat in chrono {
            if let pid = chat.projectId {
                projectIds.insert(pid)
            } else {
                hasNoProject = true
            }
        }
        let projectsById = Dictionary(uniqueKeysWithValues: appState.projects.map { ($0.id, $0) })
        var sources: [PinnedFilterSource] = projectIds.compactMap { id in
            guard let p = projectsById[id] else { return nil }
            return PinnedFilterSource(
                token: id.uuidString,
                label: p.name,
                isNoProject: false
            )
        }
        sources.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        if hasNoProject {
            sources.append(PinnedFilterSource(
                token: Self.pinnedFilterNoProjectToken,
                label: String(localized: "Without project", bundle: AppLocale.packageBundle),
                isNoProject: true
            ))
        }
        return sources
    }

    private func applyChronoFilter(to chrono: [Chat]) -> [Chat] {
        let disabled = effectiveDisabledTokens(
            chronoFilterDisabled,
            sources: chronoFilterSources(from: chrono)
        )
        guard !disabled.isEmpty else { return chrono }
        return chrono.filter { chat in
            if let pid = chat.projectId {
                return !disabled.contains(pid.uuidString)
            }
            return !disabled.contains(Self.pinnedFilterNoProjectToken)
        }
    }

    private func effectiveDisabledTokens(_ disabled: Set<String>, sources: [PinnedFilterSource]) -> Set<String> {
        guard !disabled.isEmpty, !sources.isEmpty else { return disabled }
        let available = Set(sources.map(\.token))
        return available.isSubset(of: disabled) ? [] : disabled
    }

    /// Always-visible section so users learn that archived chats land
    /// here. Lazy-fetches the list the first time it's expanded; the
    /// runtime filter `archived: true` guarantees these chats never
    /// also appear in the pinned / project / chronological lists.
    @ViewBuilder
    private var archivedSection: some View {
        sectionHeader(
            "Archived",
            expanded: $archivedExpanded,
            leadingIcon: AnyView(ArchiveIcon(size: 16.5, lineWidth: 1.28))
        )
        SidebarAccordion(
            expanded: archivedExpanded,
            targetHeight: appState.archivedChats.isEmpty
                ? 26
                : SidebarRowMetrics.recentChats(count: appState.archivedChats.count)
                    + SidebarRowMetrics.sectionEdgePadding
        ) {
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                    if appState.archivedChats.isEmpty {
                        HStack(spacing: 6) {
                            if appState.archivedLoading {
                                SidebarChatRowSpinner()
                                    .frame(width: 9, height: 9)
                            }
                            Text(appState.archivedLoading ? "Loading…" : "No archived chats")
                                .font(BodyFont.system(size: 13.5, wght: 500))
                                .foregroundColor(Color(white: 0.40))
                        }
                        .padding(.leading, 34)
                        .padding(.vertical, 4)
                    } else {
                        let currentChatId = selectedChatId
                        ForEach(appState.archivedChats) { chat in
                            RecentChatRow(
                                chat: chat,
                                isSelected: currentChatId == chat.id,
                                leadingIcon: .unarchive,
                                archivedRow: true,
                                callbacks: recentChatCallbacks(for: chat, archived: true)
                            )
                            .equatable()
                        }
                    }
                }
                .padding(.leading, 8)
                if !appState.archivedChats.isEmpty {
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
            }
        }
    }

    /// Tools section: top-level entries to feature areas other than chat.
    /// The header is collapsible like the rest of the sidebar and exposes
    /// a per-tool visibility filter on hover (mirrors the Pinned section's
    /// funnel button). Rows are drag-reorderable; their order persists via
    /// `toolsOrderRaw`.
    @ViewBuilder
    private var toolsSection: some View {
        BasicSectionHeader(
            title: "Tools",
            expanded: $toolsExpanded,
            leadingIcon: AnyView(WrenchIcon(size: 16.5, lineWidth: 1.28)),
            trailingIcon: SidebarToolsCatalog.entries.count >= 2 ? AnyView(toolsFilterButton) : nil,
            trailingForceVisible: toolsFilterMenuOpen
        )
        SidebarAccordion(
            expanded: toolsExpanded,
            targetHeight: visibleTools.isEmpty
                ? 26 + SidebarRowMetrics.sectionEdgePadding
                : CGFloat(visibleTools.count) * ToolsReorderableList.rowSlotHeight
                    + SidebarRowMetrics.sectionEdgePadding
        ) {
            toolsAccordionContent
        }
    }

    @ViewBuilder
    private var toolsAccordionContent: some View {
        let visible = visibleTools
        if visible.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("No tools visible")
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(Color(white: 0.40))
                    .padding(.leading, 34)
                    .padding(.vertical, 4)
                Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
            }
        } else {
            ToolsReorderableList(
                tools: visible,
                selectedRoute: appState.currentRoute,
                onSelect: { route in appState.navigate(to: route) },
                onReorder: { toolId, beforeId in
                    reorderTools(toolId: toolId, beforeId: beforeId)
                }
            )
            .padding(.leading, 8)
        }
    }

    var body: some View {
        RenderProbe.tick("SidebarView")
        let sidebarSnapshot = makeSnapshot()
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                // Top nav: new chat, search.
                // Plugins and automations rows kept commented out for now.
                VStack(spacing: 1) {
                    SidebarButton(title: "New chat",
                                  icon: "square.and.pencil",
                                  customShape: AnyShape(ComposeIcon()),
                                  customShapeSize: 12.8,
                                  customShapeStroke: 1.25,
                                  route: .home,
                                  actionOnly: true,
                                  shortcut: "⌘N")
                    SidebarButton(title: "Search",
                                  icon: "magnifyingglass",
                                  customShape: AnyShape(SearchIconShape()),
                                  customShapeSize: 13.8,
                                  customShapeStroke: 1.65,
                                  route: .search,
                                  shortcut: "⌘G")
                    if flags.isVisible(.skills) {
                        SidebarButton(title: "Skills",
                                      icon: "wand.and.stars",
                                      route: .skills,
                                      shortcut: "⌘⇧K")
                    }
                    /*
                    SidebarButton(title: "Plugins",
                                  icon: "circle.grid.2x2",
                                  route: .plugins,
                                  shortcut: "⌘⇧E")
                    SidebarButton(title: "Automations",
                                  icon: "clock",
                                  route: .automations,
                                  shortcut: "⌘⇧A")
                    */
                }
                .padding(.leading, 6)
                .padding(.trailing, 22)
                .padding(.top, 6)

                // Legacy mode reserves the scroller's 14pt column outside
                // the clipView, so the gutter only needs the small breathing
                // strip between content and that column.
                ThinScrollView(trailingGutter: 4) {
                    sidebarScrollContent(snapshot: sidebarSnapshot)
                        .background(SidebarScrollStateInstaller().allowsHitTesting(false))
                }

                // Settings button at bottom (toggles account popover above it)
                SettingsBottomButton(open: $settingsPopoverOpen)
                    .padding(.leading, 6)
                    .padding(.trailing, 22)
                    .padding(.bottom, 10)
                    .padding(.top, 6)
            }
            .frame(maxHeight: .infinity)

            // Account popover floats above the settings button
            if settingsPopoverOpen {
                SettingsAccountPopover(isOpen: $settingsPopoverOpen)
                    .background(MenuOutsideClickWatcher(isPresented: $settingsPopoverOpen))
                    .padding(.leading, 6)
                    .padding(.bottom, 50)
                    .transition(.softNudgeSymmetric(y: 4))
            }
        }
        .animation(.easeOut(duration: 0.20), value: settingsPopoverOpen)
        .onChange(of: appState.currentRoute) { _, _ in
            settingsPopoverOpen = false
        }
        .sheet(item: $projectEditor) { ctx in
            ProjectEditorSheet(context: ctx) { projectEditor = nil }
                .environmentObject(appState)
        }
        .sheet(item: $projectRenameTarget) { project in
            ProjectRenameSheet(project: project) { projectRenameTarget = nil }
                .environmentObject(appState)
        }
        .overlayPreferenceValue(OrganizeMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if organizeMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = OrganizeMenuPopup.mainColumnWidth
                    let chronoSources = chronoFilterSources(from: sidebarSnapshot.chrono)
                    let chronoDisabled = effectiveDisabledTokens(chronoFilterDisabled, sources: chronoSources)
                    OrganizeMenuPopup(
                        isPresented: $organizeMenuOpen,
                        viewModeRaw: $viewModeRaw,
                        projectSortModeRaw: $projectSortModeRaw,
                        chronoFilterSources: chronoSources,
                        chronoFilterDisabled: chronoDisabled,
                        toggleChronoFilter: { token in
                            var next = chronoFilterDisabled
                            if next.contains(token) {
                                next.remove(token)
                            } else {
                                next.insert(token)
                            }
                            setChronoFilterDisabled(next)
                        },
                        showAllChronoFilter: { setChronoFilterDisabled([]) },
                        hideAllChronoFilter: {
                            setChronoFilterDisabled(Set(chronoSources.map { $0.token }))
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(organizeMenuOpen)
            .animation(MenuStyle.openAnimation, value: organizeMenuOpen)
        }
        .overlayPreferenceValue(NewProjectAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if newProjectMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    NewProjectPopup(
                        isPresented: $newProjectMenuOpen,
                        onBlank: {
                            newProjectMenuOpen = false
                            startBlankProject()
                        },
                        onPickFolder: {
                            newProjectMenuOpen = false
                            createProjectFromFolder()
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(newProjectMenuOpen)
            .animation(MenuStyle.openAnimation, value: newProjectMenuOpen)
        }
        .overlayPreferenceValue(ProjectMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let openId = projectMenuOpenId,
                   let project = appState.projects.first(where: { $0.id == openId }),
                   let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 268
                    ProjectRowMenuPopup(
                        project: project,
                        isCodexSourced: appState.isCodexSourcedProject(path: project.path),
                        isPresented: Binding(
                            get: { projectMenuOpenId == project.id },
                            set: { if !$0 { projectMenuOpenId = nil } }
                        ),
                        onOpenInFinder: {
                            let path = (project.path as NSString).expandingTildeInPath
                            if !path.isEmpty,
                               FileManager.default.fileExists(atPath: path) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                            projectMenuOpenId = nil
                        },
                        onRename: {
                            projectMenuOpenId = nil
                            projectRenameTarget = project
                        },
                        onArchive: {
                            projectMenuOpenId = nil
                        },
                        onRemove: {
                            projectMenuOpenId = nil
                            appState.deleteProject(project.id)
                        },
                        onHide: {
                            projectMenuOpenId = nil
                            appState.hideCodexRoot(path: project.path)
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing(offset: 4),
                        gap: 4
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(projectMenuOpenId != nil)
            .animation(MenuStyle.openAnimation, value: projectMenuOpenId)
        }
        .overlayPreferenceValue(PinnedFilterAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if pinnedFilterMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    let sources = pinnedFilterSources(from: sidebarSnapshot.pinned)
                    let disabled = effectiveDisabledTokens(pinnedFilterDisabled, sources: sources)
                    PinnedFilterPopup(
                        isPresented: $pinnedFilterMenuOpen,
                        sources: sources,
                        disabled: disabled,
                        toggle: { token in
                            var next = pinnedFilterDisabled
                            if next.contains(token) {
                                next.remove(token)
                            } else {
                                next.insert(token)
                            }
                            setPinnedFilterDisabled(next)
                        },
                        showAll: { setPinnedFilterDisabled([]) },
                        hideAll: { setPinnedFilterDisabled(Set(sources.map { $0.token })) }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(pinnedFilterMenuOpen)
            .animation(MenuStyle.openAnimation, value: pinnedFilterMenuOpen)
        }
        .overlayPreferenceValue(ToolsFilterAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if toolsFilterMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    let allIds = SidebarToolsCatalog.entries.map(\.id)
                    ToolsFilterPopup(
                        isPresented: $toolsFilterMenuOpen,
                        entries: orderedTools,
                        hidden: toolsHidden,
                        toggle: { id in
                            var next = toolsHidden
                            if next.contains(id) {
                                next.remove(id)
                            } else {
                                next.insert(id)
                            }
                            setToolsHidden(next)
                        },
                        showAll: { setToolsHidden([]) },
                        hideAll: { setToolsHidden(Set(allIds)) }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(toolsFilterMenuOpen)
            .animation(MenuStyle.openAnimation, value: toolsFilterMenuOpen)
        }
    }

    private func sectionHeader(
        _ title: LocalizedStringKey,
        expanded: Binding<Bool>,
        leadingIcon: AnyView? = nil
    ) -> some View {
        BasicSectionHeader(title: title, expanded: expanded, leadingIcon: leadingIcon)
    }

    private var projectsHeader: some View {
        sidebarHeader(title: "Projects",
                      showCollapseAll: true,
                      showNewChat: false,
                      leadingIcon: AnyView(FolderMorphIcon(size: 14.5, progress: 0, lineWidthScale: 1.027)),
                      expanded: $projectsExpanded)
    }

    private var chronoHeader: some View {
        sidebarHeader(title: "All chats",
                      showCollapseAll: false,
                      showAddProject: false,
                      showNewChat: false,
                      leadingIcon: AnyView(
                          LucideIcon(.messageCircle, size: 13)
                      ),
                      expanded: $chronoExpanded)
    }

    @ViewBuilder
    private func sidebarHeader(
        title: LocalizedStringKey,
        showCollapseAll: Bool,
        showAddProject: Bool = true,
        showNewChat: Bool,
        alwaysShow: Bool = false,
        leadingIcon: AnyView? = nil,
        expanded: Binding<Bool>? = nil
    ) -> some View {
        // Fixed-height header. Icons are always laid out (so the row never
        // changes height) and toggled with opacity + hit-testing only.
        // Tapping outside the icon group toggles the section's collapsed
        // state, which is why the whole row is a `.contentShape(Rectangle())`
        // with `.onTapGesture`. Inner icon buttons absorb their own clicks
        // because SwiftUI prefers the innermost gesture handler.
        let iconsVisible = alwaysShow || projectsHeaderHovered || newProjectMenuOpen || organizeMenuOpen
        let toggle: () -> Void = {
            guard let expanded else { return }
            withAnimation(SidebarSection.toggleAnimation) { expanded.wrappedValue.toggle() }
        }
        // Each action icon is laid out in a 22pt slot with 2pt spacing.
        // `organize` is always present; the others are gated by their flags.
        let iconCount = (showCollapseAll ? 1 : 0) + 1 + (showAddProject ? 1 : 0) + (showNewChat ? 1 : 0)
        let iconsWidth = CGFloat(iconCount) * 22 + CGFloat(max(iconCount - 1, 0)) * 2
        // Trailing clearance leaves a 6pt visual gap between the right
        // hairline and the leading edge of the icon group when hovered.
        let trailingClearance: CGFloat = iconsWidth + 6
        HStack(spacing: 4) {
            if let expanded {
                CollapsibleSectionLabel(title: title,
                                        expanded: expanded.wrappedValue,
                                        hovered: projectsHeaderHovered,
                                        trailingIconsActive: iconsVisible,
                                        chevronLeadingPadding: 2,
                                        leadingIcon: leadingIcon,
                                        trailingIconsClearance: trailingClearance)
            } else {
                HStack(spacing: 0) {
                    if let leadingIcon {
                        leadingIcon
                            .foregroundColor(Color(white: 0.78))
                            .frame(width: 15, height: 15, alignment: .center)
                            .padding(.trailing, 11)
                    }
                    Text(title)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color(white: 0.92))
                }
                Spacer()
            }
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded != nil { toggle() }
        }
        // Action icons live as a trailing overlay so they don't reserve
        // layout space when invisible: the right hairline inside the
        // label fills the row to its trailing edge, then animates a
        // trailing inset on hover to clear the icons that fade in.
        // Each icon fades in with its own staggered delay so the group
        // cascades after the chevron; on hover-out they all clear at
        // once via the disappear branch of `hoverStaggerFade`.
        .overlay(alignment: .trailing) {
            let firstDelay = SidebarSection.trailingIconsFirstDelay
            let stagger = SidebarSection.trailingIconsStagger
            let collapseAllDelay = firstDelay
            let organizeSlot = (showCollapseAll ? 1 : 0)
            let newProjectSlot = organizeSlot + 1
            let newChatSlot = newProjectSlot + (showAddProject ? 1 : 0)
            let organizeDelay = firstDelay + Double(organizeSlot) * stagger
            let newProjectDelay = firstDelay + Double(newProjectSlot) * stagger
            let newChatDelay = firstDelay + Double(newChatSlot) * stagger
            HStack(spacing: 2) {
                if showCollapseAll {
                    let allCollapsed = expandedProjects.isEmpty
                    HeaderHoverIcon(
                        tooltip: allCollapsed ? "Expand all" : "Collapse all"
                    ) {
                        toggleAllProjectsCollapsed()
                    } label: { color in
                        CornerBracketsIcon(
                            size: 12,
                            variant: allCollapsed ? .expanded : .collapsed,
                            lineWidth: 1.4
                        )
                        .foregroundColor(color)
                        .frame(width: 22, height: 22)
                    }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: collapseAllDelay)
                }
                organizeButton
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: organizeDelay)
                if showAddProject {
                    HeaderHoverIcon(tooltip: "Add new project") {
                        newProjectMenuOpen.toggle()
                    } label: { color in
                        FolderAddIcon(size: 15.5, plusStrokeWidth: 1.4)
                            .foregroundColor(color)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .anchorPreference(key: NewProjectAnchorKey.self, value: .bounds) { $0 }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: newProjectDelay)
                }
                if showNewChat {
                    HeaderHoverIcon(tooltip: "New chat") {
                        appState.currentRoute = .home
                    } label: { color in
                        ComposeIcon()
                            .stroke(color,
                                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
                            .frame(width: 11.2, height: 11.2)
                            .frame(width: 22, height: 22)
                    }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: newChatDelay)
                }
            }
            .disabled(!iconsVisible)
        }
    }

    /// Funnel button that anchors `OrganizeMenuPopup` and uses the
    /// project-wide dropdown chrome.
    private var organizeButton: some View {
        HeaderHoverIcon(tooltip: "Filter, sort, and organize chats") {
            organizeMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: OrganizeMenuAnchorKey.self, value: .bounds) { anchor in
            organizeMenuOpen ? anchor : nil
        }
    }

    // MARK: - Header actions

    private func toggleAllProjectsCollapsed() {
        withAnimation(.easeOut(duration: 0.28)) {
            if expandedProjects.isEmpty {
                // Expand all
                expandedProjects = Set(appState.projects.map { $0.id })
                for project in appState.projects {
                    Task { await appState.loadThreadsForProject(project) }
                }
            } else {
                expandedProjects.removeAll()
            }
        }
    }

    private func startBlankProject() {
        let project = appState.createProject(
            name: String(localized: "New project", bundle: AppLocale.packageBundle),
            path: ""
        )
        appState.selectedProject = project
        appState.currentRoute = .home
        expandedProjects.insert(project.id)
    }

    private func createProjectFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Select", bundle: AppLocale.packageBundle)
        if panel.runModal() == .OK, let url = panel.url {
            let project = appState.createProject(
                name: url.lastPathComponent,
                path: url.path
            )
            appState.selectedProject = project
            appState.currentRoute = .home
            expandedProjects.insert(project.id)
        }
    }
}


// MARK: - New project popup (start blank / use existing folder)


// MARK: - Settings bottom button (opens account popover above it)


// MARK: - Settings account popover (anchored above the settings button)


// MARK: - Usage limits section

/// Toggleable section for usage limits inside the account popover. Default
/// collapsed; the chevron toggles visibility instantly via SwiftUI's
/// conditional rendering (no height measurement, so it works regardless
/// of when `appState.rateLimits` lands relative to the popover opening).
/// Reads `appState.rateLimits`, which the backend populates via
/// `account/rateLimits/read` at boot and refreshes through
/// `account/rateLimits/updated`.


// MARK: - SidebarButton


// MARK: - ComposeIcon


// MARK: - SectionDisclosureChevron

/// Tunables for collapsible sidebar sections. The chevron rotation and
/// section height share the same spring so the disclosure feels like a
/// single physical gesture.

/// Hover fade with an optional delay only on appear; on disappear the
/// fade is immediate so a group of staggered icons clears at once.


/// Disclosure chevron used by collapsible sidebar section headers
/// (Pinned, All chats, No project, Projects). Rotates with its own
/// spring curve so the rotation reads as physical even when the caller
/// uses a different animation for layout. The hover-brightening is
/// driven from `CollapsibleSectionLabel`, so the title and chevron
/// share one hover region instead of lighting up independently.

/// Title + chevron pair used by collapsible sidebar section headers.
/// Owns one hover state so the label and chevron brighten together,
/// matching the dim/brighten treatment of the header action icons.
/// Optional `leadingIcon` mirrors the icon column of the top sidebar
/// buttons (`New chat`, `Search`); when supplied, a 14x14 slot is laid
/// out before the title so headers visually rhyme with those rows.

/// Collapsible section header used for Pinned, "Chats with no project",
/// Archived, and Tools. Owns its own row-wide hover so the label, chevron
/// and hairlines all light up together when the cursor enters anywhere
/// inside the row, including the hairline tails — not just the inner
/// text+chevron region.
///
/// Optionally renders a single trailing hover icon (used by Pinned for
/// the per-project filter funnel). The icon shares the staggered fade
/// timing of the project header's icon group so the two filter
/// affordances feel like the same control across the sidebar.

/// Hairline that flanks an expanded section title (left + right). Sits
/// vertically centered with the text and grows outward from the word so
/// the open state reads as a labeled separator. `anchor` controls the
/// scale origin: `.trailing` for the left hairline (grows leftward away
/// from the title), `.leading` for the right hairline. Fade-in matches
/// the section expand timing.

// MARK: - PinnedIcon

/// Sidebar header icon button that dims by default and brightens on hover,
/// mirroring the `PinIcon` pattern used in chat rows.


// MARK: - RecentChatRow (runtime-backed chats)


/// Action callbacks the row needs but doesn't own. Held externally so the
/// row can drop `@EnvironmentObject var appState` and become `Equatable`:
/// SwiftUI then short-circuits body re-evaluation when nothing in the row's
/// data inputs changed, even if some other slice of `AppState` did. Each
/// callback captures `appState` (and the chat id) at construction time on
/// the parent side; the parent rebuilds them on demand whenever the row
/// re-evaluates.

/// Free-function factory: kept out of `SidebarView` so other sidebar
/// containers (e.g. `PinnedReorderableList`) can build the same callbacks
/// from their own `appState` reference without reaching back into the
/// outer view.
@MainActor
func makeRecentChatCallbacks(appState: AppState, chat: Chat, archived: Bool) -> RecentChatRowCallbacks {
    let chatId = chat.id
    let chatSnapshot = chat
    return RecentChatRowCallbacks(
        onSelect: { appState.navigate(to: .chat(chatId)) },
        onArchive: { appState.archiveChat(chatId: chatId) },
        onUnarchive: { appState.unarchiveChat(chatId: chatId) },
        onTogglePin: { appState.togglePin(chatId: chatId) },
        onRename: { appState.pendingRenameChat = chatSnapshot },
        onToggleUnread: { appState.toggleChatUnread(chatId: chatId) },
        onOpenInFinder: {
            guard let cwd = chatSnapshot.cwd, !cwd.isEmpty else { return }
            let path = (cwd as NSString).expandingTildeInPath
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        },
        onCopyWorkingDirectory: {
            guard let cwd = chatSnapshot.cwd, !cwd.isEmpty else { return }
            copySidebarStringToPasteboard(cwd)
        },
        onCopySessionId: {
            guard let id = chatSnapshot.clawixThreadId else { return }
            copySidebarStringToPasteboard(id)
        },
        onCopyDeeplink: {
            guard let id = chatSnapshot.clawixThreadId else { return }
            copySidebarStringToPasteboard("clawix://session/\(id)")
        },
        onForkLocal: {
            _ = appState.forkConversation(chatId: chatId, sourceSnapshot: chatSnapshot)
        },
        onContextMenu: { screenPoint in
            SidebarChatContextMenuPanel.present(
                at: screenPoint,
                chat: chatSnapshot,
                isArchived: archived,
                appState: appState
            )
        }
    )
}

func copySidebarStringToPasteboard(_ value: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(value, forType: .string)
}


/// Quiet thin ring used in chat rows while a turn is in flight. Replaces the
/// default `ProgressView` so the rotation stays slow and the stroke matches
/// the rest of the sidebar's restrained line work.

// MARK: - ProjectAccordion


/// Footer label appended to a `ProjectAccordion`'s chat list to
/// trigger "Show more" (5 → 10) or "View all" (open the per-project
/// popup). Reads as plain text, not a row: no hover background, no
/// rounded "tab" look. Hover animates the text a notch toward white
/// (still well short of the chat title's 0.94) so the user gets a
/// subtle "this is interactive" hint without it competing with the
/// conversation rows above. The trailing whitespace gives the next
/// project's header a little breathing room.

/// Animated vertical reveal driven by an explicit `targetHeight`. We
/// learned the hard way that `GeometryReader` based measurement misfires
/// when the container is clipped to 0, leaving content invisible. So
/// callers compute the natural height from their content (e.g. row count
/// times row height) and we just animate `frame(height:)` between 0 and
/// that target. `.fixedSize(vertical:)` keeps the content rendered at
/// its true intrinsic height so a slightly off estimate clips a few
/// pixels rather than collapsing rows.

/// Heights used for accordion target-height math. Keep these tight to
/// the actual rendered values so the animation lands cleanly. Re-measure
/// if you change row paddings or fonts.

/// Single-transaction accordion: the frame's height is bound directly
/// to `expanded` and animated via `.animation(_:value:)` so it rides the
/// same render pass as the header's icon-opacity and chevron-rotation
/// animations. An earlier `@State displayHeight` updated from `.onChange`
/// inside its own `withAnimation` ran one frame after the header's
/// animations kicked off, so the icon/chevron faded first while the
/// height stayed at 0 — visually the header looked like it drifted and
/// the chats arrived late "from below" once the second transaction caught
/// up.
///
/// `targetHeight` is a heuristic (row count × estimated row height +
/// section padding) that lands the open-state geometry on the same
/// transaction as the header. A `GeometryReader` measures the actual
/// intrinsic content height and we take `max(targetHeight, measuredHeight)`
/// so the floor is always the real content size. Without this, line-height
/// drift between the heuristic and the rendered text (Archived at 15+ rows)
/// clipped the last row because `.clipped()` honours `targetHeight`, not
/// intrinsic height.
///
/// `measuredHeight` follows the content size in both directions. An earlier
/// version only ratcheted up (`if newH > measuredHeight`), which left a
/// stale tall frame after rows were removed (unpinning, moving a chat into
/// a folder) — the section "remembered" its old maximum height and the
/// gap stayed open until something forced a re-measurement.


/// Animated vertical reveal: a hidden twin always renders at its intrinsic
/// height to drive `measuredHeight`, the visible tree renders at full
/// opacity, and only the outer frame animates between 0 and the measured
/// height. Reveal direction comes from the clip alone (top-to-bottom on
/// open, bottom-to-top on close) so it matches the cadence of the simpler
/// `SidebarAccordion`-driven sections like Archived.


// MARK: - PinnedRow


// MARK: - Project row dropdown menu


// MARK: - Organize / Sort menu (funnel button next to the projects header)


/// Three-section dropdown: top-level view mode (Grouped vs Chronological),
/// project sort field (only when grouped), and a `Filter > By project`
/// submenu (only when chronological). The filter row mirrors the
/// hover-reveals-side-panel pattern used in the composer's model picker
/// (`ModelMenuPopup`): hovering the chevron spawns a column to the right
/// with the project filter list, so this popup remains the single entry
/// point for organizing the chat list. Selections persist via the
/// caller's `@AppStorage`-backed bindings; the side panel's per-project
/// toggles flow through the `chronoFilter*` callbacks.


/// Row variant of `OrganizeMenuRow` that ends in a chevron and stays
/// highlighted while its companion side panel is open. Mirrors the
/// chevron row styling used by `ModelMenuChevronRow` in the composer's
/// model picker so the two cascading menus read as the same family.

// MARK: - Pinned filter

/// Distinct buckets present across the loaded pinned chats: each project
/// that has at least one pinned chat, plus a synthetic "no project"
/// entry when any chat has `projectId == nil`. Lives at file scope so
/// the popup type below can name it as a concrete parameter.


/// Per-project visibility filter for the Pinned section. Each row maps
/// to one bucket present across the user's pinned chats (a project, or
/// the synthetic "no project" entry). Toggling a row flips its inclusion
/// in the visible list. The popup also exposes a "Show all" shortcut at
/// the bottom that wipes the entire disabled set in one click — the
/// recovery path when the user filtered down to "nothing visible" and
/// can no longer find the chats they pinned earlier.

/// Toggleable row inside `PinnedFilterPopup`. Active state is shown with
/// a check on the trailing edge and the icon + label rendered at full
/// brightness; inactive rows fade their label and icon so the disabled
/// state reads at a glance even without hovering.

/// Footer row inside `PinnedFilterPopup` for "Show all" / "Hide all"
/// shortcuts. Same hover styling as the toggleable project rows so the
/// footer reads as part of the same list, just with a divider above it.

// MARK: - Drag-and-drop helper

/// Wraps any sidebar row in a drop target that accepts a `Chat.id` UUID
/// carried as plain text by `RecentChatRow`'s `.onDrag`. Renders a soft
/// inset highlight while a drag hovers the wrapper, matching the row /
/// menu hover language used elsewhere in the app.
///
/// `accept` returns whether the drop was actually meaningful (e.g. drop
/// onto a row's own source is rejected) so we don't pretend to handle
/// no-ops.

/// Custom delegate so we can reject project reorder drags before SwiftUI
/// flips `isTargeted`. Project drags carry a `public.url` representation
/// (`clawix-project://<UUID>`); `NSPasteboard` may auto-promote URLs to
/// `public.utf8-plain-text`, so the closure-based `.onDrop(of: [.text])`
/// would otherwise highlight project rows as if they were valid chat
/// drop targets.

// MARK: - Pinned reorderable list

/// Pinned-section list with intra-list drag reordering. The design
/// optimises for stability of the visual feedback during the drag and
/// for an instant, flicker-free placement on drop:
///
/// - On drag start the source row collapses (frame 0, opacity 0) AND the
///   gap is opened at the source's own slot, so the total list height
///   stays constant from frame zero. As the cursor moves to a different
///   slot, only the gap migrates: the list never grows or shrinks.
/// - Each slot zone is one contiguous drop target that includes the gap
///   above the row plus the row itself. Adjacent slot zones touch with
///   no dead band, so moving the cursor between rows can never land in a
///   "no drop target" sliver and bounce the gap off.
/// - `dropExited` does not clear the gap immediately. It schedules a
///   cancelable task; if the next slot's `dropEntered` fires before the
///   delay, the clear is cancelled. If the cursor truly left the list,
///   the gap reverts to the source's own slot (internal drag) or closes
///   (external drag). No flicker between adjacent slots.
/// - `performDrop` applies `reorderPinned` AND clears `draggingId` /
///   `targetIndex` inside a `Transaction(animation: nil)` so the row
///   simply renders at its new index in the next pass. Nothing animates,
///   nothing crossfades, the placement is atomic.
///
/// External drags (e.g. a chat dragged in from a project) are accepted
/// too: the gap opens where it will land, and `reorderPinned` pins it
/// at that position on drop.
/// Mutable bag for per-row window-coord frames. Used at drag-start to
/// anchor the chip relative to the cursor. Stored on a reference type
/// (mutated via `byId = ...`) so the per-frame `onPreferenceChange`
/// writes don't go through `@State` and therefore don't invalidate
/// SwiftUI on every layout pass — the streaming chat publish flood was
/// otherwise running this loop dozens of times per second for nothing.


// MARK: - Pinned drag auto-scroll

/// Weak handle to the surrounding `NSScrollView`. Populated by
/// `EnclosingScrollViewLocator` once SwiftUI drops the locator into
/// the AppKit hierarchy; consumed by `PinnedDragAutoScroller` while a
/// pinned-row drag is active so it can nudge the scroller without
/// going through SwiftUI bindings.
/// Walks up its AppKit superview chain to find the nearest enclosing
/// `NSScrollView` and stashes a weak reference in `box`. Mirrors the
/// trick `ThinScrollerInstaller` uses, but exposes the scroll view to
/// SwiftUI code that needs to drive scrolling imperatively (e.g. the
/// pinned-list drag auto-scroll).

/// 60Hz auto-scroll driver active during a pinned-row drag. Polls
/// `NSEvent.mouseLocation` (still queryable while AppKit's drag
/// session owns the event stream, same trick `DragChipPanel` uses);
/// when the cursor sits inside the top or bottom edge zone of the
/// surrounding scroll view's visible rect, scrolls in that direction
/// with a speed that ramps up the closer the cursor is to the edge.
/// SwiftUI's `.onDrop` keeps firing against whatever slot zone is now
/// under the cursor, so the gap follows the new content and the user
/// can drop on rows that started off screen.
// MARK: - Window-drag inhibitor

/// SwiftUI helper that drops a real NSView into the row, just so AppKit
/// has something whose `mouseDownCanMoveWindow` returns `false` to find at
/// the click point. Without this, the window's `isMovableByWindowBackground
/// = true` setting (see `App.swift`) causes mouseDown on a row to start a
/// window drag instead of letting SwiftUI's `.onDrag` initiate the chat
/// drag-and-drop.
///
/// We DO want the view to participate in hit-testing (otherwise AppKit
/// falls through to the SwiftUI host, which doesn't override
/// `mouseDownCanMoveWindow`). We just don't want to consume the click:
/// `mouseDown` is forwarded to the next responder so SwiftUI's gesture
/// recognizers (`.onTapGesture`, `.onDrag`) on the parent SwiftUI host
/// still fire normally.
/// Three stacked horizontal bars with a steep length progression
/// (100% / ~58% / ~29%) used as the "organize / filter chats" affordance in
/// the sidebar header. Replaces SF Symbol `line.3.horizontal.decrease`, whose
/// progression was too gentle to read as a hierarchy at this size.


/// Counterpart to `WindowDragInhibitor`: a transparent NSView whose only
/// job is to return `mouseDownCanMoveWindow = true`. Painted under the top
/// chrome strip so the user can grab and move the window from anywhere in
/// that band, even though `isMovableByWindowBackground` is off everywhere
/// else. Buttons inside the strip keep working: AppKit's hit test finds
/// the NSButton (or other control) on top of this view, and controls
/// return `false` from `mouseDownCanMoveWindow` by default.

// MARK: - DragChipPanel

/// Borderless `NSPanel` that shows a SwiftUI chip following the cursor
/// during a pinned-row drag. We hand macOS's drag preview a 1pt
/// transparent view (so the system's ~500ms settle animation has nothing
/// visible to fade) and render the user-facing chip ourselves here so we
/// can hide it the instant the drop lands. A 60Hz timer polls
/// `NSEvent.mouseLocation`; that is queryable even while AppKit's drag
/// session owns the event stream and `NSEvent.addLocalMonitorForEvents`
/// is silenced.
/// Bubbles each pinned row's frame (window coords, top-left origin) up
/// so `PinnedReorderableList` can compute the cursor's offset within
/// the row at drag start. The chip rendered in `DragChipPanel` uses
/// that offset to anchor the cursor to the same point of the chip the
/// user originally clicked.

/// Visual content of the drag chip. Mirrors a hovered `RecentChatRow`
/// (pin icon + title + archive icon) so the user reads it as the exact
/// line they just picked up. Width is the row's measured width, padding
/// and corner radius mirror `RecentChatRow.body`, and the background
/// pairs the sidebar's `VisualEffectBlur` with the same hover overlay
/// (`Color.white.opacity(0.035)`) so the chip composites against the
/// desktop the same way the row composites against the sidebar.
/// No stroke; any extra outline shifts the perceived width away from
/// the row underneath.

// MARK: - Project drag-reorder ("Custom" sort mode)

/// Visual content of the project drag chip. Mirrors the project header
/// row (folder icon + name) so the user reads it as the same line they
/// just picked up. Same chrome as `DragChipView` so chat and project
/// chips composite identically over the desktop background.

/// Bubbles each project row's frame (window coords, top-left origin)
/// up so `ProjectReorderableList` can compute the cursor's offset
/// within the row at drag start (mirrors `PinnedRowFrameKey`).

/// Reference-type bag for per-row frames. Same trick as
/// `PinnedRowFrameStore`: mutating `byId` doesn't go through `@State`
/// so the per-frame preference firehose during accordion expansion
/// doesn't invalidate SwiftUI on every layout pass.

/// File-private constant outside the generic type — Swift forbids
/// static stored properties on generic types.
let projectReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Wraps the projects ForEach with custom drag-reorder. Active only when
/// `projectSortMode == .custom`; in other modes the parent renders the
/// rows directly so dragging is impossible (it would conflict with the
/// computed sort). Mirrors `PinnedReorderableList`'s structure: gap
/// placeholders between rows, a borderless `DragChipPanel` that follows
/// the cursor, and edge auto-scroll via `PinnedDragAutoScroller`.


/// `clawix-project://<UUID>` puts the UUID in the host slot. macOS
/// canonicalises hostnames to lowercase, but `UUID(uuidString:)` is
/// case-insensitive. Falls back to the first path component for the
/// (rare) case where the URL parser stripped the host.
func projectId(from url: URL) -> UUID? {
    if let host = url.host, let uuid = UUID(uuidString: host) {
        return uuid
    }
    let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return UUID(uuidString: trimmed)
}

// MARK: - Tools section: filter popup + reorderable list


/// Popup that mirrors `PinnedFilterPopup` but operates on the static tools
/// catalog rather than per-project buckets. Each row toggles a tool's
/// presence in the sidebar list; the footer offers `Show all` / `Hide all`
/// shortcuts so the user can recover from "I hid everything" in one click.


// MARK: - Tools reorderable list

/// Bubbles each tool row's frame (window coords, top-left origin) up so
/// `ToolsReorderableList` can compute the cursor's offset within the row
/// at drag start (mirrors `ProjectRowFrameKey`, keyed by tool id rather
/// than UUID).


/// File-private constant outside the type so it stays consistent with
/// the existing `projectReorderMoveAnimation`.
let toolReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Drag-reorderable list for the Tools section. Mirrors the structure of
/// `ProjectReorderableList`: gap placeholders between rows, a borderless
/// `DragChipPanel` that follows the cursor while AppKit's drag preview
/// renders a 1pt transparent stand-in (no settle fade on drop). External
/// drags (chats, projects) are rejected because the drop delegate only
/// accepts the `clawix-tool` URL scheme.

/// Drop delegate scoped to the `clawix-tool://<id>` URL scheme so chat /
/// project drags never highlight tool slot zones.

/// Display-only tool row used inside `ToolsReorderableList`. Wraps
/// `SecretsToolRow` for the secrets entry and `DatabaseToolRow` for
/// everything else, so the visual treatment stays identical to the
/// pre-reorder design.

/// Mirror of `DatabaseToolRow` that renders the brand mark as the
/// row icon. Used by the `Agents` sidebar entry so the entrance point
/// for the agent-roster surface carries the Clawix identity.

/// Visual content of the tool drag chip. Matches the look of the row
/// underneath (icon + title) inside the same translucent capsule used by
/// `DragChipView` / `ProjectDragChipView` so chat, project and tool
/// chips composite identically over the desktop.
