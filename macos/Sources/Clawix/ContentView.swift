import SwiftUI
import AppKit

let sidebarDefaultWidth: CGFloat = 372
let sidebarMaxWidth: CGFloat = 558           // 372 + 50%
let sidebarMinVisibleWidth: CGFloat = 220    // can't shrink below while open
let sidebarCloseThreshold: CGFloat = 200     // drag-release below → snap closed
// Settings sidebar is fixed-width and not user-resizable. ~20% narrower
// than the chat sidebar so the categories list reads tighter.
let settingsSidebarWidth: CGFloat = 298
let rightSidebarDefaultWidth: CGFloat = 720
let rightSidebarMaxWidth: CGFloat = 1080
let rightSidebarMinVisibleWidth: CGFloat = 380
let rightSidebarCloseThreshold: CGFloat = 320
private let contentCornerRadius: CGFloat = 14

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var flags: FeatureFlags

    @AppStorage("LeftSidebarWidth", store: SidebarPrefs.store)
    private var leftSidebarWidthRaw: Double = Double(sidebarDefaultWidth)

    @AppStorage("RightSidebarWidth", store: SidebarPrefs.store)
    private var rightSidebarWidthRaw: Double = Double(rightSidebarDefaultWidth)

    @State private var sidebarResizeHovered = false
    @State private var rightSidebarResizeHovered = false
    @State private var windowWidth: CGFloat = 0
    @State private var windowHeight: CGFloat = 0

    /// Floor reserved for the centre content column when the right
    /// sidebar grows. Without this, dragging the right sidebar past the
    /// window's available space would push the content column to zero
    /// and visually swallow the left sidebar.
    private let minContentColumnWidth: CGFloat = 420

    private var leftSidebarWidth: CGFloat {
        min(sidebarMaxWidth, max(sidebarMinVisibleWidth, CGFloat(leftSidebarWidthRaw)))
    }

    private var isSettingsRoute: Bool {
        if case .settings = visibleRoute { return true }
        return false
    }

    private var visibleRoute: SidebarRoute {
        appState.currentRoute.visibleRoute(isVisible: flags.isVisible)
    }

    private var leftColumnWidth: CGFloat {
        isSettingsRoute ? settingsSidebarWidth : leftSidebarWidth
    }

    /// Largest width the right sidebar can take given the current window
    /// size, so the left sidebar and a min content column are always
    /// preserved. Falls back to the persisted minimum until the window
    /// has been measured.
    private var dynamicRightSidebarMaxWidth: CGFloat {
        let leftWidth = appState.isLeftSidebarOpen ? leftColumnWidth : 0
        let raw = windowWidth - leftWidth - minContentColumnWidth
        let bounded = max(rightSidebarMinVisibleWidth, raw)
        return min(rightSidebarMaxWidth, bounded)
    }

    private var contentShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: contentCornerRadius,
            bottomLeadingRadius: contentCornerRadius,
            bottomTrailingRadius: appState.isRightSidebarOpen ? contentCornerRadius : 0,
            topTrailingRadius: appState.isRightSidebarOpen ? contentCornerRadius : 0,
            style: .continuous
        )
    }

    private var rightSidebarColumnWidth: CGFloat {
        let stored = max(rightSidebarMinVisibleWidth, CGFloat(rightSidebarWidthRaw))
        return min(dynamicRightSidebarMaxWidth, stored)
    }

    /// Colour painted under the content panel's top-trailing rounded
    /// corner cutout so the wedge revealed by the curve continues the
    /// adjacent right-sidebar column instead of leaking the underlying
    /// blur. The unified sidebar chrome is always solid black, so the
    /// wedge tracks the column whenever it's visible.
    private var trailingTopWedgeColor: Color {
        appState.isRightSidebarOpen ? .black : .clear
    }

    /// Colour painted under the bottom-trailing corner cutout. For web
    /// tabs, tracks the live page background sampled by the active tab's
    /// controller so the curve blends with whatever the user sees in the
    /// webview at that edge. File previews fall back to black.
    private var trailingBottomWedgeColor: Color {
        guard appState.isRightSidebarOpen else { return .clear }
        if let id = appState.activeWebTabId,
           let color = appState.browserPageBackgroundColors[id] {
            return color
        }
        return .black
    }

    @ViewBuilder
    private var trailingCornerWedges: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(trailingTopWedgeColor)
                    .frame(width: contentCornerRadius, height: contentCornerRadius)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(trailingBottomWedgeColor)
                    .frame(width: contentCornerRadius, height: contentCornerRadius)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.18), value: trailingBottomWedgeColor)
    }

    /// Routes whose body shows the composer accept drag-and-dropped
    /// files as composer attachments. Settings and Automations don't
    /// host the composer, so dropping there is silently ignored.
    private var routeAcceptsFileDrops: Bool {
        switch visibleRoute {
        case .home, .search, .plugins, .project, .chat:
            return true
        case .automations, .settings, .secretsHome, .databaseHome, .databaseWorkbench, .databaseCollection, .memoryHome,
             .indexHome, .marketplaceHome,
             .calendarHome, .contactsHome,
             .driveAdmin, .drivePhotos, .driveDocuments, .driveRecent, .driveFolder,
             .app, .appsHome, .skills, .skillDetail,
             .iotHome, .iotThingDetail,
             .designStylesHome, .designStyleDetail, .designTemplatesHome,
             .designTemplateDetail, .designReferencesHome, .designEditor,
             .agentsHome, .agentDetail, .personalitiesHome, .personalityDetail,
             .skillCollectionsHome, .skillCollectionDetail,
             .connectionsHome, .connectionDetail,
             .badgerHome, .badgerComposer, .badgerChannels,
             .lifeHome, .lifeVertical, .lifeSettings:
            return false
        }
    }

    private var routeRenderID: String {
        switch visibleRoute {
        case .home: return "home"
        case .search: return "search"
        case .plugins: return "plugins"
        case .automations: return "automations"
        case .project: return "project"
        case .chat(let id): return "chat-\(id.uuidString)"
        case .settings: return "settings"
        case .secretsHome: return "secrets"
        case .databaseHome: return "database"
        case .databaseWorkbench: return "database-workbench"
        case .databaseCollection(let name): return "database-\(name)"
        case .memoryHome: return "memory"
        case .indexHome: return "index"
        case .marketplaceHome: return "marketplace"
        case .calendarHome: return "calendar"
        case .contactsHome: return "contacts"
        case .driveAdmin: return "drive-admin"
        case .drivePhotos: return "drive-photos"
        case .driveDocuments: return "drive-documents"
        case .driveRecent: return "drive-recent"
        case .driveFolder(let id): return "drive-folder-\(id)"
        case .app(let id): return "app-\(id.uuidString)"
        case .appsHome: return "apps-home"
        case .skills: return "skills"
        case .skillDetail(let slug): return "skill-detail-\(slug)"
        case .iotHome: return "iot-home"
        case .iotThingDetail(let id): return "iot-thing-\(id)"
        case .designStylesHome: return "design-styles"
        case .designStyleDetail(let id): return "design-style-\(id)"
        case .designTemplatesHome: return "design-templates"
        case .designTemplateDetail(let id): return "design-template-\(id)"
        case .designReferencesHome: return "design-references"
        case .designEditor(let id): return "design-editor-\(id)"
        case .agentsHome: return "agents-home"
        case .agentDetail(let id): return "agent-detail-\(id)"
        case .personalitiesHome: return "personalities-home"
        case .personalityDetail(let id): return "personality-detail-\(id)"
        case .skillCollectionsHome: return "skill-collections-home"
        case .skillCollectionDetail(let id): return "skill-collection-detail-\(id)"
        case .connectionsHome: return "connections-home"
        case .connectionDetail(let id): return "connection-detail-\(id)"
        case .badgerHome: return "badger-home"
        case .badgerComposer(let prefill):
            return "badger-composer-\(prefill?.hashValue ?? 0)"
        case .badgerChannels: return "badger-channels"
        case .lifeHome: return "life-home"
        case .lifeVertical(let id): return "life-\(id)"
        case .lifeSettings: return "life-settings"
        }
    }

    var body: some View {
        RenderProbe.tick("ContentView")
        return ZStack(alignment: .topLeading) {
            // Sidebar blur fills the whole window so the rounded
            // corners of the content panel reveal the sidebar colour
            // (not a transparent gap to the wallpaper).
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .overlay(Color.black.opacity(0.26))
                .ignoresSafeArea()

            if !appState.auth.isLoggedIn {
                LoggedOutChrome()
            } else {

            HStack(spacing: 0) {
                // Sidebar column (chrome + sidebar list) — no own background
                if appState.isLeftSidebarOpen {
                    VStack(spacing: 0) {
                        SidebarTopChrome()
                        Group {
                            if case .settings = visibleRoute {
                                SettingsSidebar()
                                    .accessibilityElement(children: .contain)
                                    .accessibilityLabel("Settings categories")
                            } else {
                                SidebarView()
                                    .accessibilityElement(children: .contain)
                                    .accessibilityLabel("Sidebar")
                            }
                        }
                    }
                    .frame(width: leftColumnWidth)
                    .overlay(alignment: .trailing) {
                        // Straddle the trailing edge: 5 pt inside the
                        // sidebar, 5 pt outside (over the content column)
                        // so hover detection is symmetric around the edge.
                        // Hidden in settings: that sidebar is fixed-width.
                        if !isSettingsRoute {
                            SidebarResizeHandle(
                                widthRaw: $leftSidebarWidthRaw,
                                hovered: $sidebarResizeHovered
                            )
                            .frame(width: 10)
                            .offset(x: 5)
                            .zIndex(1)
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
                }

                // Content column (chrome + routed content). Hidden when
                // the right sidebar is maximized: the right sidebar grows
                // into this slot via `maxWidth: .infinity` so its file/web
                // viewer takes the chat area, and the chat composer is
                // re-anchored at the bottom of the right column instead
                // (see RightSidebarColumn).
                if !appState.isRightSidebarMaximized {
                VStack(spacing: 0) {
                    ContentTopChrome()
                        .id(routeRenderID)

                    ContentBodyWithTerminal(windowHeight: windowHeight) {
                        Group {
                            switch visibleRoute {
                            case .home:          MainContentView()
                            case .search:
                                MainContentView()
                                    .overlay(alignment: .top) {
                                        SearchPopoverOverlay()
                                            .padding(.top, 120)
                                    }
                            case .plugins:       MainContentView()
                            case .automations:   AutomationsView()
                            case .project:       MainContentView()
                            case .appsHome:      AppsHomeView()
                            case .app(let id):   AppSurfaceView(appId: id)
                            case .chat(let id):  ChatView(chatId: id)
                            case .settings:      SettingsContent()
                            case .secretsHome:   SecretsScreen()
                            case .databaseHome:  DatabaseScreen(mode: .admin)
                            case .databaseWorkbench: DatabaseWorkbenchView()
                            case .databaseCollection(let name):
                                DatabaseScreen(mode: .curated(collectionName: name))
                            case .memoryHome:    MemoryScreen()
                            case .indexHome:     IndexScreen()
                            case .marketplaceHome: MarketplaceScreen()
                            case .driveAdmin:    DriveScreen(mode: .admin)
                            case .drivePhotos:   DriveScreen(mode: .photos)
                            case .driveDocuments:DriveScreen(mode: .documents)
                            case .driveRecent:   DriveScreen(mode: .recent)
                            case .driveFolder(let id): DriveScreen(mode: .folder(id))
                            case .calendarHome:  CalendarScreen()
                            case .contactsHome:  ContactsScreen()
                            case .skills:        SkillsView()
                            case .skillDetail(let slug): SkillDetailView(slug: slug)
                            case .iotHome:       IoTScreen()
                            case .iotThingDetail(let id): IoTThingDetailView(thingId: id)
                            case .designStylesHome:           StylesHomeView()
                            case .designStyleDetail(let id):  StyleDetailView(styleId: id)
                            case .designTemplatesHome:        TemplatesHomeView()
                            case .designTemplateDetail(let id): TemplateDetailView(templateId: id)
                            case .designReferencesHome:       ReferencesHomeView()
                            case .designEditor(let id):       EditorView(documentId: id)
                            case .agentsHome:                 AgentsHomeView()
                            case .agentDetail(let id):        AgentDetailView(agentId: id)
                            case .personalitiesHome:          PersonalitiesHomeView()
                            case .personalityDetail(let id):  PersonalityDetailView(personalityId: id)
                            case .skillCollectionsHome:       SkillCollectionsHomeView()
                            case .skillCollectionDetail(let id): SkillCollectionDetailView(collectionId: id)
                            case .connectionsHome:            ConnectionsHomeView()
                            case .connectionDetail(let id):   ConnectionDetailView(connectionId: id)
                            case .badgerHome:                 BadgerHomeView()
                            case .badgerComposer(let prefill): BadgerComposerView(prefillBody: prefill)
                            case .badgerChannels:             BadgerChannelsView()
                            case .lifeHome:                   LifeHomeScreen()
                            case .lifeVertical(let id):       LifeVerticalScreen(verticalId: id)
                            case .lifeSettings:               LifeSettingsView()
                            }
                        }
                        .id(routeRenderID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background, in: contentShape)
                .background(trailingCornerWedges)
                .overlay(
                    ZStack {
                        // Always-visible faint border around the whole panel.
                        contentShape
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                        // Left-edge brightening on resize hover. Faded both
                        // horizontally (into the top/bottom edges) and
                        // vertically (away from the rounded corners) so the
                        // highlight never meets the base stroke at the apex
                        // of the curve.
                        contentShape
                            .stroke(Color.white.opacity(0.30), lineWidth: 0.7)
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: 26)
                                    LinearGradient(
                                        colors: [.white, .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 80)
                                    Color.clear
                                }
                                .mask(
                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            colors: [.clear, .white],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 50)
                                        Rectangle()
                                        LinearGradient(
                                            colors: [.white, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 50)
                                    }
                                )
                            )
                            .opacity(sidebarResizeHovered ? 1 : 0)
                            .animation(.easeOut(duration: 0.14), value: sidebarResizeHovered)
                    }
                )
                .bodyDropTarget(enabled: routeAcceptsFileDrops)
                } // end !isRightSidebarMaximized content column

                if appState.isRightSidebarOpen {
                    // Single instance with a stable modifier chain: only
                    // the .frame values flip on maximize. This preserves
                    // SwiftUI view identity for BrowserView/WKWebView so
                    // toggling expand resizes the column smoothly (just
                    // like dragging the resize handle) instead of tearing
                    // down and recreating the WebView tree.
                    RightSidebarColumn()
                        .frame(
                            maxWidth: appState.isRightSidebarMaximized ? .infinity : nil,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                        .frame(
                            width: appState.isRightSidebarMaximized ? nil : rightSidebarColumnWidth,
                            alignment: .leading
                        )
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 0.7)
                                .opacity(appState.isRightSidebarMaximized ? 0 : 1)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .leading) {
                            // Mirror of the left handle: straddle the
                            // leading edge (5 pt outside / 5 pt inside)
                            // for symmetric hover. Disabled while
                            // maximized so it can't be dragged from the
                            // window's leading edge.
                            SidebarResizeHandle(
                                widthRaw: $rightSidebarWidthRaw,
                                hovered: $rightSidebarResizeHovered,
                                side: .right,
                                maxWidthOverride: dynamicRightSidebarMaxWidth
                            )
                            .frame(width: 10)
                            .offset(x: -5)
                            .opacity(appState.isRightSidebarMaximized ? 0 : 1)
                            .allowsHitTesting(!appState.isRightSidebarMaximized)
                            .zIndex(1)
                        }
                        .zIndex(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: appState.isLeftSidebarOpen)
            .animation(.easeInOut(duration: 0.18), value: appState.isRightSidebarOpen)
            .animation(.easeInOut(duration: 0.28), value: appState.isRightSidebarMaximized)
            .animation(.easeInOut(duration: 0.18), value: appState.activeSidebarItem?.id)

            // Window-level chrome floats above the columns so the traffic
            // lights and the sidebar toggles never slide with a column.
            WindowChromeOverlay()
                .zIndex(100)

            } // end logged-in branch
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        windowWidth = proxy.size.width
                        windowHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.width) { _, w in windowWidth = w }
                    .onChange(of: proxy.size.height) { _, h in windowHeight = h }
            }
        )
        .onChange(of: appState.isRightSidebarOpen) { _, open in
            if !open && appState.isRightSidebarMaximized {
                appState.isRightSidebarMaximized = false
            }
        }
        .onChange(of: flags.beta) { _, _ in
            appState.enforceCurrentRouteVisibility()
        }
        .onChange(of: flags.experimental) { _, _ in
            appState.enforceCurrentRouteVisibility()
            appState.enforceExperimentalRuntimeVisibility()
        }
        .overlay(CommandPaletteOverlay(appState: appState))
        .overlay(ImagePreviewOverlay(appState: appState))
    }
}

