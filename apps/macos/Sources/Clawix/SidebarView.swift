import SwiftUI
import UniformTypeIdentifiers

enum SidebarOrganizationMode: String { case byProject, recentProjects, chronological }
enum SidebarSortMode: String { case creation, updated }
enum SidebarShowFilter: String { case all, relevant }

/// UserDefaults suite used to persist sidebar preferences across launches.
/// Same suite already used for the main window frame and browser state.
enum SidebarPrefs {
    static let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
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
    @AppStorage("SidebarShowFilter", store: SidebarPrefs.store)
    private var showFilterRaw: String = SidebarShowFilter.all.rawValue
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
                sectionHeader("Pinned")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(snapshot.pinned) { chat in
                        ChatDropTarget { droppedId in
                            appState.reorderPinned(chatId: droppedId, beforeChatId: chat.id)
                            return true
                        } content: {
                            RecentChatRow(chat: chat, leadingIcon: .pin)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 0)
            }

            if organizationMode == .chronological {
                chronoHeader
                    .padding(.leading, 22)
                    .padding(.trailing, 9)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    .onHover { projectsHeaderHovered = $0 }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snapshot.chrono.prefix(chronoLimit))) { chat in
                        RecentChatRow(chat: chat)
                    }
                }
                .padding(.leading, 8)
            } else {
                projectsHeader
                    .padding(.leading, 22)
                    .padding(.trailing, 9)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    .onHover { projectsHeaderHovered = $0 }

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
                                onToggle: {
                                    if expandedProjects.contains(project.id) {
                                        expandedProjects.remove(project.id)
                                    } else {
                                        expandedProjects.insert(project.id)
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

                let projectlessChats = snapshot.chrono.filter { $0.projectId == nil }
                if !projectlessChats.isEmpty {
                    sectionHeader("No project")
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(projectlessChats) { chat in
                            RecentChatRow(chat: chat)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .padding(.bottom, 10)
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
                    .transition(.softNudge(y: -4))
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
                        sortModeRaw: $sortModeRaw,
                        showFilterRaw: $showFilterRaw
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

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(white: 0.55))
            Spacer()
        }
        .padding(.leading, 22)
        .padding(.trailing, 9)
        .padding(.top, 26)
        .padding(.bottom, 4)
    }

    private var projectsHeader: some View {
        sidebarHeader(title: "Projects", showCollapseAll: true, showNewChat: false)
    }

    private var chronoHeader: some View {
        sidebarHeader(title: "All chats", showCollapseAll: false, showNewChat: true, alwaysShow: true)
    }

    @ViewBuilder
    private func sidebarHeader(title: LocalizedStringKey, showCollapseAll: Bool, showNewChat: Bool, alwaysShow: Bool = false) -> some View {
        // Fixed-height header. Icons are always laid out (so the row never
        // changes height) and toggled with opacity + hit-testing only.
        let iconsVisible = alwaysShow || projectsHeaderHovered || newProjectMenuOpen || organizeMenuOpen
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(Color(white: 0.55))
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
                Button {
                    newProjectMenuOpen.toggle()
                } label: {
                    FolderAddIcon(size: 15)
                        .foregroundColor(Color(white: 0.78))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add new project")
                .anchorPreference(key: NewProjectAnchorKey.self, value: .bounds) { $0 }
                if showNewChat {
                    Button {
                        appState.currentRoute = .home
                    } label: {
                        ComposeIcon()
                            .stroke(Color(white: 0.78),
                                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 10.2, height: 10.2)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("New chat")
                }
            }
            .opacity(iconsVisible ? 0.78 : 0)
            .disabled(!iconsVisible)
            .animation(.easeOut(duration: 0.12), value: iconsVisible)
        }
        .frame(height: 24)
    }

    /// Funnel button that anchors `OrganizeMenuPopup` and uses the
    /// project-wide dropdown chrome.
    private var organizeButton: some View {
        Button {
            organizeMenuOpen.toggle()
        } label: {
            OrganizeFunnelIcon()
                .foregroundColor(Color(white: 0.78))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Filter, sort, and organize chats")
        .anchorPreference(key: OrganizeMenuAnchorKey.self, value: .bounds) { anchor in
            organizeMenuOpen ? anchor : nil
        }
    }

    @ViewBuilder
    private func headerIconButton(
        systemName: String,
        tooltip: String,
        anchorKey: NewProjectAnchorKey.Type? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(Color(white: 0.78))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .modifier(OptionalAnchorModifier(useAnchor: anchorKey != nil))
    }

    // MARK: - Header actions

    private func toggleAllProjectsCollapsed() {
        withAnimation(.easeOut(duration: 0.28)) {
            if expandedProjects.isEmpty {
                // Expand all
                expandedProjects = Set(appState.projects.map { $0.id })
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
            SettingsLimitsExpandableSection(expanded: $limitsExpanded)
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

// MARK: - Usage limits inline expandable section

/// Header + collapsible body for usage limits inside the account popover.
private struct SettingsLimitsExpandableSection: View {
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsLimitsHeaderRow(expanded: $expanded)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsLimitsValueRow(label: "5 h",
                                           percent: "100%",
                                           detail: "17:09")
                    SettingsLimitsValueRow(label: "Semanalmente",
                                           percent: "82%",
                                           detail: "5 may")
                    SettingsLimitsMoreInfoRow()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: expanded)
    }
}

private struct SettingsLimitsHeaderRow: View {
    @Binding var expanded: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: { expanded.toggle() }) {
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
                    .animation(.easeOut(duration: 0.18), value: expanded)
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

private struct SettingsLimitsValueRow: View {
    let label: String
    let percent: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(MenuStyle.rowText)
            Spacer(minLength: 8)
            Text(percent)
                .font(.system(size: 11.5))
                .foregroundColor(MenuStyle.rowText)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(MenuStyle.rowSubtle)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.leading, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
        .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
        .padding(.vertical, MenuStyle.rowVerticalPadding)
    }
}

private struct SettingsLimitsMoreInfoRow: View {
    @State private var hovered = false

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Text("More information")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: MenuStyle.rowTrailingIconSize, weight: .regular))
                    .foregroundColor(MenuStyle.rowSubtle)
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
                                    style: StrokeStyle(lineWidth: 1.235, lineCap: .round, lineJoin: .round))
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

// MARK: - PinnedIcon

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
                    appState.archiveChat(chatId: chat.id)
                } label: {
                    ArchiveIcon(size: 14)
                        .foregroundColor(archiveHovered ? Color(white: 0.94) : Color(white: 0.5))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { archiveHovered = $0 }
                .help("Archivar")
                .padding(.trailing, 2)
                .transition(.opacity)
            } else if chat.hasUnreadCompletion {
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
            // the macOS drag preview's label.
            let provider = NSItemProvider(object: chat.id.uuidString as NSString)
            provider.suggestedName = chat.title
            return provider
        }
        .contextMenu {
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
        if hovered    { return Color.white.opacity(0.035) }
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
    let onToggle: () -> Void
    let onMenuToggle: () -> Void
    let onNewChat: () -> Void
    let menuOpen: Bool

    @EnvironmentObject var appState: AppState
    @State private var hovered = false

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
                        .foregroundColor(Color(white: 0.55))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || menuOpen ? 1 : 0)
                .disabled(!(hovered || menuOpen))
                .help("More options")
                .anchorPreference(key: ProjectMenuAnchorKey.self, value: .bounds) { anchor in
                    menuOpen ? anchor : nil
                }

                // Pencil — start a new chat in this project (always visible)
                Button(action: onNewChat) {
                    ComposeIcon()
                        .stroke(Color(white: 0.50),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 11.2, height: 11.2)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .help("New chat in this project")
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered || menuOpen ? Color.white.opacity(0.04) : Color.clear)
            )
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.10), value: hovered || menuOpen)

            ExpandableContainer(expanded: expanded) {
                VStack(alignment: .leading, spacing: 3) {
                    if chats.isEmpty {
                        Text("No chats")
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(white: 0.40))
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

// MARK: - Organize / Sort / Show menu (funnel button next to the projects header)

private struct OrganizeMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Three-section dropdown: organization mode, sort field, visibility filter.
/// Each row shows a check on the active option; selections persist via the
/// caller's `@AppStorage`-backed bindings, so the popup itself is stateless.
private struct OrganizeMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var organizationModeRaw: String
    @Binding var sortModeRaw: String
    @Binding var showFilterRaw: String

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
            OrganizeMenuRow(
                icon: .system("arrow.down"),
                label: "Move down",
                isSelected: false
            ) {
                isPresented = false
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuHeader("Ordenar por")
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
                label: "Actualizados",
                isSelected: sortModeRaw == SidebarSortMode.updated.rawValue
            ) {
                sortModeRaw = SidebarSortMode.updated.rawValue
                isPresented = false
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuHeader("Show")
            OrganizeMenuRow(
                icon: .system("bubble.left.and.bubble.right"),
                label: "All chats",
                isSelected: showFilterRaw == SidebarShowFilter.all.rawValue
            ) {
                showFilterRaw = SidebarShowFilter.all.rawValue
                isPresented = false
            }
            OrganizeMenuRow(
                icon: .system("star"),
                label: "Relevant",
                isSelected: showFilterRaw == SidebarShowFilter.relevant.rawValue
            ) {
                showFilterRaw = SidebarShowFilter.relevant.rawValue
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
