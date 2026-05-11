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
private let clawixProjectURLScheme = "clawix-project"

/// Custom URL scheme used by tool rows in the sidebar's "Tools" section
/// when reordering. Same rationale as `clawixProjectURLScheme`: registering
/// the drag as `public.url` keeps it invisible to chat / project drop
/// targets, which match different schemes.
private let clawixToolURLScheme = "clawix-tool"

/// Catalog of every entry rendered in the sidebar's `Tools` section.
/// The IDs are stable strings (NOT route descriptions) so the user's
/// custom order persists even if a route's path changes; new tools added
/// in future releases simply append at the bottom of the saved order on
/// first launch.
fileprivate enum SidebarToolIcon: Equatable {
    case system(String)
    case secrets
}

fileprivate struct SidebarToolEntry: Identifiable, Equatable {
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

fileprivate enum SidebarToolsCatalog {
    static let entries: [SidebarToolEntry] = [
        SidebarToolEntry(id: "tasks",     title: "Tasks",     titleString: "Tasks",
                         icon: .system("checkmark.circle"),          route: .databaseCollection("tasks")),
        SidebarToolEntry(id: "goals",     title: "Goals",     titleString: "Goals",
                         icon: .system("flag"),                      route: .databaseCollection("goals")),
        SidebarToolEntry(id: "notes",     title: "Notes",     titleString: "Notes",
                         icon: .system("note.text"),                 route: .databaseCollection("notes")),
        SidebarToolEntry(id: "calendar",  title: "Calendar",  titleString: "Calendar",
                         icon: .system("calendar"),                  route: .calendarHome),
        SidebarToolEntry(id: "projects",  title: "Projects",  titleString: "Projects",
                         icon: .system("square.stack.3d.up"),        route: .databaseCollection("projects")),
        SidebarToolEntry(id: "secrets",   title: "Secrets",   titleString: "Secrets",
                         icon: .secrets,                             route: .secretsHome),
        SidebarToolEntry(id: "memory",    title: "Memory",    titleString: "Memory",
                         icon: .system("brain"),                     route: .memoryHome),
        SidebarToolEntry(id: "database",  title: "Database",  titleString: "Database",
                         icon: .system("cylinder.split.1x2"),        route: .databaseHome),
        SidebarToolEntry(id: "photos",    title: "Photos",    titleString: "Photos",
                         icon: .system("photo.on.rectangle.angled"), route: .drivePhotos),
        SidebarToolEntry(id: "documents", title: "Documents", titleString: "Documents",
                         icon: .system("doc.text"),                  route: .driveDocuments),
        SidebarToolEntry(id: "recent",    title: "Recent",    titleString: "Recent",
                         icon: .system("clock.arrow.circlepath"),    route: .driveRecent),
        SidebarToolEntry(id: "drive",     title: "Drive",     titleString: "Drive",
                         icon: .system("internaldrive"),             route: .driveAdmin),
    ]

    static func entry(byId id: String) -> SidebarToolEntry? {
        entries.first { $0.id == id }
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
    @EnvironmentObject var vault: VaultManager
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
    @AppStorage("SidebarViewMode", store: SidebarPrefs.store)
    private var viewModeRaw: String = SidebarViewMode.grouped.rawValue
    @AppStorage("ProjectSortMode", store: SidebarPrefs.store)
    private var projectSortModeRaw: String = ProjectSortMode.recent.rawValue
    @State private var pinnedExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarPinnedExpanded", default: true)
    @State private var pinnedFilterMenuOpen: Bool = false
    /// Comma-separated list of disabled pinned-filter tokens. UUIDs identify
    /// projects; the literal `__none__` represents the implicit "no project"
    /// bucket. Persisted as a single string so the existing `SidebarPrefs`
    /// `UserDefaults` suite can hold it without a custom codec.
    @AppStorage("SidebarPinnedFilterDisabled", store: SidebarPrefs.store)
    private var pinnedFilterDisabledRaw: String = ""
    /// Mirror of `pinnedFilterDisabledRaw` for the chronological "All chats"
    /// list. Same comma-separated UUID + `__none__` sentinel format. Edited
    /// from inside the Organize popup's "Filter > By project" submenu.
    @AppStorage("SidebarChronoFilterDisabled", store: SidebarPrefs.store)
    private var chronoFilterDisabledRaw: String = ""
    @State private var chronoExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarChronoExpanded", default: true)
    @State private var noProjectExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarNoProjectExpanded", default: true)
    @State private var projectsExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarProjectsExpanded", default: true)
    @State private var archivedExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarArchivedExpanded", default: false)
    @State private var toolsExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarToolsExpanded", default: true)
    /// Master switch for the Apps surface. Mirrors the Settings toggle
    /// that lives on `SidebarPrefs.store`; defaults on for new users.
    @AppStorage("AppsFeatureEnabled", store: SidebarPrefs.store)
    private var appsFeatureEnabled: Bool = true
    /// Custom order of tools, persisted as a comma-separated list of
    /// catalog ids. Empty string means "use the catalog's natural order".
    /// New tools added to the catalog in future releases append at the
    /// end of the saved order on first launch.
    @AppStorage("SidebarToolsOrder", store: SidebarPrefs.store)
    private var toolsOrderRaw: String = ""
    /// Hidden tools, persisted as a comma-separated list of catalog ids.
    /// Toggled from the section's filter popup; tools in this set are
    /// dropped from the rendered list but stay in the saved order so
    /// re-enabling them restores their previous position.
    @AppStorage("SidebarToolsHidden", store: SidebarPrefs.store)
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

            // Apps is its own peer of Tools: the user explicitly asked
            // for it OUT of Tools, even though both are top-level
            // entry points to non-chat surfaces. Gated by the
            // `AppsFeatureEnabled` toggle in Settings → Apps.
            if appsFeatureEnabled {
                AppsSidebarSection(appsStore: .shared)
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
                let chronoFilterActive = !chronoFilterDisabled.isEmpty
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
        .onChange(of: pinnedExpanded) { _, v in SidebarPrefs.store.set(v, forKey: "SidebarPinnedExpanded") }
        .onChange(of: chronoExpanded) { _, v in SidebarPrefs.store.set(v, forKey: "SidebarChronoExpanded") }
        .onChange(of: noProjectExpanded) { _, v in SidebarPrefs.store.set(v, forKey: "SidebarNoProjectExpanded") }
        .onChange(of: projectsExpanded) { _, v in SidebarPrefs.store.set(v, forKey: "SidebarProjectsExpanded") }
        .onChange(of: archivedExpanded) { _, v in
            SidebarPrefs.store.set(v, forKey: "SidebarArchivedExpanded")
            if v { Task { await appState.loadArchivedChats() } }
        }
        .onChange(of: toolsExpanded) { _, v in SidebarPrefs.store.set(v, forKey: "SidebarToolsExpanded") }
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
        let disabled = pinnedFilterDisabled
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
        return orderedTools.filter { !hidden.contains($0.id) }
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
        let disabled = chronoFilterDisabled
        guard !disabled.isEmpty else { return chrono }
        return chrono.filter { chat in
            if let pid = chat.projectId {
                return !disabled.contains(pid.uuidString)
            }
            return !disabled.contains(Self.pinnedFilterNoProjectToken)
        }
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
                    SidebarButton(title: "Skills",
                                  icon: "wand.and.stars",
                                  route: .skills,
                                  shortcut: "⌘⇧K")
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
                    OrganizeMenuPopup(
                        isPresented: $organizeMenuOpen,
                        viewModeRaw: $viewModeRaw,
                        projectSortModeRaw: $projectSortModeRaw,
                        chronoFilterSources: chronoSources,
                        chronoFilterDisabled: chronoFilterDisabled,
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
                    PinnedFilterPopup(
                        isPresented: $pinnedFilterMenuOpen,
                        sources: sources,
                        disabled: pinnedFilterDisabled,
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


private struct NewProjectAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - New project popup (start blank / use existing folder)

private struct NewProjectPopup: View {
    @Binding var isPresented: Bool
    let onBlank: () -> Void
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewProjectPopupRow(icon: "plus", label: "Start from scratch", action: onBlank)
            NewProjectPopupRow(icon: "folder", label: "Use an existing folder", action: onPickFolder)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 244)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

private struct NewProjectPopupRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                IconImage(icon, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer()
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

struct ProjectEditorContext: Identifiable {
    let id = UUID()
    let project: Project?
}

// MARK: - Settings bottom button (opens account popover above it)

private struct SettingsBottomButton: View {
    @Binding var open: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 11) {
                SettingsIcon(size: 16)
                    .frame(width: 15)
                    .foregroundColor(open ? .white : Color(white: hovered ? 0.92 : 0.78))
                Text("Settings")
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(open ? .white : Color(white: 0.92))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(open ? .isSelected : [])
    }

    private var backgroundFill: Color {
        // Sidebar tabs (open/selected and hover) use white-opacity so the
        // full-row glow stays soft; the wallpaper-tint side effect is
        // accepted here because the user prefers the look to a stable
        // solid gray.
        if open    { return Color.white.opacity(0.06) }
        if hovered { return Color.white.opacity(0.035) }
        return .clear
    }
}

// MARK: - Settings account popover (anchored above the settings button)

private struct SettingsAccountPopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var isOpen: Bool
    @State private var limitsExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsAccountRow(title: appState.auth.info?.email ?? L10n.t("Connected account"),
                               icon: "person.circle",
                               trailing: nil)
            MenuStandardDivider()
                .padding(.vertical, 4)
            SettingsAccountRow(title: L10n.t("Settings"),
                               icon: "clawix.settings",
                               trailing: nil) {
                appState.currentRoute = .settings
                isOpen = false
            }
            SettingsLimitsSection(expanded: $limitsExpanded)
            SettingsAccountRow(title: L10n.t("Sign out"),
                               icon: "clawix.signout",
                               trailing: nil) {
                isOpen = false
                appState.performBackendLogout()
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 268)
        .menuStandardBackground()
    }
}

// MARK: - Usage limits section

/// Toggleable section for usage limits inside the account popover. Default
/// collapsed; the chevron toggles visibility instantly via SwiftUI's
/// conditional rendering (no height measurement, so it works regardless
/// of when `appState.rateLimits` lands relative to the popover opening).
/// Reads `appState.rateLimits`, which the backend populates via
/// `account/rateLimits/read` at boot and refreshes through
/// `account/rateLimits/updated`.
private struct SettingsLimitsSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var expanded: Bool

    private var windows: [RateLimitWindow] {
        guard let snapshot = appState.rateLimits else { return [] }
        return [snapshot.primary, snapshot.secondary].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsLimitsHeaderRow(expanded: $expanded)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { entry in
                        SettingsLimitsValueRow(
                            label: SettingsLimitsFormatter.windowLabel(for: entry.element),
                            percent: SettingsLimitsFormatter.percentLabel(for: entry.element),
                            detail: SettingsLimitsFormatter.resetLabel(for: entry.element)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .clipped()
    }
}

private struct SettingsLimitsHeaderRow: View {
    @Binding var expanded: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.22)) {
                expanded.toggle()
            }
        }) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                UsageIcon(size: 15, lineWidth: 1.7)
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text("Remaining usage limits")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                LucideIcon(.chevronDown, size: 11)
                    .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

enum SettingsLimitsFormatter {
    static func windowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else { return "" }
        if mins == 10080 {
            return String(localized: "Weekly", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            return "\(mins / 60)h"
        }
        return "\(mins)min"
    }

    static func percentLabel(for window: RateLimitWindow) -> String {
        "\(window.usedPercent)%"
    }

    static func resetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: date)
    }

    /// Long-form variant used by the Settings → Usage page.
    static func detailedWindowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else {
            return String(localized: "Usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 10080 {
            return String(localized: "Weekly usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            let template = String(localized: "%lld-hour usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, locale: AppLocale.current, Int(mins / 60))
        }
        let template = String(localized: "%lld-minute usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, locale: AppLocale.current, Int(mins))
    }

    /// Long-form reset label, e.g. "Resets at 18:39" / "Resets on 5 mayo".
    static func detailedResetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
            let template = String(localized: "Resets at %@", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, formatter.string(from: date))
        }
        // Full month name (MMMM) so Spanish reads "5 mayo" instead of "5 may.".
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let template = String(localized: "Resets on %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, formatter.string(from: date))
    }

    static func perModelSectionTitle(name: String) -> String {
        let template = String(localized: "Usage limits for %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, name)
    }

    static func creditTitle(for credits: CreditsSnapshot) -> String {
        if credits.unlimited {
            return String(localized: "Unlimited credit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        let balance = credits.balance ?? "0"
        let template = String(localized: "%@ credit remaining", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, balance)
    }
}

private struct SettingsLimitsValueRow: View {
    let label: String
    let percent: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 12, weight: .medium))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(verbatim: percent)
                .font(BodyFont.system(size: 12))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: detail)
                .font(BodyFont.system(size: 12))
                .foregroundColor(MenuStyle.rowSubtle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
        .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
        .padding(.vertical, MenuStyle.rowVerticalPadding)
    }
}

private struct SettingsAccountRow: View {
    let title: String
    let icon: String
    let trailing: String?
    var action: (() -> Void)? = nil