// MARK: - Logged-out chrome

/// Whole-window layout shown while the user has no runtime credentials.
/// Reserves the titlebar band so the native traffic lights float cleanly
/// above LoginGateView. No sidebar, no resize handle, no right panel.
private struct LoggedOutChrome: View {
    @EnvironmentObject var appState: AppState

    private var contentShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: contentCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Reserve the titlebar strip so the native traffic lights
            // (close / miniaturize / zoom) float over a clear band above
            // the login content.
            Color.clear.frame(height: 38)

            LoginGateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background, in: contentShape)
                .overlay(
                    contentShape
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
        }
    }
}

// MARK: - Sidebar top chrome (traffic lights + nav arrows + reload pill)

private struct SidebarTopChrome: View {
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if updater.updateAvailable {
                UpdateChip { updater.installUpdate() }
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: 38)
        .background(WindowDragArea())
        .animation(.easeOut(duration: 0.20), value: updater.updateAvailable)
    }
}

private struct UpdateChip: View {
    var onTap: () -> Void
    @State private var hovered = false

    private static let fill = Color(red: 0.32, green: 0.48, blue: 0.92)

    var body: some View {
        Button(action: onTap) {
            Text("Update")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white.opacity(hovered ? 1.0 : 0.94))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Self.fill.opacity(hovered ? 1.0 : 0.88))
                )
                .scaleEffect(hovered ? 1.035 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.20), value: hovered)
        .help(L10n.t("Install the available update"))
    }
}

