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
let contentCornerRadius: CGFloat = 14

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var flags: FeatureFlags

    @AppStorage(ClawixPersistentSurfaceKeys.leftSidebarWidth, store: SidebarPrefs.store)
    private var leftSidebarWidthRaw: Double = Double(sidebarDefaultWidth)

    @AppStorage(ClawixPersistentSurfaceKeys.rightSidebarWidth, store: SidebarPrefs.store)
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
             .publishingHome, .publishingComposer, .publishingChannels,
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
        case .publishingHome: return "publishing-home"
        case .publishingComposer(let prefill):
            return "publishing-composer-\(prefill?.hashValue ?? 0)"
        case .publishingChannels: return "publishing-channels"
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
                            case .publishingHome:                 PublishingHomeView()
                            case .publishingComposer(let prefill): PublishingComposerView(prefillBody: prefill)
                            case .publishingChannels:             PublishingChannelsView()
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