    @State private var hovered = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "clawix.settings" {
                        SettingsIcon(size: 16)
                    } else if icon == "clawix.signout" {
                        SignOutIcon(size: 16)
                            .offset(x: 1)
                    } else {
                        LucideIcon.auto(icon, size: 14)
                    }
                }
                .frame(width: 18, alignment: .center)
                .foregroundColor(MenuStyle.rowIcon)
                Text(title)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                if let trailingIcon = trailing {
                    LucideIcon.auto(trailingIcon, size: 11)
                        .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing != nil ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .disabled(action == nil)
    }
}

// MARK: - SidebarButton

private struct SidebarButton: View {
    let title: String
    let icon: String
    var customShape: AnyShape? = nil
    var customShapeSize: CGFloat = 11.3
    var customShapeStroke: CGFloat = 1.15
    let route: SidebarRoute
    var actionOnly: Bool = false
    var shortcut: String? = nil

    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    private var isSelected: Bool {
        guard !actionOnly else { return false }
        return appState.currentRoute == route
    }

    private var localizedTitle: String {
        L10n.t(String.LocalizationValue(title))
    }

    var body: some View {
        Button {
            appState.currentRoute = route
        } label: {
            HStack(spacing: 11) {
                Group {
                    if let shape = customShape {
                        shape
                            .stroke(iconColor,
                                    style: StrokeStyle(lineWidth: customShapeStroke, lineCap: .round, lineJoin: .round))
                            .frame(width: customShapeSize, height: customShapeSize)
                            .frame(width: 15, height: 15)
                    } else {
                        LucideIcon.auto(icon, size: 9.5)
                            .frame(width: 15)
                            .foregroundColor(iconColor)
                    }
                }
                Text(localizedTitle)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.32))
                        )
                        .opacity(hovered ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel(localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    private var iconColor: Color {
        if isSelected { return .white }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.92)
    }

    private var backgroundFill: Color {
        // Sidebar tabs (selected and hover) both use white-opacity so the
        // full-row glow stays soft; user preference outweighs the
        // wallpaper-tint side effect here.
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

// MARK: - ComposeIcon

struct ComposeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        // Box (open rounded square, corner radius 5.5).
        path.move(to: p(10.5, 1.5))
        path.addLine(to: p(7, 1.5))
        path.addCurve(to: p(1.5, 7),
                      control1: p(3.96, 1.5),
                      control2: p(1.5, 3.96))
        path.addLine(to: p(1.5, 17))
        path.addCurve(to: p(7, 22.5),
                      control1: p(1.5, 20.04),
                      control2: p(3.96, 22.5))
        path.addLine(to: p(17, 22.5))
        path.addCurve(to: p(22.5, 17),
                      control1: p(20.04, 22.5),
                      control2: p(22.5, 20.04))
        path.addLine(to: p(22.5, 13.5))

        // Pencil (45 deg axis from eraser center (20, 4) to tip apex
        // (7.17, 16.83), body half-width 3). Eraser is a true
        // semicircle, the two shoulders and the tip apex are filleted.
        // All arcs converted to two-cubic Bezier approximations so the
        // path renders identically across platforms without addArc's
        // clockwise-flag ambiguity.
        path.move(to: p(17.88, 1.88))
        // Eraser cap (180 deg, radius 3) split at apex (22.12, 1.88).
        path.addCurve(to: p(22.12, 1.88),
                      control1: p(19.05, 0.71),
                      control2: p(20.95, 0.71))
        path.addCurve(to: p(22.12, 6.12),
                      control1: p(23.29, 3.05),
                      control2: p(23.29, 4.95))
        // Body lower edge -> lower shoulder fillet (radius 1.5).
        path.addLine(to: p(13.45, 14.79))
        path.addCurve(to: p(12.81, 15.17),
                      control1: p(13.27, 14.97),
                      control2: p(13.05, 15.10))
        // Tip lower side -> tip apex fillet (radius 0.8) split at (7.78, 16.22).
        path.addLine(to: p(8.58, 16.42))
        path.addCurve(to: p(7.78, 16.22),
                      control1: p(8.30, 16.50),
                      control2: p(7.99, 16.43))
        path.addCurve(to: p(7.58, 15.42),
                      control1: p(7.57, 16.01),
                      control2: p(7.50, 15.70))
        // Tip upper side -> upper shoulder fillet (radius 1.5).
        path.addLine(to: p(8.83, 11.19))
        path.addCurve(to: p(9.21, 10.55),
                      control1: p(8.90, 10.95),
                      control2: p(9.03, 10.73))
        path.closeSubpath()
        return path
    }
}

// MARK: - SectionDisclosureChevron

/// Tunables for collapsible sidebar sections. The chevron rotation and
/// section height share the same spring so the disclosure feels like a
/// single physical gesture.
enum SidebarSection {
    static let toggleAnimation: Animation = .easeInOut(duration: 0.28)
    /// Disclosure chevron rotation. Strong ease-out so the arrow snaps
    /// most of the way to its target quickly, then brakes hard at the
    /// end. Decoupled from `toggleAnimation` on purpose: the section
    /// height keeps a softer in-out, the chevron reads as more crisp.
    static let chevronRotation: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    /// Hover fade-in for the disclosure chevron. Small delay on appear
    /// so the arrow doesn't flash in the instant the cursor lands; fade
    /// out is immediate so the row clears as soon as hover ends.
    static let chevronHoverAppearDelay: Double = 0.06
    static let chevronHoverFadeIn: Animation = .easeOut(duration: 0.14)
    static let chevronHoverFadeOut: Animation = .easeOut(duration: 0.10)
    /// Trailing action icons cascade in after the chevron and fade out
    /// together without delay.
    static let trailingIconsFirstDelay: Double = 0.16
    static let trailingIconsStagger: Double = 0.05
    static let trailingIconsFadeIn: Animation = .easeOut(duration: 0.14)
    static let trailingIconsFadeOut: Animation = .easeOut(duration: 0.10)
}

/// Hover fade with an optional delay only on appear; on disappear the
/// fade is immediate so a group of staggered icons clears at once.
private struct HoverStaggerFade: ViewModifier {
    let visible: Bool
    let appearDelay: Double
    var fadeIn: Animation = SidebarSection.trailingIconsFadeIn
    var fadeOut: Animation = SidebarSection.trailingIconsFadeOut

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                visible ? fadeIn.delay(appearDelay) : fadeOut,
                value: visible
            )
    }
}

extension View {
    fileprivate func hoverStaggerFade(visible: Bool, appearDelay: Double) -> some View {
        modifier(HoverStaggerFade(visible: visible, appearDelay: appearDelay))
    }
}

/// Disclosure chevron used by collapsible sidebar section headers
/// (Pinned, All chats, No project, Projects). Rotates with its own
/// spring curve so the rotation reads as physical even when the caller
/// uses a different animation for layout. The hover-brightening is
/// driven from `CollapsibleSectionLabel`, so the title and chevron
/// share one hover region instead of lighting up independently.
private struct SectionDisclosureChevron: View {
    let expanded: Bool
    var hovered: Bool = false

    var body: some View {
        LucideIcon(.chevronRight, size: 10)
            .foregroundColor(Color(white: 0.78))
            .frame(width: 14, height: 14, alignment: .center)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(SidebarSection.chevronRotation, value: expanded)
            .opacity(hovered ? 1 : 0)
            .animation(
                hovered
                    ? SidebarSection.chevronHoverFadeIn.delay(SidebarSection.chevronHoverAppearDelay)
                    : SidebarSection.chevronHoverFadeOut,
                value: hovered
            )
    }
}

/// Title + chevron pair used by collapsible sidebar section headers.
/// Owns one hover state so the label and chevron brighten together,
/// matching the dim/brighten treatment of the header action icons.
/// Optional `leadingIcon` mirrors the icon column of the top sidebar
/// buttons (`New chat`, `Search`); when supplied, a 14x14 slot is laid
/// out before the title so headers visually rhyme with those rows.
private struct CollapsibleSectionLabel: View {
    let title: LocalizedStringKey
    let expanded: Bool
    /// Row-wide hover state owned by the parent header. Chevron reveal and
    /// label brightening key off this. `trailingIconsActive` (which also
    /// stays true while a header dropdown is open) drives the right hairline
    /// retraction so the bar doesn't snap back under still-visible icons
    /// when the cursor enters a popup.
    let hovered: Bool
    /// True when the trailing action icons are visible — i.e. hover OR an
    /// anchored dropdown is open. Drives the right hairline retraction
    /// only; the chevron and label color stay keyed to `hovered` so the
    /// disclosure arrow still hides on hover-out.
    var trailingIconsActive: Bool? = nil
    var chevronLeadingPadding: CGFloat = 2
    var leadingIcon: AnyView? = nil
    /// On hover, retract the right hairline by this many points to clear
    /// the trailing action icons (organize / new project / new chat). Pass
    /// 0 (default) for headers without a trailing icon group.
    var trailingIconsClearance: CGFloat = 0

    /// Collapsed sections read as part of the top button list (`New chat`,
    /// `Search`), so they borrow that brighter palette. Expanded sections
    /// recede into a dim title so the rows below stand out.
    private var labelColor: Color {
        if expanded {
            return Color(white: hovered ? 0.78 : 0.55)
        }
        return Color(white: hovered ? 0.96 : 0.92)
    }

    private var iconColor: Color {
        if expanded {
            return Color(white: hovered ? 0.78 : 0.55)
        }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let leadingIcon {
                ZStack {
                    leadingIcon
                        .foregroundColor(iconColor)
                        .scaleEffect(expanded ? 0 : 1, anchor: .center)
                        .opacity(expanded ? 0 : 1)
                        .animation(.easeOut(duration: 0.16), value: expanded)
                        .offset(y: 0.5)
                    SectionTitleHairline(visible: expanded, anchor: .trailing)
                }
                .frame(width: 15, height: 15, alignment: .center)
                .padding(.trailing, 11)
            }
            Text(title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(labelColor)
            ZStack(alignment: .leading) {
                // Asymmetric animation: contract fast on hover-in to clear
                // room for the trailing icons (collapse all, organize, new
                // project, new chat); on hover-out, wait for those icons to
                // finish their `trailingIconsFadeOut` (0.10s) and then sweep
                // back smoothly. Without the delay the line visibly crosses
                // still-fading icons; with too short a duration after the
                // delay it reads as a snap, not an animation.
                let trailingActive = trailingIconsActive ?? hovered
                SectionTitleHairline(visible: expanded, anchor: .leading)
                    .padding(.leading, hovered ? chevronLeadingPadding + 10 : 0)
                    .animation(
                        hovered
                            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
                            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.26).delay(0.10),
                        value: hovered
                    )
                    .padding(.trailing, trailingActive ? trailingIconsClearance : 0)
                    .animation(
                        trailingActive
                            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
                            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.26).delay(0.10),
                        value: trailingActive
                    )
                SectionDisclosureChevron(expanded: expanded, hovered: hovered)
                    .offset(x: chevronLeadingPadding - 11)
            }
            .frame(height: 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 11)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

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
private struct BasicSectionHeader: View {
    let title: LocalizedStringKey
    @Binding var expanded: Bool
    let leadingIcon: AnyView?
    /// Optional view rendered in a 22pt slot at the trailing edge. Fades
    /// in on hover or when `trailingForceVisible` is true. The view is
    /// responsible for its own click handler.
    var trailingIcon: AnyView? = nil
    /// Keep the trailing icon visible regardless of hover (e.g. while
    /// the icon's popup menu is open) so it doesn't blink out when the
    /// cursor enters the dropdown.
    var trailingForceVisible: Bool = false

    @State private var hovered = false

    private var iconsVisible: Bool { hovered || trailingForceVisible }

    var body: some View {
        let leadingPadding: CGFloat = leadingIcon != nil ? 16 : 20
        let hasTrailing = trailingIcon != nil
        let trailingClearance: CGFloat = hasTrailing ? 28 : 0
        HStack(spacing: 0) {
            CollapsibleSectionLabel(
                title: title,
                expanded: expanded,
                hovered: hovered,
                trailingIconsActive: hasTrailing ? iconsVisible : nil,
                leadingIcon: leadingIcon,
                trailingIconsClearance: trailingClearance
            )
            Spacer()
        }
        .frame(height: 24)
        .padding(.leading, leadingPadding)
        .padding(.trailing, 11)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(SidebarSection.toggleAnimation) { expanded.toggle() }
        }
        .overlay(alignment: .trailing) {
            if let trailingIcon {
                trailingIcon
                    .frame(width: 22, height: 22)
                    .padding(.trailing, 11)
                    .opacity(iconsVisible ? 1 : 0)
                    .animation(
                        iconsVisible
                            ? SidebarSection.trailingIconsFadeIn
                                .delay(SidebarSection.trailingIconsFirstDelay)
                            : SidebarSection.trailingIconsFadeOut,
                        value: iconsVisible
                    )
                    .disabled(!iconsVisible)
            }
        }
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Hairline that flanks an expanded section title (left + right). Sits
/// vertically centered with the text and grows outward from the word so
/// the open state reads as a labeled separator. `anchor` controls the
/// scale origin: `.trailing` for the left hairline (grows leftward away
/// from the title), `.leading` for the right hairline. Fade-in matches
/// the section expand timing.
private struct SectionTitleHairline: View {
    let visible: Bool
    let anchor: UnitPoint