// MARK: - Window-level chrome (traffic lights + sidebar toggles)

/// Always-visible top bar with the traffic-light dots, the left sidebar
/// toggle and the right sidebar toggle. Floats above the column tree so
/// the toggles never slide with a column transition.
private struct WindowChromeOverlay: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var windowState: WindowState

    var body: some View {
        HStack(spacing: 0) {
            // Native traffic lights (close / miniaturize / zoom) float
            // over the top-left of the window. Reserve their footprint
            // when they're visible; in fullscreen macOS hides them so
            // the toggle slides flush to the leading edge.
            Color.clear.frame(width: windowState.isFullscreen ? 0 : 68, height: 1)

            SidebarToggleButton(
                side: .left,
                hitSize: 24,
                accessibilityLabel: appState.isLeftSidebarOpen ? "Hide sidebar" : "Show sidebar"
            ) {
                appState.isLeftSidebarOpen.toggle()
            }
            // Outside fullscreen the toggle sits next to the native traffic
            // lights; nudge it slightly right + down so it aligns with their
            // visual baseline. In fullscreen it goes back to the edge.
            .padding(.leading, windowState.isFullscreen ? 14 : 20)
            .padding(.top, windowState.isFullscreen ? 0 : 4)

            Spacer(minLength: 0)

            SidebarToggleButton(
                side: .right,
                hitSize: 24,
                accessibilityLabel: appState.isRightSidebarOpen ? "Hide right sidebar" : "Show right sidebar"
            ) {
                appState.isRightSidebarOpen.toggle()
            }
            .padding(.trailing, 14)
            // Mirror the left toggle's vertical offset so both icons share
            // the same baseline.
            .padding(.top, windowState.isFullscreen ? 0 : 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .animation(.easeInOut(duration: 0.18), value: windowState.isFullscreen)
    }
}

// MARK: - Content top chrome (right side)

private struct ContentTopChrome: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var windowState: WindowState
    @State private var chatActionsOpen = false
    @State private var hoverEllipsis = false

    private var currentChat: Chat? {
        if case .chat(let id) = appState.currentRoute {
            return appState.chat(byId: id)
        }
        return nil
    }

    private var chatTitle: String? { currentChat?.title }

    private var showsTerminalToggle: Bool {
        switch appState.currentRoute {
        case .chat, .home: return true
        default:           return false
        }
    }

    /// Folder path that the right-side "Open with" dropdown should target.
    /// Returns nil when the user has no real folder context (e.g. "Work on
    /// a Project" home), so the dropdown stays hidden.
    private var resolvedFolderPath: String? {
        if let chat = currentChat,
           let pid = chat.projectId,
           let proj = appState.projects.first(where: { $0.id == pid }) {
            let expanded = (proj.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        if let project = appState.selectedProject {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 4) {
            // When the left sidebar is hidden, the window chrome (traffic
            // lights + left toggle) sits over this column. Reserve its
            // footprint so the chat title doesn't slide under the toggle.
            // In fullscreen macOS hides the traffic lights, so the toggle
            // sits flush to the edge and the reservation shrinks. Animating
            // width keeps the layout shift smooth.
            Color.clear.frame(
                width: appState.isLeftSidebarOpen
                    ? 0
                    : (windowState.isFullscreen ? 38 : 96),
                height: 1
            )
            if let chatTitle, let _ = currentChat {
                Text(chatTitle)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 17)
                    .padding(.top, 6)
                Button { chatActionsOpen.toggle() } label: {
                    LucideIcon(.ellipsis, size: 18)
                        .foregroundColor(Color(white: hoverEllipsis ? 0.78 : 0.55))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoverEllipsis ? Color(white: 0.16) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .padding(.top, 6)
                .buttonStyle(.plain)
                .onHover { hoverEllipsis = $0 }
                .animation(.easeOut(duration: 0.12), value: hoverEllipsis)
                .accessibilityLabel("Chat actions")
                .anchorPreference(key: ChatActionsAnchorKey.self, value: .bounds) { $0 }
            }
            Spacer()
            if showsTerminalToggle {
                TerminalToggleButton()
                    .padding(.top, 6)
                    .padding(.trailing, 2)
            }
            EditorPickerDropdown(folderPath: resolvedFolderPath)
                .padding(.trailing, 8)
            // Reserve the trailing footprint of the window chrome's right
            // toggle when no right column sits between them.
            Color.clear.frame(width: appState.isRightSidebarOpen ? 0 : 30, height: 1)
        }
        .frame(height: 38)
        .background(WindowDragArea())
        .animation(.easeInOut(duration: 0.18), value: windowState.isFullscreen)
        .zIndex(1)
        .overlayPreferenceValue(ChatActionsAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if chatActionsOpen, let anchor, let chat = currentChat {
                    let buttonFrame = proxy[anchor]
                    ChatActionsMenu(
                        isOpen: $chatActionsOpen,
                        isPinned: chat.isPinned,
                        canCopyWorkingDirectory: !(chat.cwd ?? "").isEmpty,
                        canCopySessionID: !(chat.clawixThreadId ?? "").isEmpty,
                        canCopyMarkdown: !chat.messages.isEmpty,
                        onTogglePin: { appState.togglePin(chatId: chat.id) },
                        onRename: { appState.pendingRenameChat = chat },
                        onArchive: { appState.archiveChat(chatId: chat.id) },
                        onCopyWorkingDirectory: {
                            if let cwd = chat.cwd, !cwd.isEmpty {
                                setChatActionsPasteboard(cwd)
                            }
                        },
                        onCopySessionID: {
                            if let id = chat.clawixThreadId, !id.isEmpty {
                                setChatActionsPasteboard(id)
                            }
                        },
                        onCopyDirectLink: {
                            setChatActionsPasteboard("clawix://chat/\(chat.clawixThreadId ?? chat.id.uuidString)")
                        },
                        onCopyMarkdown: {
                            setChatActionsPasteboard(markdownTranscript(for: chat))
                        },
                        onForkConversation: {
                            appState.forkConversation(chatId: chat.id, sourceSnapshot: chat)
                        },
                        onOpenSideChat: {
                            appState.openInSideChat(parentChatId: chat.id)
                        }
                    )
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .leading()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(chatActionsOpen)
        }
        .animation(MenuStyle.openAnimation, value: chatActionsOpen)
        .sheet(item: Binding(
            get: { appState.pendingRenameChat },
            set: { appState.pendingRenameChat = $0 }
        )) { chat in
            ChatRenameSheet(chat: chat) { appState.pendingRenameChat = nil }
        }
        .sheet(item: Binding(
            get: { appState.pendingConfirmation },
            set: { appState.pendingConfirmation = $0 }
        )) { request in
            ConfirmationDialog(request: request) { appState.pendingConfirmation = nil }
        }
    }
}

private struct ChatActionsAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Integrated terminal panel mount

/// Wraps the route switch and, when the current route can host terminal
/// shells and the panel is toggled open, hangs the panel below it. The panel
/// height is persisted via `@AppStorage` and the top edge of the panel
/// straddles a `TerminalResizeHandle` for drag-to-resize.
private struct ContentBodyWithTerminal<Content: View>: View {
    @EnvironmentObject var appState: AppState
    let windowHeight: CGFloat
    let content: () -> Content

    @AppStorage("TerminalPanelOpen", store: SidebarPrefs.store)
    private var panelOpenRaw: Bool = false
    @AppStorage("TerminalPanelHeight", store: SidebarPrefs.store)
    private var panelHeightRaw: Double = Double(TerminalPanelMetrics.defaultHeight)
    @State private var resizeHovered: Bool = false

    init(windowHeight: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.windowHeight = windowHeight
        self.content = content
    }

    private var chatId: UUID? {
        switch appState.currentRoute {
        case .chat(let id): return id
        case .home:         return TerminalSessionStore.homeChatId
        default:            return nil
        }
    }

    private var panelOpen: Bool { chatId != nil && panelOpenRaw }

    /// Floor the chat area (composer + at least a couple of message
    /// rows) keeps from being eaten by an over-tall panel. Mirrors
    /// `dynamicRightSidebarMaxWidth` in spirit.
    private var maxPanelHeight: CGFloat {
        let usable = max(0, windowHeight - 240)
        return max(TerminalPanelMetrics.minHeight + 40, usable)
    }

    private var clampedPanelHeight: CGFloat {
        max(TerminalPanelMetrics.minHeight,
            min(maxPanelHeight, CGFloat(panelHeightRaw)))
    }

    private var terminalSeparatorMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80)
            Rectangle()
            LinearGradient(
                colors: [.white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let chatId {
                TerminalPanel(chatId: chatId, onLastTabClosed: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        panelOpenRaw = false
                    }
                })
                    .frame(height: panelOpen ? clampedPanelHeight : 0)
                    .allowsHitTesting(panelOpen)
                    .clipped()
                    .overlay(alignment: .top) {
                        if panelOpen {
                            ZStack(alignment: .top) {
                                ZStack(alignment: .top) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(height: 0.7)
                                        .mask(terminalSeparatorMask)
                                    Rectangle()
                                        .fill(Color.white.opacity(0.38))
                                        .frame(height: 0.7)
                                        .mask(terminalSeparatorMask)
                                        .opacity(resizeHovered ? 1 : 0)
                                        .animation(.easeOut(duration: 0.14), value: resizeHovered)
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                                .allowsHitTesting(false)
                                TerminalResizeHandle(
                                    heightRaw: $panelHeightRaw,
                                    hovered: $resizeHovered,
                                    maxHeightOverride: maxPanelHeight,
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            panelOpenRaw = false
                                        }
                                    }
                                )
                                .frame(height: 10)
                                .offset(y: -5)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: panelOpenRaw)
    }
}

// MARK: - Right sidebar column

private struct RightSidebarColumn: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var flags: FeatureFlags

    var body: some View {
        BrowserView()
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Right sidebar")
            .overlay(alignment: .topLeading) {
                if flags.isVisible(.simulators), !isSimulatorActive {
                    HStack(spacing: 6) {
                        Button {
                            appState.openIOSSimulator()
                        } label: {
                            Text("iOS")
                                .font(BodyFont.system(size: 11, wght: 700))
                                .foregroundColor(Color(white: 0.86))
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("iOS Simulator")

                        Button {
                            appState.openAndroidSimulator()
                        } label: {
                            Text("Android")
                                .font(BodyFont.system(size: 11, wght: 700))
                                .foregroundColor(Color(white: 0.86))
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Android Emulator")
                    }
                    .padding(.leading, 42)
                    .padding(.top, 7)
                }
            }
    }

    private var isSimulatorActive: Bool {
        if case .iosSimulator = appState.activeSidebarItem { return true }
        if case .androidSimulator = appState.activeSidebarItem { return true }
        return false
    }
}

private struct RightSidebarTopChrome: View {
    @EnvironmentObject var appState: AppState
    @State private var addMenuOpen = false
    @State private var hoverAdd = false
    @State private var hoverExpand = false
    @State private var panelExpanded = false
    // Secondary icons (`+`, expand) stay invisible while the column
    // slides in from the trailing edge, then fade in with opacity once
    // the panel has settled. The toggle itself remains visible the
    // whole time so it appears anchored to the window edge.
    @State private var secondaryVisible = false

    var body: some View {
        HStack(spacing: 0) {
            Button { addMenuOpen.toggle() } label: {
                LucideIcon(.plus, size: 13)
                    .foregroundColor(Color(white: 0.78))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoverAdd ? Color(white: 0.16) : Color(white: 0.115))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(white: 0.20), lineWidth: 0.7)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoverAdd = $0 }
            .animation(.easeOut(duration: 0.12), value: hoverAdd)
            .padding(.leading, 14)
            .accessibilityLabel("Add")
            .anchorPreference(key: RightSidebarAddAnchorKey.self, value: .bounds) { $0 }
            .opacity(secondaryVisible ? 1 : 0)

            Spacer(minLength: 0)

            Button {
                panelExpanded.toggle()
            } label: {
                CornerBracketsIcon(
                    size: 13,
                    variant: panelExpanded ? .collapsed : .expanded,
                    lineWidth: 1.6
                )
                .foregroundColor(hoverExpand ? Color(white: 0.78) : Color(white: 0.55))
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .onHover { hoverExpand = $0 }
            .animation(.easeOut(duration: 0.12), value: hoverExpand)
            .accessibilityLabel(panelExpanded ? "Collapse panel" : "Expand panel")
            .opacity(secondaryVisible ? 1 : 0)

            // The window chrome owns the right toggle; reserve its
            // footprint so the expand button doesn't slide under it.
            Color.clear.frame(width: 30, height: 1)
        }
        .frame(height: 38)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeOut(duration: 0.18)) {
                    secondaryVisible = true
                }
            }
        }
        .overlayPreferenceValue(RightSidebarAddAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if addMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    RightSidebarAddMenu(isOpen: $addMenuOpen)
                        .anchoredPopupPlacement(
                            buttonFrame: buttonFrame,
                            proxy: proxy,
                            horizontal: .leading()
                        )
                        .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(addMenuOpen)
        }
        .animation(MenuStyle.openAnimation, value: addMenuOpen)
    }
}

