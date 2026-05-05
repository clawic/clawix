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
            chrono: chronoRaw
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
                    leadingIcon: AnyView(PinIcon(size: 14.5))
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
                    .padding(.top, 6)
                    .padding(.bottom, 4)
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
                                .font(.system(size: 13.5, weight: .light))
                                .foregroundColor(Color(white: 0.40))
                                .padding(.leading, 36)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(snapshot.chrono.prefix(chronoLimit), id: \.id) { chat in
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
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .onHover { projectsHeaderHovered = $0 }

                // Projects list. We add/remove the whole subtree when
                // toggling. Wrapping in `ExpandableContainer` collapses the
                // section to 0pt on first layout: its measurement twin sees
                // each `ProjectAccordion` clip its inner `SmoothAccordion`
                // to height 0 while collapsed, so the height preference
                // arrives as 0 and never recovers.
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
                                .font(.system(size: 11.5, weight: .regular))
                        )
                    )
                    SidebarAccordion(
                        expanded: noProjectExpanded,
                        targetHeight: SidebarRowMetrics.recentChats(count: projectlessChats.count)
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(projectlessChats) { chat in
                                RecentChatRow(chat: chat, leadingIcon: .pinOnHover)
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
            leadingIcon: AnyView(ArchiveIcon(size: 14.5))
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
                            .font(.system(size: 13.5, weight: .light))
                            .foregroundColor(Color(white: 0.40))
                    }
                    .padding(.leading, 36)
                    .padding(.vertical, 4)
                } else {
                    ForEach(appState.archivedChats) { chat in
                        RecentChatRow(chat: chat, leadingIcon: .unarchive, archivedRow: true)
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
                                  customShape: AnyShape(SearchIconShape()),
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
            .frame(height: 24)
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
                      leadingIcon: AnyView(FolderMorphIcon(size: 13.5, progress: 0, lineWidthScale: 0.82)),
                      expanded: $projectsExpanded)
    }

    private var chronoHeader: some View {
        sidebarHeader(title: "Chats",
                      showCollapseAll: false,
                      showNewChat: true,
                      alwaysShow: true,
                      leadingIcon: AnyView(
                          Image(systemName: "bubble.left")
                              .font(.system(size: 11, weight: .regular))
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
                        .font(.system(size: 13.5, weight: .light))
                        .foregroundColor(Color(white: 0.88))
                }
            }
            Spacer()
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
                }
                organizeButton
                HeaderHoverIcon(tooltip: "Add new project") {
                    newProjectMenuOpen.toggle()
                } label: { color in
                    FolderAddIcon(size: 15.5, plusStrokeWidth: 1.4)
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
                    .font(.system(size: 12))
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
                    .font(.system(size: 13.5))
                    .frame(width: 15)
                    .foregroundColor(open ? .white : Color(white: 0.78))
                Text("Settings")
                    .font(.system(size: 13.5, weight: .light))
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
                    .font(.system(size: 11.5))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text("Remaining usage limits")
                    .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(verbatim: percent)
                .font(.system(size: 12))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: detail)
                .font(.system(size: 12))
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
                    .font(.system(size: 11.5))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text(title)
                    .font(.system(size: 12))
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
                            .font(.system(size: 13.5, weight: .regular))
                            .frame(width: 15)
                            .foregroundColor(iconColor)
                    }
                }
                Text(localizedTitle)
                    .font(.system(size: 13.5, weight: .light))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .regular))
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
    /// Disclosure chevron rotation. Strong ease-out so the arrow snaps
    /// most of the way to its target quickly, then brakes hard at the
    /// end. Decoupled from `toggleAnimation` on purpose: the section
    /// height keeps a softer in-out, the chevron reads as more crisp.
    static let chevronRotation: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
}

/// Hairline that appears above and below an expanded sidebar section.
/// Snapped to instant on open/close so the row reveal stays in lockstep
/// with the rest of the section. Trailing padding is `8` (not `22`) to
/// land at the same x as the top hairline below the search row: the
/// scroll wrapper that hosts these dividers already adds a 14pt trailing
/// gutter for the scrollbar, so 14 + 8 = 22 matches the chrome edge.
private struct AnimatedSidebarDivider: View {
    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: visible ? 1 : 0)
            .scaleEffect(x: visible ? 1 : 0, y: 1, anchor: .leading)
            .opacity(visible ? 1 : 0)
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.top, visible ? 6 : 0)
            .padding(.bottom, visible ? 4 : 0)
            .animation(nil, value: visible)
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
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(white: 0.78))
            .frame(width: 14, height: 14, alignment: .center)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(SidebarSection.chevronRotation, value: expanded)
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
                    .scaleEffect(expanded ? 0 : 1, anchor: .center)
                    .opacity(expanded ? 0 : 1)
                    .animation(.easeOut(duration: 0.16), value: expanded)
                    .padding(.trailing, 11)
            }
            Text(title)
                .font(.system(size: 13.5, weight: .light))
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

