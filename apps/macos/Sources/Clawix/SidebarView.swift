import SwiftUI
import UniformTypeIdentifiers

enum SidebarOrganizationMode: String { case byProject, recentProjects, chronological }
enum SidebarSortMode: String { case creation, updated }

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
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var settingsPopoverOpen: Bool = false
    @State private var projectEditor: ProjectEditorContext?
    @State private var projectRenameTarget: Project?
    @State private var projectMenuOpenId: UUID?
    @State private var expandedProjects: Set<UUID> = []
    @State private var projectsHeaderHovered: Bool = false
    @State private var newProjectMenuOpen: Bool = false
    @State private var organizeMenuOpen: Bool = false
    @AppStorage("SidebarOrganizationMode", store: SidebarPrefs.store)
    private var organizationModeRaw: String = SidebarOrganizationMode.byProject.rawValue
    @AppStorage("SidebarSortMode", store: SidebarPrefs.store)
    private var sortModeRaw: String = SidebarSortMode.updated.rawValue
    @State private var pinnedExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarPinnedExpanded", default: true)
    @State private var chronoExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarChronoExpanded", default: true)
    @State private var noProjectExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarNoProjectExpanded", default: true)
    @State private var projectsExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarProjectsExpanded", default: true)
    @State private var archivedExpanded: Bool = SidebarPrefs.bool(forKey: "SidebarArchivedExpanded", default: false)
    @State private var chronoLimit: Int = 15

    private var organizationMode: SidebarOrganizationMode {
        SidebarOrganizationMode(rawValue: organizationModeRaw) ?? .byProject
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
        /// Anchor "now" captured once so each row reuses it for its
        /// relative-age label instead of calling `Date()` per body.
        let now: Date
    }

    private func makeSnapshot() -> SidebarSnapshot {
        let order = appState.pinnedOrder
        let pinIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        var pinnedRaw: [Chat] = []
        var byProjectRaw: [UUID: [Chat]] = [:]
        var chronoRaw: [Chat] = []
        for chat in appState.chats {
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
            chrono: chronoRaw,
            now: Date()
        )
    }

    private func sortedProjects(snapshot: SidebarSnapshot) -> [Project] {
        if organizationMode == .recentProjects {
            return appState.projects.sorted { lhs, rhs in
                let l = snapshot.recentDateByProject[lhs.id] ?? .distantPast
                let r = snapshot.recentDateByProject[rhs.id] ?? .distantPast
                return l > r
            }
        }
        return appState.projects
    }

    @ViewBuilder
    private func sidebarScrollContent(snapshot: SidebarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !snapshot.pinned.isEmpty {
                sectionHeader(
                    "Pinned",
                    expanded: $pinnedExpanded,
                    leadingIcon: AnyView(PinIcon(size: 14))
                )
                SidebarAccordion(
                    expanded: pinnedExpanded,
                    targetHeight: CGFloat(snapshot.pinned.count) * 32 + 8
                ) {
                    PinnedReorderableList(pinned: snapshot.pinned)
                        .padding(.leading, 8)
                        .padding(.trailing, 0)
                }
                AnimatedSidebarDivider(visible: pinnedExpanded)
            }

            if organizationMode == .chronological {
                chronoHeader
                    .padding(.leading, 18)
                    .padding(.trailing, 9)
                    .padding(.top, 2)
                    .padding(.bottom, 0)
                    .onHover { projectsHeaderHovered = $0 }
                let chronoCount = min(snapshot.chrono.count, chronoLimit)
                SidebarAccordion(
                    expanded: chronoExpanded,
                    targetHeight: snapshot.chrono.isEmpty
                        ? 26
                        : SidebarRowMetrics.recentChats(count: chronoCount)
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        if snapshot.chrono.isEmpty {
                            Text("No chats")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.40))
                                .padding(.leading, 22)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(Array(snapshot.chrono.prefix(chronoLimit))) { chat in
                                RecentChatRow(chat: chat, leadingIcon: .pinOnHover)
                            }
                        }
                    }
                    .padding(.leading, 8)
                }
                AnimatedSidebarDivider(visible: chronoExpanded)
            } else {
                projectsHeader
                    .padding(.leading, 18)
                    .padding(.trailing, 9)
                    .padding(.top, 2)
                    .padding(.bottom, 0)
                    .onHover { projectsHeaderHovered = $0 }

                // Projects list. We add/remove the whole subtree when
                // toggling. Nesting an `ExpandableContainer` here doesn't
                // work: each `ProjectAccordion` already runs its own
                // `ExpandableContainer` for its chat list, and chaining the
                // measurement twins reports `0` for the outer one on first
                // layout, leaving the section permanently collapsed.
                if projectsExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedProjects(snapshot: snapshot)) { project in
                            ChatDropTarget { droppedId in
                                appState.moveChatToProject(chatId: droppedId, projectId: project.id)
                                return true
                            } content: {
                                ProjectAccordion(
                                    project: project,
                                    expanded: expandedProjects.contains(project.id),
                                    chats: snapshot.byProject[project.id] ?? [],
                                    loading: appState.loadingProjects.contains(project.id),
                                    onToggle: {
                                        if expandedProjects.contains(project.id) {
                                            expandedProjects.remove(project.id)
                                        } else {
                                            expandedProjects.insert(project.id)
                                            Task { await appState.loadThreadsForProject(project) }
                                        }
                                    },
                                    onMenuToggle: {
                                        projectMenuOpenId = projectMenuOpenId == project.id ? nil : project.id
                                    },
                                    onNewChat: {
                                        appState.startNewChat(in: project)
                                    },
                                    menuOpen: projectMenuOpenId == project.id
                                )
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                AnimatedSidebarDivider(visible: projectsExpanded)

                let projectlessChats = snapshot.chrono.filter { $0.projectId == nil }
                if !projectlessChats.isEmpty {
                    sectionHeader(
                        "No project",
                        expanded: $noProjectExpanded,
                        leadingIcon: AnyView(
                            Image(systemName: "bubble.left")
                                .font(.system(size: 13, weight: .regular))
                        )
                    )
                    SidebarAccordion(
                        expanded: noProjectExpanded,
                        targetHeight: SidebarRowMetrics.recentChats(count: projectlessChats.count)
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(projectlessChats) { chat in
                                RecentChatRow(chat: chat)
                            }
                        }
                        .padding(.leading, 8)
                    }
                    AnimatedSidebarDivider(visible: noProjectExpanded)
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
        .task {
            if archivedExpanded { await appState.loadArchivedChats() }
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
            leadingIcon: AnyView(ArchiveIcon(size: 14))
        )
        SidebarAccordion(
            expanded: archivedExpanded,
            targetHeight: appState.archivedChats.isEmpty
                ? 26
                : SidebarRowMetrics.recentChats(count: appState.archivedChats.count)
        ) {
            VStack(alignment: .leading, spacing: 2) {
                if appState.archivedChats.isEmpty {
                    HStack(spacing: 6) {
                        if appState.archivedLoading {
                            SidebarChatRowSpinner()
                                .frame(width: 9, height: 9)
                        }
                        Text(appState.archivedLoading ? "Loading…" : "No archived chats")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.40))
                    }
                    .padding(.leading, 22)
                    .padding(.vertical, 4)
                } else {
                    ForEach(appState.archivedChats) { chat in
                        RecentChatRow(chat: chat, indent: 6, leadingIcon: .none, archivedRow: true)
                    }
                }
            }
            .padding(.leading, 8)
        }
        AnimatedSidebarDivider(visible: archivedExpanded)
    }

    var body: some View {
        RenderProbe.tick("SidebarView")
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                // Top nav: new chat, search.
                // Plugins and automations rows kept commented out for now.
                VStack(spacing: 1) {
                    SidebarButton(title: "New chat",
                                  icon: "square.and.pencil",
                                  customShape: AnyShape(ComposeIcon()),
                                  route: .home,
                                  actionOnly: true,
                                  shortcut: "⌘N")
                    SidebarButton(title: "Search",
                                  icon: "magnifyingglass",
                                  route: .search,
                                  shortcut: "⌘F")
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
                .padding(.leading, 8)
                .padding(.trailing, 22)
                .padding(.top, 6)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, 18)
                    .padding(.trailing, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ThinScrollView {
                    sidebarScrollContent(snapshot: makeSnapshot())
                        .padding(.trailing, 14)
                }

                // Settings button at bottom (toggles account popover above it)
                SettingsBottomButton(open: $settingsPopoverOpen)
                    .padding(.leading, 8)
                    .padding(.trailing, 22)
                    .padding(.bottom, 10)
                    .padding(.top, 6)
            }
            .frame(maxHeight: .infinity)

            // Account popover floats above the settings button
            if settingsPopoverOpen {
                SettingsAccountPopover(isOpen: $settingsPopoverOpen)
                    .background(MenuOutsideClickWatcher(isPresented: $settingsPopoverOpen))
                    .padding(.leading, 8)
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
                    let popupWidth: CGFloat = 232
                    OrganizeMenuPopup(
                        isPresented: $organizeMenuOpen,
                        organizationModeRaw: $organizationModeRaw,
                        sortModeRaw: $sortModeRaw
                    )
                    .frame(width: popupWidth)
                    .offset(
                        x: max(8, buttonFrame.maxX - popupWidth),
                        y: buttonFrame.maxY + 6
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .offset(
                        x: max(8, buttonFrame.maxX - popupWidth),
                        y: buttonFrame.maxY + 6
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                        }
                    )
                    .frame(width: popupWidth)
                    .offset(
                        x: max(8, buttonFrame.maxX - popupWidth + 4),
                        y: buttonFrame.maxY + 4
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(projectMenuOpenId != nil)
            .animation(MenuStyle.openAnimation, value: projectMenuOpenId)
        }
    }

    private func sectionHeader(
        _ title: LocalizedStringKey,
        expanded: Binding<Bool>,
        leadingIcon: AnyView? = nil
    ) -> some View {
        let isExpanded = expanded.wrappedValue
        let leadingPadding: CGFloat = leadingIcon != nil ? 18 : 22
        return Button(action: {
            withAnimation(SidebarSection.toggleAnimation) { expanded.wrappedValue.toggle() }
        }) {
            HStack(spacing: 0) {
                CollapsibleSectionLabel(
                    title: title,
                    expanded: isExpanded,
                    leadingIcon: leadingIcon
                )
                Spacer()
            }
            .padding(.leading, leadingPadding)
            .padding(.trailing, 11)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var projectsHeader: some View {
        sidebarHeader(title: "Projects",
                      showCollapseAll: true,
                      showNewChat: false,
                      leadingIcon: AnyView(FolderMorphIcon(size: 14, progress: 0)),
                      expanded: $projectsExpanded)
    }

    private var chronoHeader: some View {
        sidebarHeader(title: "All chats",
                      showCollapseAll: false,
                      showNewChat: true,
                      alwaysShow: true,
                      leadingIcon: AnyView(
                          Image(systemName: "bubble.left.and.bubble.right")
                              .font(.system(size: 12, weight: .regular))
                      ),
                      expanded: $chronoExpanded)
    }

    @ViewBuilder
    private func sidebarHeader(
        title: LocalizedStringKey,
        showCollapseAll: Bool,
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
        HStack(spacing: 4) {
            if let expanded {
                CollapsibleSectionLabel(title: title,
                                        expanded: expanded.wrappedValue,
                                        chevronLeadingPadding: 2,
                                        leadingIcon: leadingIcon)
            } else {
                HStack(spacing: 0) {
                    if let leadingIcon {
                        leadingIcon
                            .foregroundColor(Color(white: 0.78))
                            .frame(width: 15, height: 15, alignment: .center)
                            .padding(.trailing, 11)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(white: 0.88))
                }
            }
            Spacer()
            HStack(spacing: 2) {
                if showCollapseAll {
                    let allCollapsed = expandedProjects.isEmpty
                    headerIconButton(
                        systemName: allCollapsed
                            ? "arrow.up.right.and.arrow.down.left"
                            : "arrow.down.right.and.arrow.up.left",
                        tooltip: allCollapsed ? "Expandir todo" : "Collapse all"
                    ) {
                        toggleAllProjectsCollapsed()
                    }
                }
                organizeButton
                HeaderHoverIcon(tooltip: "Add new project") {
                    newProjectMenuOpen.toggle()
                } label: { color in
                    FolderAddIcon(size: 15, plusStrokeWidth: 1.4)
                        .foregroundColor(color)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .anchorPreference(key: NewProjectAnchorKey.self, value: .bounds) { $0 }
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
                }
            }
            .opacity(iconsVisible ? 1 : 0)
            .disabled(!iconsVisible)
            .animation(.easeOut(duration: 0.12), value: iconsVisible)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded != nil { toggle() }
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

    @ViewBuilder
    private func headerIconButton(
        systemName: String,
        tooltip: LocalizedStringKey,
        anchorKey: NewProjectAnchorKey.Type? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HeaderHoverIcon(tooltip: tooltip, action: action) { color in
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
        }
        .modifier(OptionalAnchorModifier(useAnchor: anchorKey != nil))
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
            name: String(localized: "New project", bundle: .module),
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
        panel.prompt = String(localized: "Select", bundle: .module)
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

/// Allows selectively attaching an anchor preference only when a key is given.
private struct OptionalAnchorModifier: ViewModifier {
    let useAnchor: Bool
    func body(content: Content) -> some View {
        if useAnchor {
            content.anchorPreference(key: NewProjectAnchorKey.self, value: .bounds) { $0 }
        } else {
            content
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
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer()
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: 15)
                    .foregroundColor(open ? .white : Color(white: 0.78))
                Text("Settings")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(open ? .white : Color(white: 0.88))
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
        .onHover { hovered = $0 }
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(open ? .isSelected : [])
    }

    private var backgroundFill: Color {
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
            SettingsAccountRow(title: appState.auth.info?.email ?? "Connected account",
                               icon: "person.circle",
                               trailing: nil)
            MenuStandardDivider()
                .padding(.vertical, 4)
            SettingsAccountRow(title: "Settings",
                               icon: "gearshape",
                               trailing: nil) {
                appState.currentRoute = .settings
                isOpen = false
            }
            SettingsLimitsSection(expanded: $limitsExpanded)
            SettingsAccountRow(title: "Sign out",
                               icon: "rectangle.portrait.and.arrow.right",
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
                Image(systemName: "speedometer")
                    .font(.system(size: 11))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text("Remaining usage limits")
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
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
        .onHover { hovered = $0 }
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

    /// Long-form reset label, e.g. "Resets at 18:39" / "Resets on 5 may".
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
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
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
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(verbatim: percent)
                .font(.system(size: 11.5))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: detail)
                .font(.system(size: 11.5))
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
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                if let trailingIcon = trailing {
                    Image(systemName: trailingIcon)
                        .font(.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
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
        .onHover { hovered = $0 }
        .disabled(action == nil)
    }
}

// MARK: - SidebarButton

private struct SidebarButton: View {
    let title: String
    let icon: String
    var customShape: AnyShape? = nil
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
                                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
                            .frame(width: 11.3, height: 11.3)
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .regular))
                            .frame(width: 15)
                            .foregroundColor(iconColor)
                    }
                }
                Text(localizedTitle)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(Color(white: 0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.09))
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
        .onHover { hovered = $0 }
        .accessibilityLabel(localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    private var iconColor: Color {
        isSelected ? .white : Color(white: 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.88)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

// MARK: - ComposeIcon

private struct ComposeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(10.5, 1.5))
        path.addLine(to: p(6, 1.5))
        path.addCurve(to: p(1.5, 6),
                      control1: p(3.515, 1.5),
                      control2: p(1.5, 3.515))
        path.addLine(to: p(1.5, 18))
        path.addCurve(to: p(6, 22.5),
                      control1: p(1.5, 20.485),
                      control2: p(3.515, 22.5))
        path.addLine(to: p(18, 22.5))
        path.addCurve(to: p(22.5, 18),
                      control1: p(20.485, 22.5),
                      control2: p(22.5, 20.485))
        path.addLine(to: p(22.5, 13.5))

        path.move(to: p(18, 1.5))
        path.addLine(to: p(21, 1.5))
        path.addCurve(to: p(22.5, 3),
                      control1: p(22, 1.5),
                      control2: p(22.5, 2))
        path.addLine(to: p(22.5, 5))
        path.addLine(to: p(13, 15))
        path.addLine(to: p(8.5, 16))
        path.addLine(to: p(8, 14.5))
        path.addLine(to: p(8, 12))
        path.addLine(to: p(17, 2.5))
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
}

/// Hairline that appears above and below an expanded sidebar section.
/// Matches the divider that sits under the top `Search` button, but
/// scales horizontally and fades in/out so it reads as part of the
/// section's open/close gesture instead of a static rule.
private struct AnimatedSidebarDivider: View {
    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: visible ? 1 : 0)
            .scaleEffect(x: visible ? 1 : 0, y: 1, anchor: .leading)
            .opacity(visible ? 1 : 0)
            .padding(.leading, 18)
            .padding(.trailing, 22)
            .padding(.top, visible ? 6 : 0)
            .padding(.bottom, visible ? 4 : 0)
            .animation(SidebarSection.toggleAnimation, value: visible)
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
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(white: 0.78))
            .frame(width: 16, height: 16, alignment: .center)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(SidebarSection.toggleAnimation, value: expanded)
            .opacity(hovered ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovered)
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
    var chevronLeadingPadding: CGFloat = 6
    var leadingIcon: AnyView? = nil

    @State private var hovered = false

    /// Collapsed sections read as part of the top button list (`New chat`,
    /// `Search`), so they borrow that brighter palette. Expanded sections
    /// recede into a dim title so the rows below stand out.
    private var labelColor: Color {
        if expanded {
            return Color(white: hovered ? 0.78 : 0.55)
        }
        return Color(white: hovered ? 0.96 : 0.88)
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
                leadingIcon
                    .foregroundColor(iconColor)
                    .frame(width: 15, height: 15, alignment: .center)
                    .padding(.trailing, 11)
                    .opacity(expanded ? 0 : 1)
                    .animation(.easeInOut(duration: 0.28), value: expanded)
            }
            Text(title)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(labelColor)
            SectionDisclosureChevron(expanded: expanded, hovered: hovered)
                .padding(.leading, chevronLeadingPadding)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
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
        .onHover { hovered = $0 }
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

enum SidebarChatLeadingIcon { case none, pin, pinOnHover, bubble }

struct RecentChatRow: View {
    let chat: Chat
    var indent: CGFloat = 0
    var leadingIcon: SidebarChatLeadingIcon = .bubble
    /// Called from `.onDrag` the moment AppKit asks for the drag's
    /// `NSItemProvider`. The reorderable pinned list uses it to mark the
    /// row as the drag source so it can collapse its slot to 0 height
    /// while the drag is active.
    var onDragStart: (() -> Void)? = nil
    /// Disables the hovered-row tint. The reorderable pinned list flips
    /// it on while a drag is active so dragging over another row doesn't
    /// read as "you can drop on this chat" — drops only land in the gaps.
    var suppressHoverStyling: Bool = false
    /// True for rows rendered inside the sidebar's archived section. The
    /// trailing hover button becomes "unarchive", drag is disabled (an
    /// archived chat has no slot to drop into) and the context menu is
    /// trimmed to actions that still make sense.
    var archivedRow: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    @State private var pinHovered = false
    @State private var archiveHovered = false

    private var isSelected: Bool {
        if case let .chat(id) = appState.currentRoute, id == chat.id { return true }
        return false
    }

    private var ageLabel: String { Self.relative(from: chat.createdAt) }

    @ViewBuilder
    private var trailingStatusView: some View {
        Group {
            if chat.hasActiveTurn {
                SidebarChatRowSpinner()
                    .frame(width: 14, height: 14)
                    .padding(.trailing, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else if hovered {
                Button {
                    if archivedRow {
                        appState.unarchiveChat(chatId: chat.id)
                    } else {
                        appState.archiveChat(chatId: chat.id)
                    }
                } label: {
                    Group {
                        if archivedRow {
                            Image(systemName: "tray.and.arrow.up")
                                .font(.system(size: 12, weight: .regular))
                        } else {
                            ArchiveIcon(size: 14)
                        }
                    }
                    .foregroundColor(archiveHovered ? Color(white: 0.94) : Color(white: 0.5))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { archiveHovered = $0 }
                .help(archivedRow ? "Unarchive" : "Archive")
                .padding(.trailing, 2)
                .transition(.opacity)
            } else if !archivedRow && chat.hasUnreadCompletion {
                Circle()
                    .fill(Color(red: 0.45, green: 0.65, blue: 1.0))
                    .frame(width: 7, height: 7)
                    .frame(width: 14, height: 14)
                    .padding(.trailing, 2)
                    .transition(.scale(scale: 0.0, anchor: .center).combined(with: .opacity))
            } else {
                Text(ageLabel)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.55))
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.55, extraBounce: 0), value: chat.hasActiveTurn)
        .animation(.spring(response: 0.55, dampingFraction: 0.62), value: chat.hasUnreadCompletion)
    }

    var body: some View {
        HStack(spacing: 10) {
            leadingIconView
            Text(chat.title.isEmpty
                 ? String(localized: "Conversation", bundle: .module)
                 : chat.title)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(isSelected ? .white : Color(white: 0.74))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailingStatusView
        }
        .padding(.leading, 10 + indent)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .onTapGesture {
            appState.currentRoute = .chat(chat.id)
        }
        .onHover { hovered = $0 }
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
            // Translucent chip: clearly distinct from a list row so the
            // user does not read the drag preview as a duplicate of the
            // source still sitting in the list. Default macOS preview is
            // an opaque snapshot of the source view at full row size.
            HStack(spacing: 8) {
                PinIcon(size: 11)
                    .foregroundColor(Color(white: 0.85))
                    .frame(width: 12, height: 12)
                Text(chat.title.isEmpty
                     ? String(localized: "Conversation", bundle: .module)
                     : chat.title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(Color(white: 0.95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.18).opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .contextMenu {
            if archivedRow {
                Button("Unarchive") {
                    appState.unarchiveChat(chatId: chat.id)
                }
                if let threadId = chat.clawixThreadId {
                    Divider()
                    Button("Copy session ID") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(threadId, forType: .string)
                    }
                }
            } else {
                Button(chat.isPinned ? "Unpin" : "Pin") {
                    appState.togglePin(chatId: chat.id)
                }
                Divider()
                Menu("Move to project") {
                    Button("No project") {
                        appState.assignChat(chatId: chat.id, toProject: nil)
                    }
                    if !appState.projects.isEmpty { Divider() }
                    ForEach(appState.projects) { project in
                        Button(project.name) {
                            appState.assignChat(chatId: chat.id, toProject: project.id)
                        }
                    }
                }
                if let threadId = chat.clawixThreadId {
                    Divider()
                    Button("Copy session ID") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(threadId, forType: .string)
                    }
                }
            }
        }
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
                help: "Unpin"
            )
        case .pinOnHover:
            pinToggleButton(
                visible: hovered,
                color: pinHovered ? Color(white: 0.94) : Color(white: 0.5),
                help: "Pin"
            )
        case .bubble:
            Image(systemName: "bubble.left")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.58))
                .frame(width: 14, height: 14)
        }
    }

    private func pinToggleButton(visible: Bool, color: Color, help: String) -> some View {
        // `.disabled(!visible)` instead of `.allowsHitTesting(visible)` so the
        // button keeps its hover tracking area alive when invisible. With
        // `.allowsHitTesting(false)` toggling on/off based on the parent row's
        // hover state, the moment the cursor crosses into the icon the parent
        // briefly loses hover, the icon flips back to non hit testable, and
        // the cursor falls through, producing the flicker the user reported.
        Button {
            appState.togglePin(chatId: chat.id)
        } label: {
            PinIcon(size: 12)
                .foregroundColor(color)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
                .opacity(visible ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { pinHovered = $0 }
        .disabled(!visible)
        .help(help)
    }

    private var rowBackground: Color {
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
        Circle()
            .trim(from: 0.0, to: 0.82)
            .stroke(Color(white: 0.55),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - ProjectAccordion

private struct ProjectAccordion: View {
    let project: Project
    let expanded: Bool
    let chats: [Chat]
    let loading: Bool
    let onToggle: () -> Void
    let onMenuToggle: () -> Void
    let onNewChat: () -> Void
    let menuOpen: Bool

    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    @State private var newChatHovered = false
    @State private var menuHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Button(action: { withAnimation(.easeOut(duration: 0.28)) { onToggle() } }) {
                    HStack(spacing: 8) {
                        FolderMorphIcon(size: 12, progress: expanded ? 1 : 0)
                            .foregroundColor(Color(white: 0.78))
                            .frame(width: 15, height: 15)
                            .animation(.easeOut(duration: 0.28), value: expanded)
                        Text(project.name)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(Color(white: 0.94))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Ellipsis (hover/menu open) — anchors the dropdown.
                // `.disabled` instead of `.allowsHitTesting` so the button's
                // hover tracking area survives even while invisible; toggling
                // hit testing on/off from the same `hovered` state the parent
                // row owns creates a flicker loop where moving the cursor
                // into the icon makes the parent lose hover and the icon
                // disappears.
                Button(action: onMenuToggle) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(menuHovered || menuOpen ? Color(white: 0.94) : Color(white: 0.55))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || menuOpen ? 1 : 0)
                .disabled(!(hovered || menuOpen))
                .onHover { menuHovered = $0 }
                .help("More options")
                .anchorPreference(key: ProjectMenuAnchorKey.self, value: .bounds) { anchor in
                    menuOpen ? anchor : nil
                }

                // Pencil. start a new chat in this project (always visible)
                Button(action: onNewChat) {
                    ComposeIcon()
                        .stroke(newChatHovered ? Color(white: 0.94) : Color(white: 0.50),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 11.2, height: 11.2)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .onHover { newChatHovered = $0 }
                .help("New chat in this project")
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered || menuOpen ? Color.white.opacity(0.04) : Color.clear)
            )
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.10), value: hovered || menuOpen)
            .animation(.easeOut(duration: 0.12), value: newChatHovered)
            .animation(.easeOut(duration: 0.12), value: menuHovered)

            SmoothAccordion(
                expanded: expanded,
                targetHeight: chats.isEmpty
                    ? SidebarRowMetrics.projectEmptyState
                    : SidebarRowMetrics.recentChats(
                        count: chats.count,
                        spacing: SidebarRowMetrics.projectChatSpacing
                    )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    if chats.isEmpty {
                        HStack(spacing: 6) {
                            if loading {
                                SidebarChatRowSpinner()
                                    .frame(width: 9, height: 9)
                            }
                            Text(loading ? "Loading…" : "No chats")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(white: 0.40))
                        }
                        .padding(.leading, 30)
                        .padding(.vertical, 4)
                    }
                    ForEach(chats) { chat in
                        RecentChatRow(chat: chat, leadingIcon: .pinOnHover)
                    }
                }
            }
        }
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
            .animation(.easeOut(duration: 0.28), value: expanded)
            .animation(.easeOut(duration: 0.28), value: targetHeight)
    }
}

/// Heights used for accordion target-height math. Keep these tight to
/// the actual rendered values so the animation lands cleanly. Re-measure
/// if you change row paddings or fonts.
private enum SidebarRowMetrics {
    /// `RecentChatRow`: vertical padding 7+7 + line-height ~16 = 30.
    static let chatRow: CGFloat = 30
    /// VStack spacing between recent chat rows.
    static let chatSpacing: CGFloat = 2
    /// Spacing inside `ProjectAccordion`'s chat list.
    static let projectChatSpacing: CGFloat = 3
    /// "No chats" / "Loading…" placeholder row inside a project accordion.
    static let projectEmptyState: CGFloat = 24

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
private struct SidebarAccordion<Content: View>: View {
    let expanded: Bool
    let targetHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: expanded ? targetHeight : 0, alignment: .top)
            .clipped()
            .animation(.easeInOut(duration: 0.28), value: expanded)
            .animation(.easeInOut(duration: 0.28), value: targetHeight)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
    }
}