private struct RightSidebarAddAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct RightSidebarBody: View {
    var body: some View {
        ZStack {
            Color.clear
            Text("Nothing here yet")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RightSidebarAddMenu: View {
    @Binding var isOpen: Bool
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var flags: FeatureFlags
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(id: "open", icon: "magnifyingglass", title: "Open file", shortcut: "⌘P")
            MenuStandardDivider()
                .padding(.vertical, 4)
            if flags.isVisible(.browserUsage) {
                row(id: "browser", icon: "globe", title: "Browser", shortcut: "⌘T")
            }
            if flags.isVisible(.simulators) {
                row(id: "iosSimulator", icon: "app.window", title: "iOS Simulator", shortcut: "")
                row(id: "androidSimulator", icon: "smartphone", title: "Android Emulator", shortcut: "")
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 232)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    private func row(id: String, icon: String, title: LocalizedStringKey, shortcut: String) -> some View {
        Button {
            switch id {
            case "browser":
                appState.openBrowser()
            case "iosSimulator":
                appState.openIOSSimulator()
            case "androidSimulator":
                appState.openAndroidSimulator()
            default:
                break
            }
            isOpen = false
        } label: {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "magnifyingglass" {
                        SearchIcon(size: 11)
                    } else {
                        LucideIcon.auto(icon, size: 11)
                    }
                }
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)
                Text(title)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                Text(shortcut)
                    .font(BodyFont.system(size: 10, wght: 500))
                    .foregroundColor(MenuStyle.rowSubtle)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = id }
            else if hovered == id { hovered = nil }
        }
    }
}

// MARK: - Chat actions menu (ellipsis popover next to chat title)

private struct ChatActionsMenu: View {
    @Binding var isOpen: Bool
    let isPinned: Bool
    let canCopyWorkingDirectory: Bool
    let canCopySessionID: Bool
    let canCopyMarkdown: Bool
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void
    let onCopyWorkingDirectory: () -> Void
    let onCopySessionID: () -> Void
    let onCopyDirectLink: () -> Void
    let onCopyMarkdown: () -> Void
    let onForkConversation: () -> Void
    let onOpenSideChat: () -> Void
    @State private var hovered: String?