    var body: some View {
        // Solid grays for the visible portion so the line doesn't take its
        // tone from the wallpaper through the translucent sidebar. The
        // endpoint stays alpha-0 because a hairline that disappears must
        // fade somewhere; the fade is local to the tail third while the
        // first ~70% nearest the word renders as a true solid line.
        let solid = Color(white: 0.42)
        let mid = Color(white: 0.36)
        let clear = Color.white.opacity(0)
        let stops: [Gradient.Stop] = anchor == .trailing
            ? [
                .init(color: clear, location: 0.0),
                .init(color: mid, location: 0.30),
                .init(color: solid, location: 0.55),
                .init(color: solid, location: 1.0)
            ]
            : [
                .init(color: solid, location: 0.0),
                .init(color: solid, location: 0.45),
                .init(color: mid, location: 0.70),
                .init(color: clear, location: 1.0)
            ]
        Rectangle()
            .fill(LinearGradient(gradient: Gradient(stops: stops),
                                 startPoint: .leading,
                                 endPoint: .trailing))
            .frame(height: 0.5)
            .scaleEffect(x: visible ? 1 : 0, y: 1, anchor: anchor)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.22), value: visible)
    }
}

// MARK: - PinnedIcon

/// Sidebar header icon button that dims by default and brightens on hover,
/// mirroring the `PinIcon` pattern used in chat rows.
private struct HeaderHoverIcon<Label: View>: View {
    let tooltip: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let label: (Color) -> Label

    @State private var hovered = false

    private var color: Color {
        hovered ? Color(white: 0.96) : Color(white: 0.6)
    }

    var body: some View {
        Button(action: action) {
            label(color)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

private struct PinnedIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(8, 4))
        path.addLine(to: p(16, 4))

        path.move(to: p(9, 4))
        path.addLine(to: p(9, 10))
        path.addLine(to: p(7, 14))
        path.addLine(to: p(7, 16))
        path.addLine(to: p(17, 16))
        path.addLine(to: p(17, 14))
        path.addLine(to: p(15, 10))
        path.addLine(to: p(15, 4))

        path.move(to: p(12, 16))
        path.addLine(to: p(12, 21))
        return path
    }
}

// MARK: - RecentChatRow (runtime-backed chats)

enum SidebarChatLeadingIcon { case none, pin, pinOnHover, bubble, unarchive }

/// Action callbacks the row needs but doesn't own. Held externally so the
/// row can drop `@EnvironmentObject var appState` and become `Equatable`:
/// SwiftUI then short-circuits body re-evaluation when nothing in the row's
/// data inputs changed, even if some other slice of `AppState` did. Each
/// callback captures `appState` (and the chat id) at construction time on
/// the parent side; the parent rebuilds them on demand whenever the row
/// re-evaluates.
struct RecentChatRowCallbacks {
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onUnarchive: () -> Void
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onToggleUnread: () -> Void
    let onOpenInFinder: () -> Void
    let onCopyWorkingDirectory: () -> Void
    let onCopySessionId: () -> Void
    let onCopyDeeplink: () -> Void
    let onForkLocal: () -> Void
    let onContextMenu: (NSPoint) -> Void
}

/// Free-function factory: kept out of `SidebarView` so other sidebar
/// containers (e.g. `PinnedReorderableList`) can build the same callbacks
/// from their own `appState` reference without reaching back into the
/// outer view.
@MainActor
private func makeRecentChatCallbacks(appState: AppState, chat: Chat, archived: Bool) -> RecentChatRowCallbacks {
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
            copySidebarStringToPasteboard("clawix://chat/\(id)")
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

private func copySidebarStringToPasteboard(_ value: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(value, forType: .string)
}

struct RecentChatRow: View, Equatable {
    let chat: Chat
    /// Pre-computed `currentRoute == .chat(chat.id)`. Lifted out of the row
    /// so the row's `Equatable` check can detect selection changes without
    /// having to subscribe to `AppState`.
    let isSelected: Bool
    var indent: CGFloat = 0
    var leadingIcon: SidebarChatLeadingIcon = .bubble
    /// Disables the hovered-row tint. The reorderable pinned list flips
    /// it on while a drag is active so dragging over another row doesn't
    /// read as "you can drop on this chat" — drops only land in the gaps.
    var suppressHoverStyling: Bool = false
    /// True for rows rendered inside the sidebar's archived section. The
    /// trailing hover button becomes "unarchive", drag is disabled (an
    /// archived chat has no slot to drop into) and the context menu is
    /// trimmed to actions that still make sense.
    var archivedRow: Bool = false
    let callbacks: RecentChatRowCallbacks
    /// Called from `.onDrag` the moment AppKit asks for the drag's
    /// `NSItemProvider`. The reorderable pinned list uses it to mark the
    /// row as the drag source so it can collapse its slot to 0 height
    /// while the drag is active.
    var onDragStart: (() -> Void)? = nil

    @State private var hovered = false
    @State private var pinHovered = false
    @State private var archiveHovered = false
    @State private var unarchiveHovered = false

    /// Closures are deliberately excluded from equality: they are recreated
    /// every parent render but capture `appState` (a stable reference) and
    /// chat id (a stable value), so a "stale" closure still does the right
    /// thing. Comparing only data fields lets SwiftUI skip body when none
    /// of them moved, even when the closure identities did.
    static func == (lhs: RecentChatRow, rhs: RecentChatRow) -> Bool {
        lhs.chat.id == rhs.chat.id
            && lhs.chat.title == rhs.chat.title
            && lhs.chat.hasActiveTurn == rhs.chat.hasActiveTurn
            && lhs.chat.hasUnreadCompletion == rhs.chat.hasUnreadCompletion
            && lhs.chat.createdAt == rhs.chat.createdAt
            && lhs.isSelected == rhs.isSelected
            && lhs.indent == rhs.indent
            && lhs.leadingIcon == rhs.leadingIcon
            && lhs.suppressHoverStyling == rhs.suppressHoverStyling
            && lhs.archivedRow == rhs.archivedRow
    }

    private var ageLabel: String { Self.relative(from: chat.createdAt) }

    @ViewBuilder
    private var trailingStatusView: some View {
        // Archive layered on top of the default trailing content
        // (spinner / unread dot / age label) and fades in/out via opacity so
        // it reads as a smooth crossfade on hover instead of a hard
        // view swap. Hit testing follows visibility so the button only
        // catches the cursor while the row is hovered.
        let archiveVisible = hovered && !archivedRow && !chat.hasActiveTurn

        ZStack(alignment: .trailing) {
            Group {
                if chat.hasActiveTurn {
                    SidebarChatRowSpinner()
                        .frame(width: 14, height: 14)
                        .frame(width: 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                } else if !archivedRow && chat.hasUnreadCompletion {
                    Circle()
                        .fill(Palette.pastelBlue)
                        .frame(width: 7, height: 7)
                        .frame(width: 28, height: 14)
                        .transition(.scale(scale: 0.0, anchor: .center).combined(with: .opacity))
                } else {
                    Text(ageLabel)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 28, alignment: .trailing)
                        .padding(.trailing, 5)
                        .transition(.opacity)
                }
            }
            .opacity(archiveVisible ? 0 : 1)
            .animation(.smooth(duration: 0.55, extraBounce: 0), value: chat.hasActiveTurn)
            .animation(.spring(response: 0.55, dampingFraction: 0.62), value: chat.hasUnreadCompletion)

            if !archivedRow && archiveVisible {
                // Render only while visible so hidden row actions do not
                // flood the accessibility tree during sidebar navigation.
                // The 22x22 frame around the 15.5pt icon gives a generous
                // halo so the cursor catches the button before it lands
                // on the glyph.
                Button(action: callbacks.onArchive) {
                    ArchiveIcon(size: 15.5)
                        .foregroundColor(archiveHovered ? Color(white: 0.94) : Color(white: 0.5))
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sidebarHover { archiveHovered = $0 }
                .help(L10n.t("Archive"))
            }
        }
        .animation(.easeOut(duration: 0.16), value: archiveVisible)
        .animation(.easeOut(duration: 0.12), value: archiveHovered)
    }

    var body: some View {
        RenderProbe.tick("RecentChatRow")
        let title = chat.title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : chat.title
        return HStack(spacing: 10) {
            leadingIconView
            Text(verbatim: title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(isSelected ? .white : Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailingStatusView
        }
        .padding(.leading, 8 + indent)
        .padding(.trailing, 3)
        .frame(height: 35)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .padding(.trailing, 3)
        .onTapGesture(perform: callbacks.onSelect)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: pinHovered)
        // Window has `isMovableByWindowBackground = true`, so without an
        // NSView in the row that returns `mouseDownCanMoveWindow = false`
        // AppKit hijacks mouseDown for a window drag and SwiftUI's
        // `.onDrag` never fires.
        .background(WindowDragInhibitor())
        .onDrag {
            // Carry the chat's UUID as plain text. Drop targets parse it
            // back to a UUID and route to AppState (reorder / move-to-
            // project / pin). The provider's suggestedName is used as
            // the macOS drag preview's label. Archived rows return an
            // empty provider so drop targets can't decode a UUID and
            // the drag is effectively inert.
            if archivedRow { return NSItemProvider() }
            onDragStart?()
            let provider = NSItemProvider(object: chat.id.uuidString as NSString)
            provider.suggestedName = chat.title
            return provider
        } preview: {
            // 1pt transparent: macOS animates the drag preview settling
            // at the drop location for ~500ms and SwiftUI does not expose
            // a way to disable it. We hand it a 1pt invisible view here
            // so the system has nothing visible to fade. The actual chip
            // the user sees follows the cursor via `DragChipPanel`, which
            // we close instantly on drop.
            Color.clear.frame(width: 1, height: 1)
        }
        .contextMenu { nativeContextMenu }
    }

    @ViewBuilder
    private var nativeContextMenu: some View {
        Button(chat.isPinned ? "Unpin chat" : "Pin chat", action: callbacks.onTogglePin)
            .disabled(archivedRow)
        Button("Rename chat", action: callbacks.onRename)
        Button(archivedRow ? "Unarchive chat" : "Archive chat") {
            archivedRow ? callbacks.onUnarchive() : callbacks.onArchive()
        }
        if !archivedRow {
            Button(chat.hasUnreadCompletion ? "Mark as read" : "Mark as unread", action: callbacks.onToggleUnread)
        }
        Divider()
        Button("Open in Finder", action: callbacks.onOpenInFinder)
            .disabled(chat.cwd?.isEmpty != false)
        Button("Copy working directory", action: callbacks.onCopyWorkingDirectory)
            .disabled(chat.cwd?.isEmpty != false)
        Button("Copy session ID", action: callbacks.onCopySessionId)
            .disabled(chat.clawixThreadId == nil)
        Button("Copy direct link", action: callbacks.onCopyDeeplink)
            .disabled(chat.clawixThreadId == nil)
        Divider()
        Button("Fork conversation", action: callbacks.onForkLocal)
    }

    @ViewBuilder
    private var leadingIconView: some View {
        switch leadingIcon {
        case .none:
            EmptyView()
        case .pin:
            pinToggleButton(
                visible: true,
                color: pinHovered ? .white : Color(white: 0.5),
                help: L10n.t("Unpin")
            )
        case .pinOnHover:
            pinToggleButton(
                visible: hovered,
                color: pinHovered ? Color(white: 0.94) : Color(white: 0.5),
                help: L10n.t("Pin")
            )
        case .bubble:
            LucideIcon(.messageCircle, size: 11)
                .foregroundColor(Color(white: 0.58))
                .frame(width: 14, height: 14)
        case .unarchive:
            unarchiveButton()
                .offset(y: 1)
        }
    }

    private func unarchiveButton() -> some View {
        // Leading slot, so growing the layout frame would push the
        // title right. Pad outwards to a 28x22 halo for the hit
        // shape, then pad back inwards by the same amount so the
        // parent HStack still allocates 14x14. Matches the generous
        // hover catch of the archive button on the right.
        Button(action: callbacks.onUnarchive) {
            ArchiveUnarchiveMorphIcon(
                size: 16.5,
                hovered: hovered,
                iconHovered: unarchiveHovered
            )
                .frame(width: 14, height: 14)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .padding(.horizontal, -7)
                .padding(.vertical, -4)
        }
        .buttonStyle(.plain)
        .sidebarHover { unarchiveHovered = $0 }
        .help(L10n.t("Unarchive"))
    }

    private func pinToggleButton(visible: Bool, color: Color, help: String) -> some View {
        // `.disabled(!visible)` instead of `.allowsHitTesting(visible)` so the
        // button keeps its hover tracking area alive when invisible. With
        // `.allowsHitTesting(false)` toggling on/off based on the parent row's
        // hover state, the moment the cursor crosses into the icon the parent
        // briefly loses hover, the icon flips back to non hit testable, and
        // the cursor falls through, producing the flicker the user reported.
        Button(action: callbacks.onTogglePin) {
            PinIcon(size: 15.0, lineWidth: 1.5)
                .foregroundColor(color)
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
                .opacity(visible ? 1 : 0)
        }
        .buttonStyle(.plain)
        .sidebarHover { pinHovered = $0 }
        .disabled(!visible)
        .accessibilityHidden(!visible)
        .help(help)
    }

    private var rowBackground: Color {
        // Both selected and hover use white-opacity so the chat-row glow
        // stays soft and consistent with the rest of the sidebar tabs.
        if isSelected { return Color.white.opacity(0.05) }
        if hovered && !suppressHoverStyling { return Color.white.opacity(0.035) }
        return .clear
    }

    private static func relative(from date: Date) -> String {
        L10n.relativeAge(elapsed: Date().timeIntervalSince(date))
    }
}

/// Quiet thin ring used in chat rows while a turn is in flight. Replaces the
/// default `ProgressView` so the rotation stays slow and the stroke matches
/// the rest of the sidebar's restrained line work.
private struct SidebarChatRowSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.28),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.79)
                .stroke(Color(white: 0.75),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 11, height: 11)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - ProjectAccordion

private struct ProjectAccordion: View, Equatable {
    let project: Project
    let expanded: Bool
    /// Up to `Self.maxVisible` (10) chats indexed for this project,
    /// already sorted desc by `createdAt`. The accordion further
    /// trims to `defaultVisible` (5) until "Show more" is tapped.
    let chats: [Chat]
    /// True once the user has tapped "Show more" on this project,
    /// promoting the visible slice from 5 to up to 10. Reset by the
    /// parent on collapse.
    let showingExtended: Bool
    let onToggle: () -> Void
    let onMenuToggle: () -> Void
    let onNewChat: () -> Void
    let onShowMore: () -> Void
    let onViewAll: () -> Void
    let menuOpen: Bool
    /// Currently selected chat id, lifted out so the accordion's `Equatable`
    /// check can detect "the user navigated to / away from a chat in this
    /// project" without subscribing to `AppState`.
    let selectedChatId: UUID?
    /// Factory that produces per-row callbacks. The closure itself is
    /// excluded from `==`; it captures `appState` and the chat id on the
    /// parent side, both stable across renders.
    let chatCallbacks: (Chat) -> RecentChatRowCallbacks

    /// Default number of chats shown when a project is freshly expanded.
    /// "Show more" promotes the slice to `maxVisible`.
    static let defaultVisible: Int = 5
    /// Hard cap on chats rendered inside the accordion. Anything past
    /// this is reachable through the per-project "View all" popup.
    static let maxVisible: Int = 10

    /// Visible slice of `chats` for the current `showingExtended` state.
    private var visibleChats: ArraySlice<Chat> {
        let cap = showingExtended ? Self.maxVisible : Self.defaultVisible
        return chats.prefix(cap)
    }

    /// Whether tapping "Show more" would reveal additional rows in the
    /// accordion. False once the visible slice already covers `chats`.
    private var canShowMore: Bool {
        !showingExtended && chats.count > Self.defaultVisible
    }

    /// Whether to surface the "View all" footer row. True once the
    /// indexed list has saturated the per-project cap, since the
    /// runtime may know about more conversations than the snapshot.
    /// Conservative: with exactly 10 indexed chats and nothing else
    /// behind them the popup just lists those 10, which is fine.
    private var canViewAll: Bool {
        showingExtended && chats.count >= Self.maxVisible
    }

    @State private var hovered = false
    @State private var newChatHovered = false
    @State private var menuHovered = false

    static func == (lhs: ProjectAccordion, rhs: ProjectAccordion) -> Bool {
        lhs.project.id == rhs.project.id
            && lhs.project.name == rhs.project.name
            && lhs.expanded == rhs.expanded
            && lhs.showingExtended == rhs.showingExtended
            && lhs.menuOpen == rhs.menuOpen
            && lhs.selectedChatId == rhs.selectedChatId
            && Self.chatsEqual(lhs.chats, rhs.chats)
    }

    /// Compare only the `Chat` fields the inner row actually renders
    /// (everything in `RecentChatRow.==`). Skips `messages`, `cwd`,
    /// `branch`, etc. — those mutate often during streaming and would
    /// invalidate the accordion for nothing.
    private static func chatsEqual(_ lhs: [Chat], _ rhs: [Chat]) -> Bool {
        if lhs.count != rhs.count { return false }
        for i in 0..<lhs.count {
            let l = lhs[i]
            let r = rhs[i]
            if l.id != r.id
                || l.title != r.title
                || l.hasActiveTurn != r.hasActiveTurn
                || l.hasUnreadCompletion != r.hasUnreadCompletion
                || l.createdAt != r.createdAt {
                return false
            }
        }
        return true
    }

    var body: some View {
        RenderProbe.tick("ProjectAccordion")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Tap-gesture instead of `Button`. A `Button` would consume
                // mouseDown and starve the parent's `.onDrag` (custom sort
                // mode reorders by dragging this row), the same reason
                // `RecentChatRow` uses `.onTapGesture` for selection.
                HStack(spacing: 8) {
                    FolderMorphIcon(size: 14.5, progress: expanded ? 1 : 0, lineWidthScale: 1.027)
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 15, height: 15)
                        .animation(.easeOut(duration: 0.28), value: expanded)
                    Text(project.name)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color(white: 0.94))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.28)) { onToggle() }
                }

                // Ellipsis (hover/menu open) — anchors the dropdown.
                // `.disabled` instead of `.allowsHitTesting` so the button's
                // hover tracking area survives even while invisible; toggling
                // hit testing on/off from the same `hovered` state the parent
                // row owns creates a flicker loop where moving the cursor
                // into the icon makes the parent lose hover and the icon
                // disappears.
                Button(action: onMenuToggle) {
                    LucideIcon(.ellipsis, size: 13)
                        .foregroundColor(menuHovered || menuOpen ? Color(white: 0.94) : Color(white: 0.55))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || menuOpen ? 1 : 0)
                .disabled(!(hovered || menuOpen))
                .sidebarHover { menuHovered = $0 }
                .help(L10n.t("More options"))
                .anchorPreference(key: ProjectMenuAnchorKey.self, value: .bounds) { anchor in
                    menuOpen ? anchor : nil
                }

                // Pencil. start a new chat in this project (always visible).
                // 28x28 hit area around a 12.2pt glyph: the cursor catches
                // the button as soon as it nears the icon, no need to land
                // exactly on the strokes.
                Button(action: onNewChat) {
                    ComposeIcon()
                        .stroke(newChatHovered ? Color(white: 0.94) : Color(white: 0.50),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 12.2, height: 12.2)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .sidebarHover { newChatHovered = $0 }
                .help(L10n.t("New chat in this project"))
            }
            .frame(height: 35)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered || menuOpen ? Color.white.opacity(0.04) : Color.clear)
            )
            .padding(.trailing, 3)
            .sidebarHover { hovered = $0 }
            .animation(.easeOut(duration: 0.10), value: hovered || menuOpen)
            .animation(.easeOut(duration: 0.12), value: newChatHovered)
            .animation(.easeOut(duration: 0.12), value: menuHovered)

            // `SidebarAccordion` uses the targetHeight as an open-state
            // animation hint but takes max(target, measured) for the
            // actual frame, so a slightly off heuristic clips a few
            // pixels rather than the bottom row. The previous fixed
            // `SmoothAccordion` cropped the 10th chat because the
            // 30pt row metric undershoots the rendered height and the
            // footer row was not in the calculation at all.
            let visibleCount = visibleChats.count
            let baseHeight: CGFloat = visibleCount > 0
                ? SidebarRowMetrics.recentChats(
                    count: visibleCount,
                    spacing: SidebarRowMetrics.projectChatSpacing
                )
                : SidebarRowMetrics.projectEmptyState
            let footerHeight: CGFloat = (canShowMore || canViewAll)
                ? SidebarRowMetrics.projectFooterRow + SidebarRowMetrics.projectChatSpacing
                : 0
            SidebarAccordion(
                expanded: expanded,
                targetHeight: baseHeight + footerHeight
            ) {
                // `LazyVStack` so a project with many chats doesn't pay
                // for instantiating off-screen rows. The accordion's
                // `targetHeight` provides the bounded frame, and the
                // surrounding `ThinScrollView` is the scroll context that
                // actually drives lazy materialisation.
                LazyVStack(alignment: .leading, spacing: 0) {
                    if chats.isEmpty {
                        Text("No chats")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Color(white: 0.40))
                            .padding(.leading, 30)
                            .padding(.vertical, 4)
                    }
                    ForEach(Array(visibleChats)) { chat in
                        RecentChatRow(
                            chat: chat,
                            isSelected: selectedChatId == chat.id,
                            leadingIcon: .pinOnHover,
                            callbacks: chatCallbacks(chat)
                        )
                        .equatable()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                    if canShowMore {
                        ProjectAccordionFooterRow(
                            label: L10n.t("Show more"),
                            action: onShowMore
                        )
                        .transition(.opacity)
                    } else if canViewAll {
                        ProjectAccordionFooterRow(
                            label: L10n.t("View all"),
                            action: onViewAll
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }
}

/// Footer label appended to a `ProjectAccordion`'s chat list to
/// trigger "Show more" (5 → 10) or "View all" (open the per-project
/// popup). Reads as plain text, not a row: no hover background, no
/// rounded "tab" look. Hover animates the text a notch toward white
/// (still well short of the chat title's 0.94) so the user gets a
/// subtle "this is interactive" hint without it competing with the
/// conversation rows above. The trailing whitespace gives the next
/// project's header a little breathing room.
private struct ProjectAccordionFooterRow: View {
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
            Spacer(minLength: 6)
        }
        .padding(.leading, 33)
        .padding(.trailing, 10)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.14), value: hovered)
    }
}