/// Animated vertical reveal: measures intrinsic content height in a hidden
/// twin and animates the visible frame between 0 and that height. Wrapping
/// the toggle in `withAnimation(.easeOut(...))` decelerates the height/opacity
/// together so the project's container grows or shrinks smoothly instead of
/// snapping rows in and out.
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
                .opacity(expanded ? 1 : 0)
        }
        .frame(height: expanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(expanded)
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
        HStack(spacing: 10) {
            PinnedIcon()
                .stroke(Color(white: 0.58),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text(item.title)
                .font(.system(size: 13.5, weight: .light))
                .foregroundColor(Color(white: 0.92))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hovered {
                Button {
                    // archivar chat
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(white: 0.72))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Archive chat")
            } else {
                Text(item.age)
                    .font(.system(size: 11))
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
        .onHover { hovered = $0 }
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
    @Binding var isPresented: Bool
    let onOpenInFinder: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectRowMenuRow(icon: "folder", label: "Open in Finder", action: onOpenInFinder)
            ProjectRowMenuRow(icon: "arrow.triangle.branch", label: "Create a permanent worktree") {
                isPresented = false
            }
            ProjectRowMenuRow(icon: "pencil", label: "Rename project", action: onRename)
            ProjectRowMenuRow(icon: "tray.and.arrow.down", label: "Archivar chats", action: onArchive)
            ProjectRowMenuRow(icon: "xmark", label: "Quitar", action: onRemove)
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
                            .frame(width: 11, height: 11)
                    } else {
                        IconImage(icon, size: 11)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Organize / Sort menu (funnel button next to the projects header)

private struct OrganizeMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Two-section dropdown: organization mode and sort field. Each row shows a
/// check on the active option; selections persist via the caller's
/// `@AppStorage`-backed bindings, so the popup itself is stateless.
private struct OrganizeMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var organizationModeRaw: String
    @Binding var sortModeRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Organize")
            OrganizeMenuRow(
                icon: .folderOpen,
                label: "By project",
                isSelected: organizationModeRaw == SidebarOrganizationMode.byProject.rawValue
            ) {
                organizationModeRaw = SidebarOrganizationMode.byProject.rawValue
                isPresented = false
            }
            OrganizeMenuRow(
                icon: .folderOpen,
                label: "Recent projects",
                isSelected: organizationModeRaw == SidebarOrganizationMode.recentProjects.rawValue
            ) {
                organizationModeRaw = SidebarOrganizationMode.recentProjects.rawValue
                isPresented = false
            }
            OrganizeMenuRow(
                icon: .system("clock"),
                label: "Chronological list",
                isSelected: organizationModeRaw == SidebarOrganizationMode.chronological.rawValue
            ) {
                organizationModeRaw = SidebarOrganizationMode.chronological.rawValue
                isPresented = false
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuHeader("Sort by")
            OrganizeMenuRow(
                icon: .system("plus.circle"),
                label: "Creation",
                isSelected: sortModeRaw == SidebarSortMode.creation.rawValue
            ) {
                sortModeRaw = SidebarSortMode.creation.rawValue
                isPresented = false
            }
            OrganizeMenuRow(
                icon: .system("pencil.circle"),
                label: "Updated",
                isSelected: sortModeRaw == SidebarSortMode.updated.rawValue
            ) {
                sortModeRaw = SidebarSortMode.updated.rawValue
                isPresented = false
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
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
                        FolderOpenIcon(size: 11)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 11))
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
                    .fill(Color.white.opacity(isTargeted ? 0.07 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.10), value: isTargeted)
            .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
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
private struct PinnedReorderableList: View {
    @EnvironmentObject var appState: AppState
    let pinned: [Chat]

    @State private var draggingId: UUID? = nil
    @State private var targetIndex: Int? = nil
    @State private var pendingClearTask: DispatchWorkItem? = nil
    @State private var mouseUpMonitor: Any? = nil

    private let baseSpacing: CGFloat = 2
    /// Approximate row height. RecentChatRow renders at ~32 pt with
    /// font 13 + vertical padding 7. The gap matches it so the source's
    /// collapse and the gap's opening cancel out and the list height
    /// stays constant during an internal drag.
    private let gapHeight: CGFloat = 32
    private let rowHeight: CGFloat = 32
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pinned.enumerated()), id: \.element.id) { (i, chat) in
                slotZone(chat: chat, slot: i)
            }
            trailingSlotZone
        }
        // Animations are applied explicitly per-call (`withAnimation`) so
        // start/drop are instant while only the gap slide during hover
        // interpolates. `.animation(_:value:)` wouldn't honour the
        // `disablesAnimations` flag on `Transaction`, so we can't use it
        // here without also fading the source row.
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cancelPendingClear()
            removeMouseUpMonitor()
        }
        .onChange(of: pinned.map(\.id)) { _, _ in
            // Defensive cleanup: any pinned-array reorder (ours or an
            // external sync) clears lingering drag state. Belt-and-
            // suspenders against the "extra gap stays forever" bug.
            guard draggingId != nil || targetIndex != nil else { return }
            cancelPendingClear()
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
                leadingIcon: .pin,
                onDragStart: { handleDragStart(chat: chat) },
                suppressHoverStyling: dragActive
            )
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
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
            Color.clear
                .frame(height: 14)
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
        let beforeChatId: UUID? = (beforeIndex < pinned.count) ? pinned[beforeIndex].id : nil
        // Instant: row at new index, no gap, source uncollapsed, all in
        // one frame. With no `.animation(_:value:)` modifier on the list,
        // this needs no transaction trickery to be snappy.
        appState.reorderPinned(chatId: uuid, beforeChatId: beforeChatId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cancelPendingClear()
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

private struct WindowDragInhibitor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { _NoWindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class _NoWindowDragView: NSView {
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
    }
}