    private struct Item {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let shortcut: String?
        let enabled: Bool

        init(
            id: String,
            icon: String,
            title: LocalizedStringKey,
            shortcut: String?,
            enabled: Bool = true
        ) {
            self.id = id
            self.icon = icon
            self.title = title
            self.shortcut = shortcut
            self.enabled = enabled
        }
    }

    private var groups: [[Item]] {
        [
        [
            .init(id: "togglePin", icon: "pin",         title: isPinned ? "Unpin chat" : "Pin chat", shortcut: "⌥⌘P"),
            .init(id: "rename",   icon: "pencil",      title: "Rename chat", shortcut: "⌥⌘R"),
            .init(id: "archive",  icon: "archivebox",  title: "Archive chat",  shortcut: "⇧⌘A"),
        ],
        [
            .init(id: "copyCwd",  icon: "doc.on.doc",  title: "Copy working directory", shortcut: "⇧⌘C", enabled: canCopyWorkingDirectory),
            .init(id: "copyId",   icon: "doc.on.doc",  title: "Copy session ID",       shortcut: "⌥⌘C", enabled: canCopySessionID),
            .init(id: "copyLink", icon: "doc.on.doc",  title: "Copy direct link",        shortcut: "⌥⌘L"),
            .init(id: "copyMd",   icon: "doc.on.doc",  title: "Copy as Markdown",         shortcut: nil, enabled: canCopyMarkdown),
        ],
        [
            .init(id: "forkConv",      icon: "branchArrows",             title: "Fork conversation",        shortcut: nil),
            .init(id: "openSide",      icon: "plus.app",                 title: "Open side chat",         shortcut: nil),
        ],
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                if idx > 0 {
                    MenuStandardDivider()
                        .padding(.vertical, 4)
                }
                ForEach(group, id: \.id) { item in
                    row(item)
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 246)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    private func row(_ item: Item) -> some View {
        Button {
            guard item.enabled else { return }
            isOpen = false
            switch item.id {
            case "togglePin": onTogglePin()
            case "rename":    onRename()
            case "archive":   onArchive()
            case "copyCwd":    onCopyWorkingDirectory()
            case "copyId":     onCopySessionID()
            case "copyLink":   onCopyDirectLink()
            case "copyMd":     onCopyMarkdown()
            case "forkConv":  onForkConversation()
            case "openSide":  onOpenSideChat()
            default: break
            }
        } label: {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if item.icon == "pencil" {
                        PencilIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 15, height: 15)
                    } else if item.icon == "doc.on.doc" {
                        CopyIconViewSquircle(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 13, height: 13)
                    } else if item.icon == "archivebox" {
                        ArchiveIcon(size: 15)
                            .foregroundColor(MenuStyle.rowIcon)
                    } else if item.icon == "pin" {
                        PinIcon(size: 13, lineWidth: 1.0)
                            .foregroundColor(MenuStyle.rowIcon)
                    } else if item.icon == "branchArrows" {
                        BranchArrowsIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 14, height: 14)
                    } else {
                        IconImage(item.icon, size: 12)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(item.title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == item.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { hovering in
            if hovering && item.enabled { hovered = item.id }
            else if hovered == item.id { hovered = nil }
        }
    }
}

private func setChatActionsPasteboard(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
}

private func markdownTranscript(for chat: Chat) -> String {
    var lines: [String] = ["# \(chat.title)", ""]
    for message in chat.messages {
        let role = message.role == .user ? "User" : "Assistant"
        let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { continue }
        lines.append("## \(role)")
        lines.append("")
        lines.append(body)
        lines.append("")
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Search popover overlay

/// Bubbles the inner search-content's natural height (rows or empty
/// message) up to `SearchPopoverOverlay`, which uses it to size the
/// content slot. `max` so duplicate emissions converge on the tallest
/// reading.
private struct SearchContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SearchPopoverOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var queryFocused: Bool = false
    /// Natural height of the inner content (rows or empty message),
    /// measured via `SearchContentHeightKey`. The popup's content slot
    /// renders at this height, capped at `contentAreaMaxHeight`. Anchored
    /// to the popup's top so the search icon never moves; only the
    /// bottom edge tracks the result count.
    @State private var contentNaturalHeight: CGFloat = 220

    private static let popupCornerRadius: CGFloat = 26
    private static let popupStrokeColor = Color.white.opacity(0.18)
    private static let popupStrokeWidth: CGFloat = 0.9
    /// Cap on the result list. Past this, the inner content scrolls.
    private static let contentAreaMaxHeight: CGFloat = 350

    private var scopedProject: Project? {
        guard let id = appState.searchScopedProjectId else { return nil }
        return appState.projects.first(where: { $0.id == id })
    }

    private var pinnedChats: [Chat] {
        appState.chats
            .filter { $0.isPinned && !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredPinnedChats: [Chat] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pinnedChats }
        return searchableChats.filter { $0.title.lowercased().contains(q) }
    }

    private var searchableChats: [Chat] {
        appState.chats
            .filter { !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func scopedChats(for project: Project) -> [Chat] {
        appState.chats
            .filter { $0.projectId == project.id && !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func filteredScopedChats(for project: Project) -> [Chat] {
        let all = scopedChats(for: project)
        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) }
    }

    private func projectName(for chat: Chat) -> String? {
        guard let pid = chat.projectId else { return nil }
        return appState.projects.first(where: { $0.id == pid })?.name
    }

    private var sortedProjects: [Project] {
        appState.projects.sorted {
            $0.name.lowercased() < $1.name.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            divider
            content
                .frame(height: min(max(contentNaturalHeight, 1),
                                   Self.contentAreaMaxHeight),
                       alignment: .top)
                .onPreferenceChange(SearchContentHeightKey.self) { newValue in
                    contentNaturalHeight = newValue
                }
        }
        .frame(width: 560, alignment: .leading)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow,
                                 blendingMode: .withinWindow,
                                 state: .active)
                MenuStyle.fill
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.popupCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.popupCornerRadius, style: .continuous)
                    .stroke(Self.popupStrokeColor, lineWidth: Self.popupStrokeWidth)
            )
            .shadow(color: MenuStyle.shadowColor,
                    radius: MenuStyle.shadowRadius,
                    x: 0, y: MenuStyle.shadowOffsetY)
        )
        .background(MenuOutsideClickWatcher(isPresented: searchOpenBinding))
        .background(SearchKeyMonitor(
            query: $appState.searchQuery,
            onEscape: { closePopover() },
            onSelectIndex: { index in selectResult(at: index) },
            onSubmitFirst: { selectResult(at: 0) }
        ))
        .task {
            // Re-arming the focus in a Task keeps the textfield reliably
            // first responder even when the popup is reopened from the
            // same route, where onAppear sometimes fires before the
            // field is in the responder chain.
            queryFocused = true
            triggerScopedHistoryLoadIfNeeded()
        }
        .onChange(of: appState.searchScopedProjectId) { _, _ in
            queryFocused = true
            triggerScopedHistoryLoadIfNeeded()
        }
    }

    private func closePopover() {
        if appState.currentRoute == .search {
            appState.currentRoute = .home
        }
    }

    private func selectResult(at index: Int) {
        guard index >= 0 else { return }
        let chats: [Chat]
        if let project = scopedProject {
            chats = filteredScopedChats(for: project)
        } else {
            chats = filteredPinnedChats
        }
        guard index < min(chats.count, 9) else { return }
        appState.navigate(to: .chat(chats[index].id))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 14)
                .foregroundColor(Color(white: 0.55))
            if let project = scopedProject {
                ScopeChip(
                    name: project.name,
                    onRemove: { appState.searchScopedProjectId = nil }
                )
            }
            SearchQueryTextField(
                placeholder: scopedProject == nil
                    ? "Search chats"
                    : "Search in \(scopedProject!.name)",
                text: $appState.searchQuery,
                wantsFocus: queryFocused,
                onEscape: { closePopover() },
                onSelectIndex: { index in selectResult(at: index) },
                onSubmitFirst: { selectResult(at: 0) }
            )
            .frame(height: 20)
            if scopedProject == nil, !sortedProjects.isEmpty {
                projectFilterMenu
            }
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                } label: {
                    LucideIcon(.circleX, size: 13)
                        .foregroundColor(Color(white: 0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var projectFilterMenu: some View {
        Menu {
            ForEach(sortedProjects) { project in
                Button(project.name) {
                    appState.searchScopedProjectId = project.id
                }
            }
        } label: {
            FolderOpenIcon(size: 14)
                .foregroundColor(Color(white: 0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by project")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        if let project = scopedProject {
            scopedContent(for: project)
        } else {
            unscopedContent
        }
    }

    @ViewBuilder
    private var unscopedContent: some View {
        let pinned = filteredPinnedChats
        if !pinned.isEmpty {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty ? "Pinned chats" : "Matches")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(MenuStyle.headerText)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(pinned.prefix(9).enumerated()), id: \.element.id) { index, chat in
                            SearchPinnedRow(
                                title: chat.title,
                                projectName: projectName(for: chat),
                                shortcutNumber: index + 1,
                                isFirst: index == 0 && appState.searchQuery.isEmpty,
                                onSelect: { appState.navigate(to: .chat(chat.id)) }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(naturalHeightProbe)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .thinScrollers()
        } else {
            emptyContent(message: appState.searchQuery.isEmpty
                         ? "Search by chat title"
                         : "No matches")
        }
    }

    @ViewBuilder
    private func scopedContent(for project: Project) -> some View {
        let chats = filteredScopedChats(for: project)
        if chats.isEmpty {
            emptyContent(message: appState.searchQuery.isEmpty
                         ? "No chats in this project yet"
                         : "No matches")
        } else {
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(chats) { chat in
                        SearchScopedRow(
                            title: chat.title,
                            createdAt: chat.createdAt,
                            onSelect: { appState.navigate(to: .chat(chat.id)) }
                        )
                    }
                }
                .padding(.vertical, 8)
                .background(naturalHeightProbe)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .thinScrollers()
        }
    }

    private func emptyContent(message: LocalizedStringKey) -> some View {
        Text(message)
            .font(BodyFont.system(size: 13, wght: 500))
            .foregroundColor(MenuStyle.rowSubtle)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(naturalHeightProbe)
    }

    /// Transparent overlay used by the content branches to publish their
    /// unconstrained natural height to the popup so the outer frame can
    /// shrink to fit short lists and clip+scroll long ones.
    private var naturalHeightProbe: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: SearchContentHeightKey.self,
                            value: proxy.size.height)
        }
    }

    private var searchOpenBinding: Binding<Bool> {
        Binding(
            get: { appState.currentRoute == .search },
            set: { isOpen in
                if !isOpen, appState.currentRoute == .search {
                    appState.currentRoute = .home
                }
            }
        )
    }

    private func triggerScopedHistoryLoadIfNeeded() {
        // Pull the full project history into memory the moment a scope
        // is set, so the title filter sees every chat instead of just
        // the 10-row sidebar slice. Detached so the popup paints with
        // whatever's already cached and updates as rows arrive.
        guard let project = scopedProject else { return }
        Task.detached(priority: .userInitiated) { [project] in
            await appState.loadAllThreadsForProject(project)
        }
    }
}

private struct SearchKeyMonitor: NSViewRepresentable {
    @Binding var query: String
    var onEscape: () -> Void
    var onSelectIndex: (Int) -> Void
    var onSubmitFirst: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.query = $query
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onSubmitFirst = onSubmitFirst
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MonitorView else { return }
        view.query = $query
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onSubmitFirst = onSubmitFirst
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? MonitorView)?.detach()
    }