/// Animated vertical reveal driven by an explicit `targetHeight`. We
/// learned the hard way that `GeometryReader` based measurement misfires
/// when the container is clipped to 0, leaving content invisible. So
/// callers compute the natural height from their content (e.g. row count
/// times row height) and we just animate `frame(height:)` between 0 and
/// that target. `.fixedSize(vertical:)` keeps the content rendered at
/// its true intrinsic height so a slightly off estimate clips a few
/// pixels rather than collapsing rows.
private struct SmoothAccordion<Content: View>: View {
    let expanded: Bool
    let targetHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: expanded ? targetHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
            .animation(nil, value: expanded)
            .animation(nil, value: targetHeight)
    }
}

/// Heights used for accordion target-height math. Keep these tight to
/// the actual rendered values so the animation lands cleanly. Re-measure
/// if you change row paddings or fonts.
private enum SidebarRowMetrics {
    /// `RecentChatRow` and `ProjectAccordion` headers are both pinned
    /// to `frame(height: 35)` so every hoverable "tab" in the sidebar
    /// reads at one consistent size, regardless of internal content
    /// (e.g. the chat row's 22pt archive button vs the project header's
    /// 16pt text line).
    static let chatRow: CGFloat = 35
    /// VStack spacing between recent chat rows.
    static let chatSpacing: CGFloat = 0
    /// Spacing inside `ProjectAccordion`'s chat list.
    static let projectChatSpacing: CGFloat = 0
    /// "No chats" / "Loading…" placeholder row inside a project accordion.
    static let projectEmptyState: CGFloat = 24
    /// "Show more" / "View all" footer row at the end of a project's
    /// chat list. Same text size as a chat row plus a generous bottom
    /// gap so it visually separates from the next project header.
    static let projectFooterRow: CGFloat = 36
    /// Trailing buffer rendered as a `Color.clear` spacer at the end of
    /// every collapsible section's content (Pinned, Chats, All chats,
    /// Projects, Archived). Inside the accordion (not standalone) so it
    /// rides the height transition. Driving the gap from a real spacer
    /// inside `content()` instead of from `targetHeight` overshoot is
    /// what guarantees the gap reads identically across sections: when
    /// a section's row-height estimate is too low (Projects: 28pt
    /// estimate vs ~35pt actual rows), `measuredHeight` overshoots
    /// `targetHeight` and the accordion frame uses `measuredHeight`,
    /// which used to consume the buffer entirely (Projects looked glued
    /// to Archived while Pinned/Chats had a generous gap). With the
    /// spacer baked into measured content, the visible gap = this
    /// constant regardless of estimate accuracy.
    static let sectionEdgePadding: CGFloat = 9.75

    static func recentChats(count: Int, spacing: CGFloat = chatSpacing) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * chatRow + CGFloat(count - 1) * spacing
    }
}

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
private struct SidebarAccordion<Content: View>: View {
    let expanded: Bool
    let targetHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        let h = max(targetHeight, measuredHeight)
        VStack(spacing: 0) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                measuredHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size.height) { _, newH in
                                measuredHeight = newH
                            }
                    }
                )
        }
        .frame(height: expanded ? h : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .animation(nil, value: expanded)
        .animation(nil, value: h)
    }
}

private struct SidebarAccordionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Animated vertical reveal: a hidden twin always renders at its intrinsic
/// height to drive `measuredHeight`, the visible tree renders at full
/// opacity, and only the outer frame animates between 0 and the measured
/// height. Reveal direction comes from the clip alone (top-to-bottom on
/// open, bottom-to-top on close) so it matches the cadence of the simpler
/// `SidebarAccordion`-driven sections like Archived.
private struct ExpandableContainer<Content: View>: View {
    let expanded: Bool
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ExpandableHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            content()
        }
        .frame(height: expanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .animation(nil, value: expanded)
        .animation(nil, value: measuredHeight)
        .onPreferenceChange(ExpandableHeightKey.self) { measuredHeight = $0 }
    }
}