enum SidebarChatLeadingIcon { case none, pin, pinOnHover, bubble, unarchive }

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
    @State private var unarchiveHovered = false

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
            } else if hovered && !archivedRow {
                Button {
                    appState.archiveChat(chatId: chat.id)
                } label: {
                    ArchiveIcon(size: 14.5)
                        .foregroundColor(archiveHovered ? Color(white: 0.94) : Color(white: 0.5))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { archiveHovered = $0 }
                .help(L10n.t("Archive"))
                .padding(.trailing, 2)
                .transition(.opacity)
            } else if !archivedRow && chat.hasUnreadCompletion {
                Circle()
                    .fill(Palette.pastelBlue)
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
                 ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
                 : chat.title)
                .font(.system(size: 13.5, weight: .light))
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
        .animation(.easeOut(duration: 0.12), value: unarchiveHovered)
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
        .overlay(
            SidebarRightClickCatcher { screenPoint in
                SidebarChatContextMenuPanel.present(
                    at: screenPoint,
                    chat: chat,
                    isArchived: archivedRow,
                    appState: appState
                )
            }
        )
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
            Image(systemName: "bubble.left")
                .font(.system(size: 10.5))
                .foregroundColor(Color(white: 0.58))
                .frame(width: 14, height: 14)
        case .unarchive:
            unarchiveButton()
        }
    }

    private func unarchiveButton() -> some View {
        Button {
            appState.unarchiveChat(chatId: chat.id)
        } label: {
            ArchiveUnarchiveMorphIcon(size: 15.5, hovered: unarchiveHovered)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { unarchiveHovered = $0 }
        .help(L10n.t("Unarchive"))
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
            PinIcon(size: 12.5)
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
                        FolderMorphIcon(size: 12.5, progress: expanded ? 1 : 0)
                            .foregroundColor(Color(white: 0.78))
                            .frame(width: 15, height: 15)
                            .animation(.easeOut(duration: 0.28), value: expanded)
                        Text(project.name)
                            .font(.system(size: 13.5, weight: .light))
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
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(menuHovered || menuOpen ? Color(white: 0.94) : Color(white: 0.55))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || menuOpen ? 1 : 0)
                .disabled(!(hovered || menuOpen))
                .onHover { menuHovered = $0 }
                .help(L10n.t("More options"))
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
                .help(L10n.t("New chat in this project"))
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
                                .font(.system(size: 11))
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
            .animation(nil, value: expanded)
            .animation(nil, value: targetHeight)
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
            .animation(nil, value: expanded)
            .animation(nil, value: targetHeight)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
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
        HStack(spacing: 10) {
            PinnedIcon()
                .stroke(Color(white: 0.58),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text(item.title)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(white: 0.92))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hovered {
                Button {
                    // archivar chat
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color(white: 0.72))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Archive chat"))
            } else {
                Text(item.age)
                    .font(.system(size: 11.5))
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
                    .font(.system(size: 12))
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
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 11.5))
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .semibold))
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
    /// Custom drag chip rendered in a borderless `NSPanel` that follows
    /// the cursor. Bypasses macOS's built-in drag preview so we control
    /// when it disappears (instantly on drop), instead of the system's
    /// ~500ms settle animation.
    @State private var dragChipPanel: DragChipPanel? = nil
    /// Each row reports its window-coord frame here so `handleDragStart`
    /// can compute the cursor's offset within the row at drag start. The
    /// chip is anchored to that offset so the cursor stays at the same
    /// point of the chip the user originally clicked.
    @State private var rowFramesById: [UUID: CGRect] = [:]
    /// Holds a weak ref to the surrounding sidebar `NSScrollView`,
    /// captured by `EnclosingScrollViewLocator` once the view enters
    /// the AppKit hierarchy. Drives the edge auto-scroll while a
    /// pinned-row drag is active.
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

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
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cancelPendingClear()
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(PinnedRowFrameKey.self) { rowFramesById = $0 }
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
                leadingIcon: .pin,
                onDragStart: { handleDragStart(chat: chat) },
                suppressHoverStyling: dragActive
            )
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
        // Render our own chip in a borderless panel that polls the
        // cursor each frame. macOS still runs its drag preview animation,
        // but we hand it a 1pt transparent view (see `.onDrag`'s
        // `preview:`) so there is nothing to fade. The visible chip is
        // ours and disappears the instant `cleanupDragChip()` fires.
        // Anchor offset: cursor position relative to the row's top-left
        // at drag start. Carrying this through to the panel keeps the
        // cursor at the same point on the chip the user originally
        // clicked, instead of a fixed right-of-cursor offset.
        let anchor = grabAnchor(for: chat)
        dragChipPanel?.close()
        dragChipPanel = DragChipPanel(chat: chat, grabAnchor: anchor)
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

    /// Cursor offset (in chip-local coords, top-left origin) at drag
    /// start. Falls back to a sensible default if we don't yet have a
    /// frame measurement for this row (defensive only — every row reports
    /// its frame on appear).
    private func grabAnchor(for chat: Chat) -> CGPoint {
        guard let rowFrame = rowFramesById[chat.id] else {
            return CGPoint(x: 30, y: 16)
        }
        // Compute the offset entirely in SwiftUI window coordinates
        // (top-left origin) to avoid screen<->window conversion errors
        // around title bars / contentLayoutRect. Convert the cursor from
        // screen coords into the same SwiftUI window space, then take
        // the diff against the row's frame.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return CGPoint(x: 30, y: 16)
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
        return CGPoint(x: dx, y: dy)
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
        // Force-instant: the last `setTarget` during the drag opened an
        // animation transaction (`withAnimation(moveAnimation)`); without
        // an explicit nil-animation transaction here the source row's
        // opacity/frame restore inherits that easeOut and fades in over
        // 200ms instead of snapping back the moment the drop lands.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            appState.reorderPinned(chatId: uuid, beforeChatId: beforeChatId)
            targetIndex = nil
            draggingId = nil
        }
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
    /// ~1.5 pinned rows: comfortable hit area without triggering during
    /// normal mid-list dragging.
    private let edgeZone: CGFloat = 56
    /// Peak scroll speed (px/s) at the very edge. Squared falloff in
    /// `tick(dt:)` keeps motion gentle near the boundary of `edgeZone`
    /// and ramps up sharply only as the cursor approaches the edge.
    private let maxSpeed: CGFloat = 900

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

        var delta: CGFloat = 0
        if yFromTop < edgeZone {
            let factor = (edgeZone - yFromTop) / edgeZone
            delta = -(factor * factor) * maxSpeed * CGFloat(dt)
        } else if yFromTop > visibleH - edgeZone {
            let factor = (yFromTop - (visibleH - edgeZone)) / edgeZone
            delta = (factor * factor) * maxSpeed * CGFloat(dt)
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

    init(chat: Chat, grabAnchor: CGPoint) {
        self.grabAnchor = grabAnchor
        let chip = DragChipView(chat: chat)
        host = NSHostingView(rootView: AnyView(chip))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize.width > 0
            ? host.fittingSize
            : CGSize(width: 240, height: 32)

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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host
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
        // grabAnchor is in chip-local coords, top-left origin. Translate
        // to AppKit screen coords (bottom-left origin) so the cursor
        // stays at the same point on the chip the user originally
        // clicked when the drag began.
        let new = NSRect(
            x: cursor.x - grabAnchor.x,
            y: cursor.y - (frame.height - grabAnchor.y),
            width: frame.width,
            height: frame.height
        )
        panel.setFrame(new, display: false)
    }
}

/// Visual content of the drag chip. Mirrors a `RecentChatRow` (pin icon
/// + title + age) so the user reads it as the line they picked up.
private struct DragChipView: View {
    let chat: Chat

    private var ageLabel: String {
        L10n.relativeAge(elapsed: Date().timeIntervalSince(chat.createdAt))
    }

    var body: some View {
        HStack(spacing: 10) {
            PinIcon(size: 12.5)
                .foregroundColor(Color(white: 0.85))
                .frame(width: 14, height: 14)
            Text(chat.title.isEmpty
                 ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
                 : chat.title)
                .font(.system(size: 13.5, weight: .light))
                .foregroundColor(Color(white: 0.94))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ageLabel)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.6))
        }
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.40), radius: 14, x: 0, y: 8)
    }
}