    final class Coordinator {
        var query: Binding<String>

        init(query: Binding<String>) {
            self.query = query
        }
    }

    final class MonitorView: NSView {
        var query: Binding<String>?
        var onEscape: (() -> Void)?
        var onSelectIndex: ((Int) -> Void)?
        var onSubmitFirst: (() -> Void)?
        private var monitor: Any?
        private let shortcutKeyCodes: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
            22: 5, 26: 6, 28: 7, 25: 8
        ]
        private let navigationKeyCodes: Set<UInt16> = [
            36, 48, 76, 115, 116, 119, 121, 123, 124, 125, 126
        ]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { attach() } else { detach() }
        }

        private func attach() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, NSApp.keyWindow === win else { return event }
                if event.keyCode == 53 {
                    self.onEscape?()
                    return nil
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.command),
                   let index = self.shortcutKeyCodes[event.keyCode] {
                    self.onSelectIndex?(index)
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.onSubmitFirst?()
                    return nil
                }
                if self.handleTextInput(event) {
                    return nil
                }
                return event
            }
        }

        private func handleTextInput(_ event: NSEvent) -> Bool {
            guard let query else { return false }
            if navigationKeyCodes.contains(event.keyCode) {
                return false
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return false
            }
            if event.keyCode == 51 {
                guard !query.wrappedValue.isEmpty else { return true }
                query.wrappedValue.removeLast()
                return true
            }
            guard let characters = event.characters, !characters.isEmpty else { return false }
            if characters.unicodeScalars.allSatisfy({ CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
                return false
            }
            query.wrappedValue.append(characters)
            return true
        }

        func detach() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { detach() }
    }
}

private struct SearchQueryTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let wantsFocus: Bool
    var onEscape: () -> Void
    var onSelectIndex: (Int) -> Void
    var onSubmitFirst: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusableSearchTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        field.textColor = NSColor(white: 0.94, alpha: 1)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.onEscape = onEscape
        field.onSelectIndex = onSelectIndex
        field.onSubmitFirst = onSubmitFirst
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onWindowReady = {
            guard context.coordinator.wantsFocus else { return }
            context.coordinator.focusIfNeeded(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.text = $text
        context.coordinator.wantsFocus = wantsFocus
        if let field = nsView as? FocusableSearchTextField {
            field.onEscape = onEscape
            field.onSelectIndex = onSelectIndex
            field.onSubmitFirst = onSubmitFirst
        }
        if wantsFocus {
            context.coordinator.focusIfNeeded(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var wantsFocus: Bool = false

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func focusIfNeeded(_ field: NSTextField) {
            if Self.fieldIsEditing(field) {
                return
            }
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                if Self.fieldIsEditing(field) { return }
                window.makeFirstResponder(field)
                Self.collapseSelectionToEnd(field)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak field] in
                guard let field, let window = field.window else { return }
                if Self.fieldIsEditing(field) { return }
                window.makeFirstResponder(field)
                Self.collapseSelectionToEnd(field)
            }
        }

        private static func fieldIsEditing(_ field: NSTextField) -> Bool {
            guard let window = field.window, let editor = field.currentEditor()
            else { return false }
            return window.firstResponder === editor
        }

        private static func collapseSelectionToEnd(_ field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }
}

private final class FocusableSearchTextField: NSTextField {
    var onWindowReady: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSelectIndex: ((Int) -> Void)?
    var onSubmitFirst: (() -> Void)?

    private let shortcutKeyCodes: [UInt16: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
        22: 5, 26: 6, 28: 7, 25: 8
    ]
    private let navigationKeyCodes: Set<UInt16> = [
        48, 115, 116, 119, 121, 123, 124, 125, 126
    ]

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowReady?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           let index = shortcutKeyCodes[event.keyCode] {
            onSelectIndex?(index)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onSubmitFirst?()
            return
        }
        if navigationKeyCodes.contains(event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }
}

private struct ScopeChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            FolderOpenIcon(size: 11)
                .foregroundColor(Color(white: 0.65))
            Text(name)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.88))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: onRemove) {
                LucideIcon(.x, size: 10)
                    .foregroundColor(Color(white: 0.62))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .fixedSize()
    }
}

private struct SearchScopedRow: View {
    let title: String
    let createdAt: Date
    let onSelect: () -> Void

    @State private var hovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var displayTitle: String {
        title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : title
    }