private struct ExpandableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ProjectMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - PinnedRow

private struct PinnedRow: View {
    let item: PinnedItem
    @State private var hovered = false

    var body: some View {
        RenderProbe.tick("PinnedRow")
        return HStack(spacing: 10) {
            PinnedIcon()
                .stroke(Color(white: 0.58),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text(item.title)
                .font(BodyFont.system(size: 14, wght: 500))
                .foregroundColor(Color(white: 0.94))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hovered {
                Button {
                    // archivar chat
                } label: {
                    LucideIcon(.archive, size: 13)
                        .foregroundColor(Color(white: 0.72))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Archive chat"))
            } else {
                Text(item.age)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovered ? Color.white.opacity(0.035) : Color.clear)
        )
        .sidebarHover { hovered = $0 }
        .contextMenu {
            Button("Unpin chat")     {}
            Button("Rename chat")     {}
            Button("Archive chat")      {}
            Button("Mark as unread") {}
            Divider()
            Button("Open in Finder")            {}
            Button("Copy working directory") {
                copyToPasteboard("~/Projects/\(item.title)")
            }
            Button("Copy session ID") {
                copyToPasteboard(item.id.uuidString)
            }
            Button("Copy direct link") {
                copyToPasteboard("clawix://chat/\(item.id.uuidString)")
            }
            Divider()
            Button("Fork to local")         {}
            Button("Fork to new worktree") {}
            Divider()
            Button("Open in mini window") {}
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }
}

// MARK: - Project row dropdown menu

private struct ProjectRowMenuPopup: View {
    let project: Project
    let isCodexSourced: Bool
    @Binding var isPresented: Bool
    let onOpenInFinder: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void
    let onRemove: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectRowMenuRow(icon: "folder", label: "Open in Finder", action: onOpenInFinder)
            ProjectRowMenuRow(icon: "arrow.triangle.branch", label: "Create a permanent worktree") {
                isPresented = false
            }
            ProjectRowMenuRow(icon: "pencil", label: "Rename project", action: onRename)
            ProjectRowMenuRow(icon: "tray.and.arrow.down", label: "Archive chats", action: onArchive)
            if isCodexSourced {
                ProjectRowMenuRow(icon: "eye.slash", label: "Hide from sidebar", action: onHide)
            } else {
                ProjectRowMenuRow(icon: "xmark", label: "Remove", action: onRemove)
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

private struct ProjectRowMenuRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "pencil" {
                        PencilIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 14, height: 14)
                    } else {
                        IconImage(icon, size: 11)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

// MARK: - Organize / Sort menu (funnel button next to the projects header)

private struct OrganizeMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private enum OrganizeSubmenu { case none, byProject }

private enum OrganizeChevronRow: Hashable { case byProject }

private struct OrganizeChevronAnchorsKey: PreferenceKey {
    static var defaultValue: [OrganizeChevronRow: Anchor<CGRect>] = [:]
    static func reduce(value: inout [OrganizeChevronRow: Anchor<CGRect>],
                       nextValue: () -> [OrganizeChevronRow: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Three-section dropdown: top-level view mode (Grouped vs Chronological),
/// project sort field (only when grouped), and a `Filter > By project`
/// submenu (only when chronological). The filter row mirrors the
/// hover-reveals-side-panel pattern used in the composer's model picker
/// (`ModelMenuPopup`): hovering the chevron spawns a column to the right
/// with the project filter list, so this popup remains the single entry
/// point for organizing the chat list. Selections persist via the
/// caller's `@AppStorage`-backed bindings; the side panel's per-project
/// toggles flow through the `chronoFilter*` callbacks.
private struct OrganizeMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var viewModeRaw: String
    @Binding var projectSortModeRaw: String

    /// Distinct project buckets across the chronological list. Empty if
    /// the chrono list contains zero chats. Provided by the caller so the
    /// popup stays stateless.
    let chronoFilterSources: [PinnedFilterSource]
    let chronoFilterDisabled: Set<String>
    let toggleChronoFilter: (String) -> Void
    let showAllChronoFilter: () -> Void
    let hideAllChronoFilter: () -> Void

    static let mainColumnWidth: CGFloat = 232
    private static let byProjectColumnWidth: CGFloat = 244
    private static let columnGap: CGFloat = 6
    private static let byProjectMaxListHeight: CGFloat = 260
    /// Below this row count we render the project list inline so the
    /// popup hugs the rows; above it we wrap in a capped ScrollView so
    /// the popup doesn't dominate the window.
    private static let byProjectInlineThreshold = 8

    @State private var openSubmenu: OrganizeSubmenu = .none

    private var isGrouped: Bool {
        viewModeRaw == SidebarViewMode.grouped.rawValue
    }

    /// Hide the filter affordance when there's nothing meaningful to
    /// filter by: zero buckets, or a single bucket (typically just the
    /// implicit "Without project" entry when the user hasn't created any
    /// projects yet). Mirrors the `>= 2` rule the Pinned section uses.
    private var canFilterByProject: Bool {
        !isGrouped && chronoFilterSources.count >= 2
    }

    private var allChronoHidden: Bool {
        !chronoFilterSources.isEmpty
            && chronoFilterDisabled.count >= chronoFilterSources.count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainColumn
        }
        .overlayPreferenceValue(OrganizeChevronAnchorsKey.self) { anchors in
            GeometryReader { proxy in
                let parentGlobalMinX = proxy.frame(in: .global).minX
                if openSubmenu == .byProject,
                   canFilterByProject,
                   let anchor = anchors[.byProject] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.byProjectColumnWidth,
                        gap: Self.columnGap
                    )
                    byProjectColumn
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
            }
            .animation(.easeOut(duration: 0.18), value: openSubmenu)
        }
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .animation(.easeOut(duration: 0.18), value: isGrouped)
        .animation(.easeOut(duration: 0.18), value: canFilterByProject)
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Organize")
            OrganizeMenuRow(
                icon: .folderOpen,
                label: "Grouped by project",
                isSelected: viewModeRaw == SidebarViewMode.grouped.rawValue
            ) {
                viewModeRaw = SidebarViewMode.grouped.rawValue
                isPresented = false
            }
            .onHover { hovering in
                if hovering { openSubmenu = .none }
            }
            OrganizeMenuRow(
                icon: .system("clock"),
                label: "Chronological list",
                isSelected: viewModeRaw == SidebarViewMode.chronological.rawValue
            ) {
                viewModeRaw = SidebarViewMode.chronological.rawValue
                isPresented = false
            }
            .onHover { hovering in
                if hovering { openSubmenu = .none }
            }

            if isGrouped {
                MenuStandardDivider()
                    .padding(.vertical, 5)

                ModelMenuHeader("Sort projects by")
                OrganizeMenuRow(
                    icon: .system("clock.arrow.circlepath"),
                    label: "Recent",
                    isSelected: projectSortModeRaw == ProjectSortMode.recent.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.recent.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("plus.circle"),
                    label: "Created",
                    isSelected: projectSortModeRaw == ProjectSortMode.creation.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.creation.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("textformat"),
                    label: "Name",
                    isSelected: projectSortModeRaw == ProjectSortMode.name.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.name.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("line.3.horizontal"),
                    label: "Custom",
                    isSelected: projectSortModeRaw == ProjectSortMode.custom.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.custom.rawValue
                    isPresented = false
                }
            }

            if canFilterByProject {
                MenuStandardDivider()
                    .padding(.vertical, 5)

                ModelMenuHeader("Filter")
                OrganizeMenuChevronRow(
                    icon: .system("folder"),
                    label: "By project",
                    badge: chronoFilterDisabled.isEmpty ? nil : "\(chronoFilterDisabled.count)",
                    highlighted: openSubmenu == .byProject
                ) {
                    openSubmenu = (openSubmenu == .byProject) ? .none : .byProject
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .byProject }
                }
                .anchorPreference(key: OrganizeChevronAnchorsKey.self, value: .bounds) {
                    [.byProject: $0]
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.mainColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var byProjectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Filter by project")
            byProjectList

            let hasFooter = !chronoFilterDisabled.isEmpty || !allChronoHidden
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !chronoFilterDisabled.isEmpty {
                    PinnedFilterBulkRow(icon: "eye", label: "Show all") {
                        showAllChronoFilter()
                    }
                }
                if !allChronoHidden {
                    PinnedFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAllChronoFilter()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.byProjectColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    @ViewBuilder
    private var byProjectList: some View {
        if chronoFilterSources.count > Self.byProjectInlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chronoFilterSources) { source in
                        PinnedFilterRow(
                            label: source.label,
                            isNoProject: source.isNoProject,
                            isActive: !chronoFilterDisabled.contains(source.token),
                            action: { toggleChronoFilter(source.token) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.byProjectMaxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(chronoFilterSources) { source in
                    PinnedFilterRow(
                        label: source.label,
                        isNoProject: source.isNoProject,
                        isActive: !chronoFilterDisabled.contains(source.token),
                        action: { toggleChronoFilter(source.token) }
                    )
                }
            }
        }
    }
}

private enum OrganizeMenuIcon {
    case folderOpen
    case system(String)
}

private struct OrganizeMenuRow: View {
    let icon: OrganizeMenuIcon
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    switch icon {
                    case .folderOpen:
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        LucideIcon.auto(name, size: 12)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

/// Row variant of `OrganizeMenuRow` that ends in a chevron and stays
/// highlighted while its companion side panel is open. Mirrors the
/// chevron row styling used by `ModelMenuChevronRow` in the composer's
/// model picker so the two cascading menus read as the same family.
private struct OrganizeMenuChevronRow: View {
    let icon: OrganizeMenuIcon
    let label: String
    let badge: String?
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    switch icon {
                    case .folderOpen:
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        LucideIcon.auto(name, size: 12)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
                LucideIcon(.chevronRight, size: 11)
                    .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                    .foregroundColor(MenuStyle.rowSubtle)
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(
                active: highlighted || hovered,
                intensity: highlighted ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            ))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

// MARK: - Pinned filter

/// Distinct buckets present across the loaded pinned chats: each project
/// that has at least one pinned chat, plus a synthetic "no project"
/// entry when any chat has `projectId == nil`. Lives at file scope so
/// the popup type below can name it as a concrete parameter.
fileprivate struct PinnedFilterSource: Identifiable, Equatable {
    let token: String
    let label: String
    let isNoProject: Bool
    var id: String { token }
}

private struct PinnedFilterAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Per-project visibility filter for the Pinned section. Each row maps
/// to one bucket present across the user's pinned chats (a project, or
/// the synthetic "no project" entry). Toggling a row flips its inclusion
/// in the visible list. The popup also exposes a "Show all" shortcut at
/// the bottom that wipes the entire disabled set in one click — the
/// recovery path when the user filtered down to "nothing visible" and
/// can no longer find the chats they pinned earlier.
private struct PinnedFilterPopup: View {
    @Binding var isPresented: Bool
    let sources: [PinnedFilterSource]
    let disabled: Set<String>
    let toggle: (String) -> Void
    let showAll: () -> Void
    let hideAll: () -> Void

    /// Cap so the popup never occupies the entire window when the user
    /// has dozens of projects with pinned chats; rows beyond the cap
    /// scroll inside.
    private static let maxListHeight: CGFloat = 260
    /// Below this row count we render the project list inline so the
    /// popup hugs the rows; above it we wrap in a capped ScrollView so
    /// the popup doesn't dominate the window.
    private static let inlineThreshold = 8

    private var allHidden: Bool {
        !sources.isEmpty && disabled.count >= sources.count
    }

    private var hasFooter: Bool { !disabled.isEmpty || !allHidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Filter by project")
            list
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !disabled.isEmpty {
                    PinnedFilterBulkRow(icon: "eye", label: "Show all") {
                        showAll()
                    }
                }
                if !allHidden {
                    PinnedFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAll()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    @ViewBuilder
    private var list: some View {
        if sources.count > Self.inlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        PinnedFilterRow(
                            label: source.label,
                            isNoProject: source.isNoProject,
                            isActive: !disabled.contains(source.token),
                            action: { toggle(source.token) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources) { source in
                    PinnedFilterRow(
                        label: source.label,
                        isNoProject: source.isNoProject,
                        isActive: !disabled.contains(source.token),
                        action: { toggle(source.token) }
                    )
                }
            }
        }
    }
}

/// Toggleable row inside `PinnedFilterPopup`. Active state is shown with
/// a check on the trailing edge and the icon + label rendered at full
/// brightness; inactive rows fade their label and icon so the disabled
/// state reads at a glance even without hovering.
private struct PinnedFilterRow: View {
    let label: String
    let isNoProject: Bool
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if isNoProject {
                        Image(systemName: "tray")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
                    } else {
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(isActive ? MenuStyle.rowText : MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 9.5, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

/// Footer row inside `PinnedFilterPopup` for "Show all" / "Hide all"
/// shortcuts. Same hover styling as the toggleable project rows so the
/// footer reads as part of the same list, just with a divider above it.
private struct PinnedFilterBulkRow: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Image(systemName: icon)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

// MARK: - Drag-and-drop helper

/// Wraps any sidebar row in a drop target that accepts a `Chat.id` UUID
/// carried as plain text by `RecentChatRow`'s `.onDrag`. Renders a soft
/// inset highlight while a drag hovers the wrapper, matching the row /
/// menu hover language used elsewhere in the app.
///
/// `accept` returns whether the drop was actually meaningful (e.g. drop
/// onto a row's own source is rejected) so we don't pretend to handle
/// no-ops.
private struct ChatDropTarget<Content: View>: View {
    let accept: (UUID) -> Bool
    @ViewBuilder let content: () -> Content

    @State private var isTargeted: Bool = false

    var body: some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isTargeted ? Color(white: 0.30) : Color.clear)
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.10), value: isTargeted)
            .onDrop(of: [.text], delegate: ChatDropDelegate(
                isTargeted: $isTargeted,
                accept: accept
            ))
    }
}

/// Custom delegate so we can reject project reorder drags before SwiftUI
/// flips `isTargeted`. Project drags carry a `public.url` representation
/// (`clawix-project://<UUID>`); `NSPasteboard` may auto-promote URLs to
/// `public.utf8-plain-text`, so the closure-based `.onDrop(of: [.text])`
/// would otherwise highlight project rows as if they were valid chat
/// drop targets.
private struct ChatDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let accept: (UUID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [.url]) { return false }
        return info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let s = item as? String,
                  let uuid = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                _ = accept(uuid)
            }
        }
        return true
    }
}

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
private final class PinnedRowFrameStore: ObservableObject {
    var byId: [UUID: CGRect] = [:]
}

private struct PinnedReorderableList: View, Equatable {
    /// Injected from the parent. Not observed: callbacks go through the
    /// reference, but state reads are passed in explicitly so this view
    /// stops re-evaluating on every `AppState` publish (per-token chats
    /// updates were rebuilding the pinned list at ~16 Hz during streaming).
    let appState: AppState
    let pinned: [Chat]
    let selectedChatId: UUID?

    static func == (lhs: PinnedReorderableList, rhs: PinnedReorderableList) -> Bool {
        lhs.selectedChatId == rhs.selectedChatId
            && Self.pinnedEqual(lhs.pinned, rhs.pinned)
    }

    /// Same shape as `RecentChatRow.==`: only fields the row actually
    /// renders, skipping `messages`, `cwd`, `branch`, etc. Streaming
    /// mutates those continually; comparing them would defeat the gate.
    private static func pinnedEqual(_ lhs: [Chat], _ rhs: [Chat]) -> Bool {
        if lhs.count != rhs.count { return false }
        for i in 0..<lhs.count {
            let l = lhs[i]
            let r = rhs[i]
            if l.id != r.id
                || l.title != r.title
                || l.hasActiveTurn != r.hasActiveTurn
                || l.hasUnreadCompletion != r.hasUnreadCompletion
                || l.createdAt != r.createdAt {
                return false
            }
        }
        return true
    }

    @State private var draggingId: UUID? = nil
    @State private var targetIndex: Int? = nil
    @State private var pendingClearTask: DispatchWorkItem? = nil
    @State private var mouseUpMonitor: Any? = nil
    /// Custom drag chip rendered in a borderless `NSPanel` that follows
    /// the cursor. Bypasses macOS's built-in drag preview so we control
    /// when it disappears (instantly on drop), instead of the system's
    /// ~500ms settle animation.
    @State private var dragChipPanel: DragChipPanel? = nil
    /// Each row reports its window-coord frame here so `handleDragStart`
    /// can compute the cursor's offset within the row at drag start.
    /// Reference-type bag (no `@Published`) so mutating `byId` is
    /// invisible to SwiftUI and the per-frame preference firehose
    /// stays cheap.
    @StateObject private var rowFrames = PinnedRowFrameStore()
    /// Holds a weak ref to the surrounding sidebar `NSScrollView`,
    /// captured by `EnclosingScrollViewLocator` once the view enters
    /// the AppKit hierarchy. Drives the edge auto-scroll while a
    /// pinned-row drag is active.
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    private let baseSpacing: CGFloat = 0
    /// Approximate slot size. `RecentChatRow` renders at 35 pt
    /// (`frame(height: 35)`) with 0 pt of baseSpacing so adjacent rows
    /// share an edge. The gap matches the row so the source's collapse
    /// and the gap's opening cancel out and the list height stays
    /// constant during an internal drag.
    private let gapHeight: CGFloat = 35
    private let rowHeight: CGFloat = 35
    /// Delay before a deferred clear fires when the cursor exits a slot
    /// zone. Short enough that leaving the list closes the gap quickly,
    /// long enough to absorb the brief inter-row transition without a
    /// visible flash.
    private static let exitClearDelay: TimeInterval = 0.10

    /// Smooth curve for the gap migrating from one slot to the next.
    /// Applied via `.animation(_:value:)` on the parent so every state
    /// change to `targetIndex` / `draggingId` interpolates with the
    /// same curve. Drop and cancel paths use a `disablesAnimations`
    /// transaction to override and commit instantly.
    private static let moveAnimation: Animation = .easeInOut(duration: 0.20)

    var body: some View {
        RenderProbe.tick("PinnedReorderableList")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pinned.enumerated()), id: \.element.id) { (i, chat) in
                slotZone(chat: chat, slot: i)
            }
            trailingSlotZone
        }
        // Animations are applied explicitly per-call (`withAnimation`)
        // so start/drop are instant while only the gap slide during
        // hover interpolates. The `withAnimation(moveAnimation)` in
        // `setTarget` opens a transaction scoped to that closure: it
        // animates the resulting `targetIndex` change (gap height) and
        // closes when the closure returns. Subsequent state mutations
        // in `performReorder` (plain assignments) do not inherit it,
        // so the row insertion lands instant without any extra
        // transaction trickery.
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cancelPendingClear()
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(PinnedRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: pinned.map(\.id)) { _, _ in
            // Defensive cleanup: any pinned-array reorder (ours or an
            // external sync) clears lingering drag state. Belt-and-
            // suspenders against the "extra gap stays forever" bug.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cancelPendingClear()
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    /// One slot zone, with two SEPARATE drop targets:
    ///
    /// - `gapPlaceholder(at: slot)` accepts drops with a constant
    ///   `slot` output. When the gap is open (32 pt) the cursor can
    ///   dwell inside it without flipping the target.
    /// - The row underneath uses a fixed `rowHeight / 2` threshold to
    ///   pick `slot` (top half, gap above this row) or `slot + 1`
    ///   (bottom half, gap below). Threshold is constant regardless
    ///   of whether the gap is open, so there is no oscillation when
    ///   the cursor sits right on a half boundary.
    @ViewBuilder
    private func slotZone(chat: Chat, slot: Int) -> some View {
        let isDragging = draggingId == chat.id
        let dragActive = draggingId != nil
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            RecentChatRow(
                chat: chat,
                isSelected: selectedChatId == chat.id,
                leadingIcon: .pin,
                suppressHoverStyling: dragActive,
                callbacks: makeRecentChatCallbacks(appState: appState, chat: chat, archived: false),
                onDragStart: { handleDragStart(chat: chat) }
            )
            .equatable()
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PinnedRowFrameKey.self,
                        value: [chat.id: proxy.frame(in: .global)]
                    )
                }
            )
            .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                computeSlot: { y in y < rowHeight / 2 ? slot : slot + 1 },
                onSet: { setTarget(slot: $0) },
                onExit: { scheduleExitClear() },
                onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
            ))
        }
    }