    var body: some View {
        HStack(spacing: 11) {
            LucideIcon(.messageCircle, size: 11)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(displayTitle)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            Text(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(MenuStyle.rowSubtle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            MenuRowHover(active: hovered)
        )
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open chat"), onSelect)
    }
}

private struct SearchPinnedRow: View {
    let title: String
    let projectName: String?
    let shortcutNumber: Int
    let isFirst: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var displayTitle: String {
        title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : title
    }

    var body: some View {
        HStack(spacing: 11) {
            PinIcon(size: 13, lineWidth: 1.0)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(displayTitle)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let projectName {
                Text(projectName)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .trailing)
            }

            ShortcutGlyph(number: shortcutNumber)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            MenuRowHover(
                active: hovered || isFirst,
                intensity: (hovered || isFirst) ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            )
        )
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(projectName ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open chat"), onSelect)
    }
}

private struct ShortcutGlyph: View {
    let number: Int

    var body: some View {
        Text("⌘\(number)")
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(MenuStyle.rowSubtle)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .frame(minWidth: 28, alignment: .center)
    }
}

// MARK: - Sidebar toggle icon (custom, replaces SF Symbol)

struct SidebarToggleIcon: View {
    enum Side { case left, right }
    var side: Side
    var size: CGFloat = 18
    var color: Color = Color(white: 0.55)

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height) / 24
            let lineW: CGFloat = 1.575 * s + 0.25
            let stroke = StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)

            // Outer rounded rectangle (square-ish, with softer corners).
            // Height shrunk 5% (17 → 16.15) and re-centred vertically.
            let outer = Path(roundedRect: CGRect(x: 3.5 * s, y: 3.925 * s, width: 17 * s, height: 16.15 * s),
                             cornerSize: CGSize(width: 4 * s, height: 4 * s),
                             style: .continuous)
            ctx.stroke(outer, with: .color(color), style: stroke)

            // Vertical mark near one inner edge; height shrunk 5% (10 → 9.5),
            // re-centred against the outer rect.
            let markX: CGFloat = (side == .left ? 7.5 : 16.5) * s
            var mark = Path()
            mark.move(to: CGPoint(x: markX, y: 7.25 * s))
            mark.addLine(to: CGPoint(x: markX, y: 16.75 * s))
            ctx.stroke(mark, with: .color(color), style: stroke)
        }
        .frame(width: size, height: size)
    }
}

/// Toggle button that brightens on hover, mirroring the sidebar header icons.
/// `SidebarToggleIcon` renders through `Canvas`, which does not interpolate
/// stroke colour between states. We render the canvas at full white and
/// animate the wrapper's `.opacity` instead so the transition shows the
/// same eased curve as the rest of the sidebar chrome.
struct SidebarToggleButton: View {
    let side: SidebarToggleIcon.Side
    var size: CGFloat = 18
    var hitSize: CGFloat? = nil
    var defaultOpacity: Double = 0.45
    var hoverOpacity: Double = 0.96
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            SidebarToggleIcon(side: side, size: size, color: .white)
                .opacity(hovered ? hoverOpacity : defaultOpacity)
                .frame(width: hitSize ?? size, height: hitSize ?? size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Shared colour palette

enum Palette {
    static let background    = Color(white: 0.04)
    static let sidebar       = Color(white: 0.245)
    static let cardFill      = Color(white: 0.14)
    static let cardHover     = Color(white: 0.17)
    static let border        = Color(white: 0.20)
    static let borderSubtle  = Color(white: 0.15)
    static let popupStroke   = Color.white.opacity(0.10)
    static let popupStrokeWidth: CGFloat = 0.5
    static let selFill       = Color(white: 0.28)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textTertiary  = Color(white: 0.38)
    static let pastelBlue    = Color(red: 0.45, green: 0.65, blue: 1.0)
}

// MARK: - Standard dropdown / popup menu style
// Project-wide canon: every dropdown, popover-style menu, edit menu and
// context menu must share this chrome.
enum MenuStyle {
    static let cornerRadius: CGFloat        = 12
    // Tinted fill on top of a blurred backdrop. Slight translucency lets the
    // wallpaper and chat content bleed through subtly.
    static let fill                         = Color(white: 0.135).opacity(0.82)
    static let shadowColor                  = Color.black.opacity(0.40)
    static let shadowRadius: CGFloat        = 18
    static let shadowOffsetY: CGFloat       = 10
    static let menuVerticalPadding: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 9
    static let rowVerticalPadding: CGFloat   = 6
    static let rowIconLabelSpacing: CGFloat  = 6
    static let rowTrailingIconExtra: CGFloat = 5
    static let rowTrailingIconSize: CGFloat  = 11
    static let rowHoverCornerRadius: CGFloat = 8
    static let rowHoverInset: CGFloat        = 4
    static let rowHoverIntensity: Double     = 0.06
    static let rowHoverIntensityStrong: Double = 0.08
    static let dividerColor                  = Color.white.opacity(0.06)
    static let rowText                       = Color(white: 0.94)
    static let rowIcon                       = Color(white: 0.86)
    static let rowSubtle                     = Color(white: 0.55)
    static let headerText                    = Color(white: 0.50)
    static let openAnimation                 = Animation.easeOut(duration: 0.20)
}

// Window content width, used by lateral submenus to decide whether they
// fit on the right of their anchor row or have to flip to the left.
@MainActor
func currentWindowContentWidth() -> CGFloat {
    NSApp.keyWindow?.contentView?.bounds.width ?? .infinity
}

/// Decides whether a horizontally cascading submenu should open on the
/// right (preferred) or flip to the left of its anchor row, based on
/// whether placing it on the right would overflow the window.
///
/// - parentGlobalMinX: the parent menu's leading edge in window-content
///   coordinates (`proxy.frame(in: .global).minX`).
/// - row: the anchor row's frame in the parent menu's local space.
/// - Returns: a tuple with the offset to feed into
///   `alignmentGuide(.leading) { _ in offset }` and a boolean that is
///   `true` when the submenu was placed on the right.
@MainActor
func submenuLeadingPlacement(parentGlobalMinX: CGFloat,
                             row: CGRect,
                             submenuWidth: CGFloat,
                             gap: CGFloat,
                             safetyMargin: CGFloat = 12) -> (offset: CGFloat, placedRight: Bool) {
    let rightEdgeIfPlacedRight = parentGlobalMinX + row.maxX + gap + submenuWidth
    let windowMaxX = currentWindowContentWidth() - safetyMargin
    if rightEdgeIfPlacedRight <= windowMaxX {
        return (-(row.maxX + gap), true)
    }
    return (-(row.minX - gap - submenuWidth), false)
}

extension View {
    /// Applies the canonical dropdown chrome: blurred backdrop + tinted
    /// rounded fill + thin popup stroke + soft shadow.
    ///
    /// `blurBehindWindow`: pass `true` when the menu lives in a standalone
    /// `NSPanel` (e.g. the sidebar's right-click context menu) so the
    /// blur samples the content behind the panel rather than the
    /// transparent panel-internal contents.
    ///
    /// `opaque`: drop the blur and the tint's translucency for menus that
    /// open over visually busy regions where the standard 18% bleed reads
    /// as a stacking glitch (e.g. file-card "Open" popup, where the parent
    /// card's translucent fill would otherwise show through the menu).
    func menuStandardBackground(blurBehindWindow: Bool = false,
                                opaque: Bool = false) -> some View {
        self.background(
            ZStack {
                if !opaque {
                    VisualEffectBlur(material: .hudWindow,
                                     blendingMode: blurBehindWindow ? .behindWindow : .withinWindow,
                                     state: .active)
                    MenuStyle.fill
                } else {
                    Color(white: 0.135)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
            .shadow(color: MenuStyle.shadowColor,
                    radius: MenuStyle.shadowRadius,
                    x: 0, y: MenuStyle.shadowOffsetY)
        )
    }
}

// MARK: - Sidebar resize handle

/// 10-pt wide strip straddling the trailing edge of the left sidebar
/// (5 pt inside, 5 pt outside), that drags the sidebar between
/// [sidebarMinVisibleWidth, sidebarMaxWidth].
///
/// The hit zone is implemented as an `NSView` that registers a system
/// cursor rect (`.resizeLeftRight`) via `addCursorRect`. That avoids the
/// flicker and "se sale todo el rato" problem you get from driving the
/// cursor with SwiftUI's `.onHover` + `NSCursor.set()`: the OS now owns
/// the cursor for that rect and stops it from being overridden by
/// neighbouring views.
///
/// Drag is also handled in `mouseDown`/`mouseDragged`/`mouseUp` so the
/// gesture survives even if the cursor briefly leaves the strip during
/// the drag (AppKit keeps mouse events flowing to the original target
/// until mouseUp).
///
/// Releasing below `sidebarCloseThreshold` snaps the sidebar closed and
/// resets the persisted width to the default for the next open.
enum SidebarResizeSide {
    case left
    case right

    var minWidth: CGFloat {
        self == .left ? sidebarMinVisibleWidth : rightSidebarMinVisibleWidth
    }
    var maxWidth: CGFloat {
        self == .left ? sidebarMaxWidth : rightSidebarMaxWidth
    }
    var closeThreshold: CGFloat {
        self == .left ? sidebarCloseThreshold : rightSidebarCloseThreshold
    }
    var defaultWidth: CGFloat {
        self == .left ? sidebarDefaultWidth : rightSidebarDefaultWidth
    }
    /// Sign applied to the horizontal drag delta when computing the new
    /// width. Dragging right grows the left sidebar (+1) but shrinks the
    /// right one (-1).
    var deltaSign: CGFloat {
        self == .left ? 1 : -1
    }
}

struct SidebarResizeHandle: View {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    var side: SidebarResizeSide = .left
    /// Tightens the upper bound below the side's static `maxWidth` when
    /// the surrounding layout cannot afford the full range (typically
    /// the right sidebar capped by the current window width minus the
    /// left sidebar and the min content column).
    var maxWidthOverride: CGFloat? = nil
    @EnvironmentObject var appState: AppState

    var body: some View {
        SidebarResizeNSViewBridge(
            widthRaw: $widthRaw,
            hovered: $hovered,
            side: side,
            maxWidthOverride: maxWidthOverride,
            onClose: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    switch side {
                    case .left:  appState.isLeftSidebarOpen = false
                    case .right: appState.isRightSidebarOpen = false
                    }
                }
            }
        )
    }
}

private struct SidebarResizeNSViewBridge: NSViewRepresentable {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    var side: SidebarResizeSide
    var maxWidthOverride: CGFloat?
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            widthRaw: $widthRaw,
            hovered: $hovered,
            side: side,
            maxWidthOverride: maxWidthOverride,
            onClose: onClose
        )
    }