    /// Slot after the last row: trailing-end gap plus a small strip so
    /// the user can drop "at the end" without having to land on the
    /// last row's bottom half pixel-perfectly.
    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = pinned.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            // Trailing strip doubles as: (a) a drop target so dropping
            // "at the end" doesn't require landing on the last row's
            // bottom-half pixel-perfectly, and (b) the visible bottom
            // gap of the Pinned section. Sized to `sectionEdgePadding`
            // so Pinned's bottom gap matches every other collapsible
            // section. Earlier this was a hardcoded 14pt strip stacked
            // above the parent's `sectionEdgePadding` spacer, leaving
            // Pinned with ~14pt extra below the last row vs Chats /
            // Projects / Archived.
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == pinned.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear
            .frame(height: isOpen ? gapHeight : baseHeight)
    }

    private func handleDragStart(chat: Chat) {
        cancelPendingClear()
        let src = pinned.firstIndex(where: { $0.id == chat.id })
        // Instant: source row collapses to 0 + gap opens at its slot in
        // the same render. The drag preview takes over with no fade.
        // Cleanup paths after a drop are: `performReorder`, the
        // `mouseUpMonitor` for drops outside any zone, and the
        // `.onChange(of: pinned…)` defensive sweep. No watchdog timer
        // here because any fixed delay either fires mid-drag (the
        // source reappears under the cursor) or is too long to actually
        // catch a stuck state.
        targetIndex = src
        draggingId = chat.id
        // Render our own chip in a borderless panel that polls the
        // cursor each frame. macOS still runs its drag preview animation,
        // but we hand it a 1pt transparent view (see `.onDrag`'s
        // `preview:`) so there is nothing to fade. The visible chip is
        // ours and disappears the instant `cleanupDragChip()` fires.
        // Anchor offset: cursor position relative to the row's top-left
        // at drag start. Carrying this through to the panel keeps the
        // cursor at the same point on the chip the user originally
        // clicked, instead of a fixed right-of-cursor offset.
        let (anchor, width) = grabAnchor(for: chat)
        dragChipPanel?.close()
        dragChipPanel = DragChipPanel(chat: chat, grabAnchor: anchor, width: width)
        dragChipPanel?.show()
        // Edge auto-scroll. The same 60Hz cursor poll the chip uses to
        // follow the cursor also drives this; nudges the surrounding
        // sidebar `NSScrollView` while the cursor sits in the top or
        // bottom edge zone, so reordering across a long pinned list
        // doesn't require manual scrolling.
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    /// Cursor offset (in chip-local coords, top-left origin) and the
    /// row's measured width at drag start. The anchor keeps the cursor
    /// pinned to the same point on the chip the user clicked, and the
    /// width sizes the chip 1:1 with the row underneath. Falls back to
    /// sensible defaults if we don't yet have a frame measurement
    /// (defensive only — every row reports its frame on appear).
    private func grabAnchor(for chat: Chat) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[chat.id] else {
            return (CGPoint(x: 30, y: 16), fallbackWidth)
        }
        // Compute the offset entirely in SwiftUI window coordinates
        // (top-left origin) to avoid screen<->window conversion errors
        // around title bars / contentLayoutRect. Convert the cursor from
        // screen coords into the same SwiftUI window space, then take
        // the diff against the row's frame.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 16), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        // Screen -> window (still bottom-left origin).
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        // Window bottom-left -> SwiftUI top-left.
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        // Anchor in chip-local coords (top-left).
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        cancelPendingClear()
        // Drop targets keep firing `dropUpdated` for one more frame after
        // the drop completes (the layout reflow shifts which zone the
        // cursor sits over, SwiftUI dispatches one trailing event).
        // Without this guard that trailing event reopens the gap below
        // the row we just dropped and only a click clears it.
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        // Animated: the gap slides between positions as the cursor moves
        // over different slot zones. Source row collapse already happened
        // in `handleDragStart` so it doesn't get re-triggered here.
        withAnimation(Self.moveAnimation) {
            targetIndex = slot
        }
    }

    private func scheduleExitClear() {
        // Intentionally a no-op. SwiftUI fires `dropExited` on the zone
        // we just dropped onto (same event as the drop itself), which
        // means scheduling a state mutation here races with
        // `performReorder` and lands a phantom gap below the dropped row
        // for the gap between the two callbacks. Cleanup on cursor exit
        // is handled by the `mouseUpMonitor` (release outside any zone)
        // and `performReorder` (release inside a zone).
    }

    private func cancelPendingClear() {
        pendingClearTask?.cancel()
        pendingClearTask = nil
    }

    private func performReorder(uuid: UUID, beforeIndex: Int) {
        cancelPendingClear()
        cleanupDragChip()
        let beforeChatId: UUID? = (beforeIndex < pinned.count) ? pinned[beforeIndex].id : nil
        // Plain assignments. `setTarget`'s `withAnimation(moveAnimation)`
        // closure has already returned by the time the drop fires, so
        // there is no live transaction to override here. Row at new
        // index, no gap, source uncollapsed, all in one frame.
        appState.reorderPinned(chatId: uuid, beforeChatId: beforeChatId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cancelPendingClear()
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

private struct PinnedRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onExit: () -> Void
    let onPerform: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let s = item as? String,
                  let uuid = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                onPerform(uuid, slot)
            }
        }
        return true
    }
}

// MARK: - Pinned drag auto-scroll

/// Weak handle to the surrounding `NSScrollView`. Populated by
/// `EnclosingScrollViewLocator` once SwiftUI drops the locator into
/// the AppKit hierarchy; consumed by `PinnedDragAutoScroller` while a
/// pinned-row drag is active so it can nudge the scroller without
/// going through SwiftUI bindings.
@MainActor
final class EnclosingScrollViewBox: ObservableObject {
    weak var scrollView: NSScrollView?
}

/// Walks up its AppKit superview chain to find the nearest enclosing
/// `NSScrollView` and stashes a weak reference in `box`. Mirrors the
/// trick `ThinScrollerInstaller` uses, but exposes the scroll view to
/// SwiftUI code that needs to drive scrolling imperatively (e.g. the
/// pinned-list drag auto-scroll).
private struct EnclosingScrollViewLocator: NSViewRepresentable {
    let box: EnclosingScrollViewBox

    func makeNSView(context: Context) -> NSView { LocatorView(box: box) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class LocatorView: NSView {
        let box: EnclosingScrollViewBox
        init(box: EnclosingScrollViewBox) {
            self.box = box
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.locate() }
        }
        private func locate() {
            var current: NSView? = self.superview
            while let v = current {
                if let sv = v as? NSScrollView {
                    box.scrollView = sv
                    return
                }
                current = v.superview
            }
        }
    }
}

/// 60Hz auto-scroll driver active during a pinned-row drag. Polls
/// `NSEvent.mouseLocation` (still queryable while AppKit's drag
/// session owns the event stream, same trick `DragChipPanel` uses);
/// when the cursor sits inside the top or bottom edge zone of the
/// surrounding scroll view's visible rect, scrolls in that direction
/// with a speed that ramps up the closer the cursor is to the edge.
/// SwiftUI's `.onDrop` keeps firing against whatever slot zone is now
/// under the cursor, so the gap follows the new content and the user
/// can drop on rows that started off screen.
@MainActor
private final class PinnedDragAutoScroller {
    private weak var box: EnclosingScrollViewBox?
    private var timer: Timer?

    /// Distance from the top/bottom edge at which auto-scroll engages.
    /// ~3 pinned rows: wide enough that the user can park the cursor
    /// near the edge without having to nail it pixel-perfect.
    private let edgeZone: CGFloat = 96
    /// Speed (px/s) at the boundary of `edgeZone`. Even a slight nudge
    /// into the zone scrolls visibly instead of crawling.
    private let minSpeed: CGFloat = 600
    /// Peak scroll speed (px/s) right at the edge. ~3000 traverses
    /// the visible sidebar in roughly a third of a second, so a long
    /// pinned list moves quickly when the cursor is pinned to the edge.
    private let maxSpeed: CGFloat = 3000

    init(box: EnclosingScrollViewBox) {
        self.box = box
    }

    func start() {
        timer?.invalidate()
        let dt: TimeInterval = 1.0 / 60.0
        timer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            self?.tick(dt: dt)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(dt: TimeInterval) {
        guard let sv = box?.scrollView, let win = sv.window else { return }
        let cursorScreen = NSEvent.mouseLocation
        let cursorWindow = win.convertPoint(fromScreen: cursorScreen)
        let clip = sv.contentView
        let cursorClip = clip.convert(cursorWindow, from: nil)
        let bounds = clip.bounds
        guard cursorClip.x >= bounds.minX, cursorClip.x <= bounds.maxX,
              cursorClip.y >= bounds.minY, cursorClip.y <= bounds.maxY
        else { return }

        // Distance from the visible top edge, regardless of clip view
        // orientation. SwiftUI hosting views are flipped (origin at top),
        // but support both orientations defensively.
        let yFromTop: CGFloat = clip.isFlipped
            ? (cursorClip.y - bounds.minY)
            : (bounds.maxY - cursorClip.y)
        let visibleH = bounds.height

        // Linear ramp from `minSpeed` (factor=0, just inside the zone)
        // to `maxSpeed` (factor=1, glued to the edge). A floor speed
        // means scrolling kicks in immediately when the cursor enters
        // the zone instead of crawling for the first few pixels.
        var delta: CGFloat = 0
        if yFromTop < edgeZone {
            let factor = max(0, min(1, (edgeZone - yFromTop) / edgeZone))
            let speed = minSpeed + (maxSpeed - minSpeed) * factor
            delta = -speed * CGFloat(dt)
        } else if yFromTop > visibleH - edgeZone {
            let factor = max(0, min(1, (yFromTop - (visibleH - edgeZone)) / edgeZone))
            let speed = minSpeed + (maxSpeed - minSpeed) * factor
            delta = speed * CGFloat(dt)
        }
        guard abs(delta) > 0.05 else { return }

        let docHeight = sv.documentView?.frame.height ?? 0
        let maxY = max(0, docHeight - visibleH)
        // In a flipped clip view, increasing bounds.origin.y reveals
        // content that was below; in a non-flipped one it's the
        // opposite. Flip the sign so a positive `delta` always means
        // "scroll towards the bottom".
        let signedDelta: CGFloat = clip.isFlipped ? delta : -delta
        let currentY = bounds.origin.y
        let newY = max(0, min(maxY, currentY + signedDelta))
        guard abs(newY - currentY) > 0.05 else { return }
        clip.scroll(to: NSPoint(x: bounds.origin.x, y: newY))
        sv.reflectScrolledClipView(clip)
    }
}

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
private struct OrganizeFunnelIcon: View {
    var body: some View {
        VStack(spacing: 1.76) {
            Capsule(style: .continuous).frame(width: 11.0, height: 1.1)
            Capsule(style: .continuous).frame(width: 7.04, height: 1.1)
            Capsule(style: .continuous).frame(width: 3.52, height: 1.1)
        }
    }
}

struct WindowDragInhibitor: NSViewRepresentable {
    var onRightClick: ((NSPoint) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        _NoWindowDragView(onRightClick: onRightClick)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? _NoWindowDragView)?.onRightClick = onRightClick
    }

    private final class _NoWindowDragView: NSView {
        var onRightClick: ((NSPoint) -> Void)?

        init(onRightClick: ((NSPoint) -> Void)?) {
            self.onRightClick = onRightClick
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            nextResponder?.mouseDown(with: event)
        }
        override func mouseDragged(with event: NSEvent) {
            nextResponder?.mouseDragged(with: event)
        }
        override func mouseUp(with event: NSEvent) {
            nextResponder?.mouseUp(with: event)
        }
        override func rightMouseDown(with event: NSEvent) {
            if let onRightClick {
                onRightClick(NSEvent.mouseLocation)
            } else {
                nextResponder?.rightMouseDown(with: event)
            }
        }
    }
}

/// Counterpart to `WindowDragInhibitor`: a transparent NSView whose only
/// job is to return `mouseDownCanMoveWindow = true`. Painted under the top
/// chrome strip so the user can grab and move the window from anywhere in
/// that band, even though `isMovableByWindowBackground` is off everywhere
/// else. Buttons inside the strip keep working: AppKit's hit test finds
/// the NSButton (or other control) on top of this view, and controls
/// return `false` from `mouseDownCanMoveWindow` by default.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { _DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class _DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

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
private struct PinnedRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

@MainActor
final class DragChipPanel {
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>
    private var timer: Timer?
    /// Cursor offset within the chip (chip-local, top-left origin)
    /// captured at drag start.
    private let grabAnchor: CGPoint
    /// Transparent margin around the chip body inside the panel so the
    /// drop shadow (radius 14 + y offset 8) has room to render. Without
    /// it the panel's frame clips the shadow flush at the chip edge.
    private static let shadowInset: CGFloat = 24

    /// Designated init. Takes any SwiftUI view as the chip body so the
    /// same panel can render either a chat row preview or a project row
    /// preview. `fallbackHeight` is the height used when the hosting
    /// view's `fittingSize` isn't available yet (a measurement race
    /// every chip type works around).
    init(content: AnyView, grabAnchor: CGPoint, width: CGFloat, fallbackHeight: CGFloat) {
        self.grabAnchor = grabAnchor
        host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        // Width is pinned to the row's measured width plus the shadow
        // inset on each side so the shadow doesn't get clipped at the
        // panel edge. Height comes from the natural fitting size, or
        // `fallbackHeight + 2*inset` if measurement isn't ready yet.
        let measured = host.fittingSize
        let panelWidth = measured.width > 0 ? measured.width : width + Self.shadowInset * 2
        let panelHeight = measured.height > 0 ? measured.height : fallbackHeight + Self.shadowInset * 2
        let size = CGSize(width: panelWidth, height: panelHeight)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        // Borderless panels still inherit a default fade-out from
        // `orderOut(_:)`. Force `.none` so the chip disappears the same
        // frame the drop lands; otherwise the chip lingers for a beat
        // and reads as "the row I just dropped is animating in".
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host
    }

    convenience init(chat: Chat, grabAnchor: CGPoint, width: CGFloat) {
        let chip = DragChipView(chat: chat, width: width, shadowInset: Self.shadowInset)
        self.init(content: AnyView(chip), grabAnchor: grabAnchor, width: width, fallbackHeight: 35)
    }

    convenience init(project: Project, grabAnchor: CGPoint, width: CGFloat) {
        let chip = ProjectDragChipView(project: project, width: width, shadowInset: Self.shadowInset)
        self.init(content: AnyView(chip), grabAnchor: grabAnchor, width: width, fallbackHeight: 35)
    }

    func show() {
        updatePosition()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    private func updatePosition() {
        let cursor = NSEvent.mouseLocation
        let frame = panel.frame
        // grabAnchor is in chip-local coords, top-left origin. The chip
        // sits inset by `shadowInset` inside the panel (so the shadow
        // has room to render), so the cursor's target point in
        // panel-local coords is shifted by that inset on both axes.
        // Translate to AppKit screen coords (bottom-left origin) so the
        // cursor stays at the same point on the chip the user originally
        // clicked when the drag began.
        let inset = Self.shadowInset
        let new = NSRect(
            x: cursor.x - grabAnchor.x - inset,
            y: cursor.y - (frame.height - grabAnchor.y - inset),
            width: frame.width,
            height: frame.height
        )
        panel.setFrame(new, display: false)
    }
}

/// Visual content of the drag chip. Mirrors a hovered `RecentChatRow`
/// (pin icon + title + archive icon) so the user reads it as the exact
/// line they just picked up. Width is the row's measured width, padding
/// and corner radius mirror `RecentChatRow.body`, and the background
/// pairs the sidebar's `VisualEffectBlur` with the same hover overlay
/// (`Color.white.opacity(0.035)`) so the chip composites against the
/// desktop the same way the row composites against the sidebar.
/// No stroke; any extra outline shifts the perceived width away from
/// the row underneath.
private struct DragChipView: View {
    let chat: Chat
    let width: CGFloat
    /// Transparent breathing room around the chip so the drop shadow
    /// extends beyond the host panel's content view bounds without
    /// being clipped.
    let shadowInset: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            PinIcon(size: 12.5)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 14, height: 14)
            Text(chat.title.isEmpty
                 ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
                 : chat.title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
            ArchiveIcon(size: 14.5)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 14, height: 14)
                .padding(.trailing, 2)
        }
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(height: 35)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }
}

// MARK: - Project drag-reorder ("Custom" sort mode)

/// Visual content of the project drag chip. Mirrors the project header
/// row (folder icon + name) so the user reads it as the same line they
/// just picked up. Same chrome as `DragChipView` so chat and project
/// chips composite identically over the desktop background.
private struct ProjectDragChipView: View {
    let project: Project
    let width: CGFloat
    let shadowInset: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            FolderMorphIcon(size: 14.5, progress: 0, lineWidthScale: 1.027)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 15, height: 15)
            Text(project.name)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 35)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }
}

/// Bubbles each project row's frame (window coords, top-left origin)
/// up so `ProjectReorderableList` can compute the cursor's offset
/// within the row at drag start (mirrors `PinnedRowFrameKey`).
private struct ProjectRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Reference-type bag for per-row frames. Same trick as
/// `PinnedRowFrameStore`: mutating `byId` doesn't go through `@State`
/// so the per-frame preference firehose during accordion expansion
/// doesn't invalidate SwiftUI on every layout pass.
private final class ProjectRowFrameStore: ObservableObject {
    var byId: [UUID: CGRect] = [:]
}

/// File-private constant outside the generic type — Swift forbids
/// static stored properties on generic types.
private let projectReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Wraps the projects ForEach with custom drag-reorder. Active only when
/// `projectSortMode == .custom`; in other modes the parent renders the
/// rows directly so dragging is impossible (it would conflict with the
/// computed sort). Mirrors `PinnedReorderableList`'s structure: gap
/// placeholders between rows, a borderless `DragChipPanel` that follows
/// the cursor, and edge auto-scroll via `PinnedDragAutoScroller`.
private struct ProjectReorderableList<RowContent: View>: View {
    let appState: AppState
    let projects: [Project]
    @ViewBuilder let row: (Project) -> RowContent