    func makeNSView(context: Context) -> SidebarResizeNSView {
        let view = SidebarResizeNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SidebarResizeNSView, context: Context) {
        context.coordinator.widthRaw = $widthRaw
        context.coordinator.hovered = $hovered
        context.coordinator.side = side
        context.coordinator.maxWidthOverride = maxWidthOverride
        context.coordinator.onClose = onClose
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var widthRaw: Binding<Double>
        var hovered: Binding<Bool>
        var side: SidebarResizeSide
        var maxWidthOverride: CGFloat?
        var onClose: () -> Void
        init(
            widthRaw: Binding<Double>,
            hovered: Binding<Bool>,
            side: SidebarResizeSide,
            maxWidthOverride: CGFloat?,
            onClose: @escaping () -> Void
        ) {
            self.widthRaw = widthRaw
            self.hovered = hovered
            self.side = side
            self.maxWidthOverride = maxWidthOverride
            self.onClose = onClose
        }
    }
}

private final class SidebarResizeNSView: NSView {
    weak var coordinator: SidebarResizeNSViewBridge.Coordinator?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocationX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var isDragging = false
    private var moveMonitor: Any?

    override var isFlipped: Bool { true }

    // CRITICAL: window has `isMovableByWindowBackground = true`. Any view
    // that doesn't explicitly opt out of "background drag" lets the window
    // hijack mouseDown and start a window drag instead of forwarding the
    // event to us. That's why dragging the resize strip was moving the
    // whole window. Returning false here makes AppKit dispatch the click
    // to our `mouseDown` overrides.
    override var mouseDownCanMoveWindow: Bool { false }

    // Receive clicks even if the window isn't yet key (resize-on-first-click).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Window-level cursor rect: the system reapplies `.resizeLeftRight`
    // automatically every time the cursor is inside `bounds`, on every
    // mouse move, regardless of what other SwiftUI siblings are doing
    // with `NSCursor.set()`. This is the most reliable mechanism and is
    // the primary reason the resize cursor stays sticky across the whole
    // 10-pt strip. The tracking-area paths below are belt-and-braces.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        if window != nil {
            installMoveMonitor()
        } else {
            removeMoveMonitor()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    // Some other view (likely SwiftUI's hosting machinery or a sibling
    // sidebar row) is calling `NSCursor.set(.arrow)` during the same event
    // tick that we run our own cursorUpdate/mouseMoved overrides, so its
    // call lands AFTER ours and the resize cursor never sticks while just
    // hovering. Workaround: install an app-wide local monitor for
    // `.mouseMoved`, and when the cursor is inside our bounds defer
    // `NSCursor.resizeLeftRight.set()` to the next runloop turn via
    // `DispatchQueue.main.async`. That guarantees our `.set()` runs after
    // every other view has finished processing the event, so we win the
    // race deterministically.
    private func installMoveMonitor() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved]
        ) { [weak self] event in
            self?.applyResizeCursorIfInside(event: event)
            return event
        }
    }

    private func removeMoveMonitor() {
        if let m = moveMonitor {
            NSEvent.removeMonitor(m)
            moveMonitor = nil
        }
    }

    private func applyResizeCursorIfInside(event: NSEvent) {
        guard let window, event.window === window else { return }
        let mouseLocal = convert(event.locationInWindow, from: nil)
        guard bounds.contains(mouseLocal) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            // Re-check bounds at dispatch time using the CURRENT mouse
            // position, not the event's. Between the synchronous check
            // above and this dispatch the cursor may have left our strip
            // (the user moves fast into the sidebar). Setting the resize
            // cursor here would then strand it: the cursor is already
            // outside our `addCursorRect`, so the system won't see a
            // boundary crossing to reset it back to arrow until the user
            // re-enters and exits again. Result: the resize cursor
            // sticks while the user is navigating the sidebar.
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let local = self.convert(windowPoint, from: nil)
            guard self.bounds.contains(local) else { return }
            NSCursor.resizeLeftRight.set()
        }
    }

    deinit {
        removeMoveMonitor()
    }

    // Cursor is reapplied on every mouseMoved inside the strip, not just on
    // enter. `cursorUpdate` only fires once per entry, so whenever a sibling
    // SwiftUI view (text, buttons) calls `NSCursor.set()` afterwards it pins
    // the wrong cursor until the user leaves and re-enters. With `.mouseMoved`
    // the tracking area receives every move event regardless of the window's
    // `acceptsMouseMovedEvents`, and we re-set the resize cursor each time.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.hovered.wrappedValue = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            coordinator?.hovered.wrappedValue = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else { return }
        isDragging = true
        dragStartLocationX = event.locationInWindow.x
        dragStartWidth = CGFloat(coordinator.widthRaw.wrappedValue)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        // During a drag the cursor often leaves the 10-pt strip, which
        // means mouseMoved/cursorUpdate stop firing. Force the resize
        // cursor on every drag tick so it stays sticky.
        NSCursor.resizeLeftRight.set()
        let side = coordinator.side
        let maxW = min(side.maxWidth, coordinator.maxWidthOverride ?? .greatestFiniteMagnitude)
        let delta = (event.locationInWindow.x - dragStartLocationX) * side.deltaSign
        let proposed = dragStartWidth + delta
        let clamped = max(side.minWidth, min(maxW, proposed))
        coordinator.widthRaw.wrappedValue = Double(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        isDragging = false
        let side = coordinator.side
        let maxW = min(side.maxWidth, coordinator.maxWidthOverride ?? .greatestFiniteMagnitude)
        let delta = (event.locationInWindow.x - dragStartLocationX) * side.deltaSign
        let proposed = dragStartWidth + delta
        if proposed < side.closeThreshold {
            coordinator.onClose()
            coordinator.widthRaw.wrappedValue = Double(side.defaultWidth)
        } else {
            let clamped = max(side.minWidth, min(maxW, proposed))
            coordinator.widthRaw.wrappedValue = Double(clamped)
        }
        // If the cursor moved out during the drag, fold hover off now.
        let mouse = convert(event.locationInWindow, from: nil)
        if !bounds.contains(mouse) {
            coordinator.hovered.wrappedValue = false
        }
    }
}

/// Inset rounded hover highlight for menu rows. Mirrors the highlight used
/// by the model dropdown: a 7-pt rounded fill that breathes 5pt away from
/// the menu edges.
struct MenuRowHover: View {
    let active: Bool
    var intensity: Double = MenuStyle.rowHoverIntensity
    var body: some View {
        RoundedRectangle(cornerRadius: MenuStyle.rowHoverCornerRadius, style: .continuous)
            .fill(active ? Color.white.opacity(intensity) : Color.clear)
            .padding(.horizontal, MenuStyle.rowHoverInset)
    }
}