    @State private var draggingId: UUID? = nil
    @State private var targetIndex: Int? = nil
    @State private var mouseUpMonitor: Any? = nil
    @State private var dragChipPanel: DragChipPanel? = nil
    @StateObject private var rowFrames = ProjectRowFrameStore()
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    /// Vertical breathing room between projects when no drag is active.
    /// Matches the `LazyVStack` spacing in the parent's non-custom
    /// branch so switching modes doesn't shift the layout.
    private let baseSpacing: CGFloat = 0
    /// Open-gap height during drag. Matches the project header (35 pt)
    /// with 0 pt baseSpacing so adjacent rows share an edge and the
    /// source's collapse plus the gap's opening cancel out, keeping the
    /// list height stable.
    private let gapHeight: CGFloat = 35
    /// Threshold for splitting a row into top-half / bottom-half slot
    /// zones. Used by the row-level drop delegate to choose between
    /// "gap above this row" and "gap below this row" depending on
    /// where the cursor is vertically.
    private let rowHeight: CGFloat = 35

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { (i, project) in
                slotZone(project: project, slot: i)
            }
            trailingSlotZone
        }
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(ProjectRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: projects.map(\.id)) { _, _ in
            // Defensive sweep: any external mutation to the projects
            // array (rename, delete, Codex roots refresh) clears
            // lingering drag state so a stale gap can never persist.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    @ViewBuilder
    private func slotZone(project: Project, slot: Int) -> some View {
        let isDragging = draggingId == project.id
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            row(project)
                .background(WindowDragInhibitor())
                .opacity(isDragging ? 0 : 1)
                .frame(height: isDragging ? 0 : nil, alignment: .top)
                .clipped()
                .allowsHitTesting(!isDragging)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ProjectRowFrameKey.self,
                            value: [project.id: proxy.frame(in: .global)]
                        )
                    }
                )
                .onDrag {
                    handleDragStart(project: project)
                    // Register `public.url` data DIRECTLY rather than
                    // wrapping an `NSURL` instance. `NSItemProvider(object:
                    // NSURL)` bridges through AppKit's pasteboard layer,
                    // which auto-promotes URLs to `public.utf8-plain-text`
                    // so other text drop targets (`ChatDropTarget`) flip
                    // their `isTargeted` highlight when a project is being
                    // reordered. Going through `registerDataRepresentation`
                    // exposes ONLY `public.url`, keeping the drag invisible
                    // to chat drop targets.
                    let provider = NSItemProvider()
                    let urlString = "\(clawixProjectURLScheme)://\(project.id.uuidString)"
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.url.identifier,
                        visibility: .ownProcess
                    ) { completion in
                        completion(urlString.data(using: .utf8), nil)
                        return nil
                    }
                    provider.suggestedName = project.name
                    return provider
                } preview: {
                    // 1pt transparent: macOS animates the system drag
                    // preview settling at drop for ~500ms; we hand it
                    // nothing visible so the only chip the user sees
                    // is our `DragChipPanel`, which closes instantly.
                    Color.clear.frame(width: 1, height: 1)
                }
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { y in y < rowHeight / 2 ? slot : slot + 1 },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = projects.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            // Trailing strip doubles as drop target for "at the end"
            // and as the section's visible bottom gap. Sized to
            // `sectionEdgePadding` for parity with every other
            // collapsible section; see the matching strip in
            // `PinnedReorderableList.trailingSlotZone` for the rationale.
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == projects.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear.frame(height: isOpen ? gapHeight : baseHeight)
    }

    private func handleDragStart(project: Project) {
        let src = projects.firstIndex(where: { $0.id == project.id })
        targetIndex = src
        draggingId = project.id
        let (anchor, width) = grabAnchor(for: project)
        dragChipPanel?.close()
        dragChipPanel = DragChipPanel(project: project, grabAnchor: anchor, width: width)
        dragChipPanel?.show()
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    private func grabAnchor(for project: Project) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[project.id] else {
            return (CGPoint(x: 30, y: 16), fallbackWidth)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 16), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        withAnimation(projectReorderMoveAnimation) {
            targetIndex = slot
        }
    }

    private func performReorder(uuid: UUID, beforeIndex: Int) {
        cleanupDragChip()
        let beforeProjectId: UUID? = (beforeIndex < projects.count) ? projects[beforeIndex].id : nil
        appState.reorderProject(projectId: uuid, beforeProjectId: beforeProjectId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

private struct ProjectRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onPerform: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
            guard let data,
                  let s = String(data: data, encoding: .utf8),
                  let url = URL(string: s),
                  url.scheme == clawixProjectURLScheme,
                  let uuid = projectId(from: url) else { return }
            DispatchQueue.main.async {
                onPerform(uuid, slot)
            }
        }
        return true
    }
}

/// `clawix-project://<UUID>` puts the UUID in the host slot. macOS
/// canonicalises hostnames to lowercase, but `UUID(uuidString:)` is
/// case-insensitive. Falls back to the first path component for the
/// (rare) case where the URL parser stripped the host.
private func projectId(from url: URL) -> UUID? {
    if let host = url.host, let uuid = UUID(uuidString: host) {
        return uuid
    }
    let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return UUID(uuidString: trimmed)
}

// MARK: - Tools section: filter popup + reorderable list

private struct ToolsFilterAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Popup that mirrors `PinnedFilterPopup` but operates on the static tools
/// catalog rather than per-project buckets. Each row toggles a tool's
/// presence in the sidebar list; the footer offers `Show all` / `Hide all`
/// shortcuts so the user can recover from "I hid everything" in one click.
private struct ToolsFilterPopup: View {
    @Binding var isPresented: Bool
    let entries: [SidebarToolEntry]
    let hidden: Set<String>
    let toggle: (String) -> Void
    let showAll: () -> Void
    let hideAll: () -> Void

    private static let maxListHeight: CGFloat = 280
    private static let inlineThreshold = 8

    private var allHidden: Bool {
        !entries.isEmpty && hidden.count >= entries.count
    }

    private var hasFooter: Bool { !hidden.isEmpty || !allHidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Show or hide tools")
            list
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !hidden.isEmpty {
                    ToolsFilterBulkRow(icon: "eye", label: "Show all") {
                        showAll()
                    }
                }
                if !allHidden {
                    ToolsFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAll()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    @ViewBuilder
    private var list: some View {
        if entries.count > Self.inlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        ToolsFilterRow(
                            entry: entry,
                            isActive: !hidden.contains(entry.id),
                            action: { toggle(entry.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    ToolsFilterRow(
                        entry: entry,
                        isActive: !hidden.contains(entry.id),
                        action: { toggle(entry.id) }
                    )
                }
            }
        }
    }
}

private struct ToolsFilterRow: View {
    let entry: SidebarToolEntry
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false
    @EnvironmentObject private var vault: VaultManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                iconView
                    .frame(width: 18, alignment: .center)
                Text(entry.title)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(isActive ? MenuStyle.rowText : MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 9.5, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        switch entry.icon {
        case .system(let name):
            Image(systemName: name)
                .font(BodyFont.system(size: 11))
                .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
        case .secrets:
            SecretsIcon(
                size: 11.5,
                lineWidth: 1.28,
                color: isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle,
                isLocked: vault.state == .locked || vault.state == .unlocking
            )
        }
    }
}

private struct ToolsFilterBulkRow: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Image(systemName: icon)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

// MARK: - Tools reorderable list

/// Bubbles each tool row's frame (window coords, top-left origin) up so
/// `ToolsReorderableList` can compute the cursor's offset within the row
/// at drag start (mirrors `ProjectRowFrameKey`, keyed by tool id rather
/// than UUID).
private struct ToolRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private final class ToolRowFrameStore: ObservableObject {
    var byId: [String: CGRect] = [:]
}

/// File-private constant outside the type so it stays consistent with
/// the existing `projectReorderMoveAnimation`.
private let toolReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Drag-reorderable list for the Tools section. Mirrors the structure of
/// `ProjectReorderableList`: gap placeholders between rows, a borderless
/// `DragChipPanel` that follows the cursor while AppKit's drag preview
/// renders a 1pt transparent stand-in (no settle fade on drop). External
/// drags (chats, projects) are rejected because the drop delegate only
/// accepts the `clawix-tool` URL scheme.
private struct ToolsReorderableList: View {
    let tools: [SidebarToolEntry]
    let selectedRoute: SidebarRoute
    let onSelect: (SidebarRoute) -> Void
    let onReorder: (String, String?) -> Void

    @State private var draggingId: String? = nil
    @State private var targetIndex: Int? = nil
    @State private var mouseUpMonitor: Any? = nil
    @State private var dragChipPanel: DragChipPanel? = nil
    @StateObject private var rowFrames = ToolRowFrameStore()
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    /// Slot height used both as the row height and the gap height during
    /// drag. The two cancel out so the list height stays constant while
    /// the gap migrates between slots. Matches the natural intrinsic
    /// height of `DatabaseToolRow` / `SecretsToolRow` (~28 pt: 6 pt
    /// vertical padding + ~16 pt content).
    static let rowSlotHeight: CGFloat = 28
    private let baseSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { (i, entry) in
                slotZone(entry: entry, slot: i)
            }
            trailingSlotZone
        }
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(ToolRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: tools.map(\.id)) { _, _ in
            // Defensive sweep: any external mutation to the tools array
            // (filter toggle, reorder) clears lingering drag state so a
            // stale gap can never persist.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    @ViewBuilder
    private func slotZone(entry: SidebarToolEntry, slot: Int) -> some View {
        let isDragging = draggingId == entry.id
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            ToolDisplayRow(
                entry: entry,
                isSelected: selectedRoute == entry.route,
                onTap: { onSelect(entry.route) }
            )
            .background(WindowDragInhibitor())
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ToolRowFrameKey.self,
                        value: [entry.id: proxy.frame(in: .global)]
                    )
                }
            )
            .onDrag {
                handleDragStart(entry: entry)
                let provider = NSItemProvider()
                let urlString = "\(clawixToolURLScheme)://\(entry.id)"
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.url.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(urlString.data(using: .utf8), nil)
                    return nil
                }
                provider.suggestedName = entry.titleString
                return provider
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                computeSlot: { y in y < Self.rowSlotHeight / 2 ? slot : slot + 1 },
                onSet: { setTarget(slot: $0) },
                onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
            ))
        }
    }

    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = tools.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == tools.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear.frame(height: isOpen ? Self.rowSlotHeight : baseHeight)
    }

    private func handleDragStart(entry: SidebarToolEntry) {
        let src = tools.firstIndex(where: { $0.id == entry.id })
        targetIndex = src
        draggingId = entry.id
        let (anchor, width) = grabAnchor(for: entry)
        dragChipPanel?.close()
        let chip = ToolDragChipView(
            entry: entry,
            width: width,
            shadowInset: 24
        )
        dragChipPanel = DragChipPanel(
            content: AnyView(chip),
            grabAnchor: anchor,
            width: width,
            fallbackHeight: Self.rowSlotHeight
        )
        dragChipPanel?.show()
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    private func grabAnchor(for entry: SidebarToolEntry) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[entry.id] else {
            return (CGPoint(x: 30, y: 14), fallbackWidth)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 14), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        withAnimation(toolReorderMoveAnimation) {
            targetIndex = slot
        }
    }

    private func performReorder(toolId: String, beforeIndex: Int) {
        cleanupDragChip()
        // Skip a no-op drop onto the source's own slot (either the gap
        // immediately above or the slot immediately below it). Otherwise
        // we'd churn the persisted order and re-fire the onChange watcher
        // on every drop that didn't actually move anything.
        if let src = tools.firstIndex(where: { $0.id == toolId }),
           (beforeIndex == src || beforeIndex == src + 1) {
            targetIndex = nil
            draggingId = nil
            return
        }
        let beforeId: String? = (beforeIndex < tools.count) ? tools[beforeIndex].id : nil
        onReorder(toolId, beforeId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

/// Drop delegate scoped to the `clawix-tool://<id>` URL scheme so chat /
/// project drags never highlight tool slot zones.
private struct ToolRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onPerform: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
            guard let data,
                  let s = String(data: data, encoding: .utf8),
                  let url = URL(string: s),
                  url.scheme == clawixToolURLScheme
            else { return }
            // The id sits in the URL host slot. Tool ids in the catalog
            // are already lowercase so macOS's hostname canonicalisation
            // is a no-op.
            let id = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return }
            DispatchQueue.main.async {
                onPerform(id, slot)
            }
        }
        return true
    }
}

/// Display-only tool row used inside `ToolsReorderableList`. Wraps
/// `SecretsToolRow` for the secrets entry and `DatabaseToolRow` for
/// everything else, so the visual treatment stays identical to the
/// pre-reorder design.
private struct ToolDisplayRow: View {
    let entry: SidebarToolEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        switch entry.icon {
        case .secrets:
            SecretsToolRow(isSelected: isSelected, onTap: onTap)
        case .system(let name):
            DatabaseToolRow(
                title: entry.titleString,
                systemIcon: name,
                route: entry.route,
                isSelected: isSelected,
                onTap: onTap
            )
        }
    }
}

/// Visual content of the tool drag chip. Matches the look of the row
/// underneath (icon + title) inside the same translucent capsule used by
/// `DragChipView` / `ProjectDragChipView` so chat, project and tool
/// chips composite identically over the desktop.
private struct ToolDragChipView: View {
    let entry: SidebarToolEntry
    let width: CGFloat
    let shadowInset: CGFloat
    @EnvironmentObject private var vault: VaultManager

    var body: some View {
        HStack(spacing: 11) {
            iconView
                .frame(width: 15, height: 15)
            Text(entry.title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: ToolsReorderableList.rowSlotHeight)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }

    @ViewBuilder
    private var iconView: some View {
        switch entry.icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Color(white: 0.82))
        case .secrets:
            SecretsIcon(
                size: 13.8,
                lineWidth: 1.28,
                color: Color(white: 0.82),
                isLocked: vault.state == .locked || vault.state == .unlocking
            )
        }
    }
}
