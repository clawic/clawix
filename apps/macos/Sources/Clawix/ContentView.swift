import SwiftUI
import AppKit

let sidebarDefaultWidth: CGFloat = 372
let sidebarMaxWidth: CGFloat = 558           // 372 + 50%
let sidebarMinVisibleWidth: CGFloat = 220    // can't shrink below while open
let sidebarCloseThreshold: CGFloat = 200     // drag-release below → snap closed
let rightSidebarDefaultWidth: CGFloat = 720
let rightSidebarMaxWidth: CGFloat = 1080
let rightSidebarMinVisibleWidth: CGFloat = 380
let rightSidebarCloseThreshold: CGFloat = 320
private let contentCornerRadius: CGFloat = 14

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("LeftSidebarWidth", store: SidebarPrefs.store)
    private var leftSidebarWidthRaw: Double = Double(sidebarDefaultWidth)

    @AppStorage("RightSidebarWidth", store: SidebarPrefs.store)
    private var rightSidebarWidthRaw: Double = Double(rightSidebarDefaultWidth)

    @State private var sidebarResizeHovered = false
    @State private var rightSidebarResizeHovered = false
    @State private var windowWidth: CGFloat = 0

    /// Floor reserved for the centre content column when the right
    /// sidebar grows. Without this, dragging the right sidebar past the
    /// window's available space would push the content column to zero
    /// and visually swallow the left sidebar.
    private let minContentColumnWidth: CGFloat = 420

    private var leftSidebarWidth: CGFloat {
        min(sidebarMaxWidth, max(sidebarMinVisibleWidth, CGFloat(leftSidebarWidthRaw)))
    }

    /// Largest width the right sidebar can take given the current window
    /// size, so the left sidebar and a min content column are always
    /// preserved. Falls back to the persisted minimum until the window
    /// has been measured.
    private var dynamicRightSidebarMaxWidth: CGFloat {
        let leftWidth = appState.isLeftSidebarOpen ? leftSidebarWidth : 0
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
        switch appState.currentRoute {
        case .home, .search, .plugins, .project, .chat:
            return true
        case .automations, .settings:
            return false
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
                            if case .settings = appState.currentRoute {
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
                    .frame(width: leftSidebarWidth)
                    .overlay(alignment: .trailing) {
                        // Straddle the trailing edge: 5 pt inside the
                        // sidebar, 5 pt outside (over the content column)
                        // so hover detection is symmetric around the edge.
                        SidebarResizeHandle(
                            widthRaw: $leftSidebarWidthRaw,
                            hovered: $sidebarResizeHovered
                        )
                        .frame(width: 10)
                        .offset(x: 5)
                        .zIndex(1)
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

                    Group {
                        switch appState.currentRoute {
                        case .home:          MainContentView()
                        case .search:
                            MainContentView()
                                .overlay(alignment: .center) {
                                    SearchPopoverOverlay()
                                }
                        case .plugins:       MainContentView()
                        case .automations:   AutomationsView()
                        case .project:       MainContentView()
                        case .chat(let id):  ChatView(chatId: id)
                        case .settings:      SettingsContent()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Group {
                        if appState.isRightSidebarMaximized {
                            RightSidebarColumn()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            RightSidebarColumn()
                                .frame(width: rightSidebarColumnWidth, alignment: .leading)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.10))
                                        .frame(width: 0.7)
                                        .allowsHitTesting(false)
                                }
                                .overlay(alignment: .leading) {
                                    // Mirror of the left handle: straddle
                                    // the leading edge (5 pt outside / 5 pt
                                    // inside) for symmetric hover.
                                    SidebarResizeHandle(
                                        widthRaw: $rightSidebarWidthRaw,
                                        hovered: $rightSidebarResizeHovered,
                                        side: .right,
                                        maxWidthOverride: dynamicRightSidebarMaxWidth
                                    )
                                    .frame(width: 10)
                                    .offset(x: -5)
                                    .zIndex(1)
                                }
                                .zIndex(1)
                        }
                    }
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
                    .onAppear { windowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in windowWidth = w }
            }
        )
        .onChange(of: appState.isRightSidebarOpen) { _, open in
            if !open && appState.isRightSidebarMaximized {
                appState.isRightSidebarMaximized = false
            }
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
                .font(BodyFont.system(size: 12, weight: .regular))
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
                    .font(BodyFont.system(size: 13.5))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.leading, 17)
                    .padding(.top, 6)
                Button { chatActionsOpen.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(BodyFont.system(size: 11, weight: .semibold))
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
                        onTogglePin: { appState.togglePin(chatId: chat.id) },
                        onRename: { appState.pendingRenameChat = chat },
                        onArchive: { appState.archiveChat(chatId: chat.id) },
                        onForkConversation: {
                            appState.forkConversation(chatId: chat.id)
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

// MARK: - Right sidebar column

private struct RightSidebarColumn: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        BrowserView()
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Right sidebar")
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
                Image(systemName: "plus")
                    .font(BodyFont.system(size: 13, weight: .semibold))
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
                .font(BodyFont.system(size: 13))
                .foregroundColor(Color(white: 0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RightSidebarAddMenu: View {
    @Binding var isOpen: Bool
    @EnvironmentObject var appState: AppState
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(id: "open", icon: "magnifyingglass", title: "Open file", shortcut: "⌘P")
            MenuStandardDivider()
                .padding(.vertical, 4)
            row(id: "browser", icon: "globe", title: "Browser", shortcut: "⌘T")
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
                        Image(systemName: icon)
                            .font(BodyFont.system(size: 11))
                    }
                }
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)
                Text(title)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                Text(shortcut)
                    .font(BodyFont.system(size: 10))
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
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void
    let onForkConversation: () -> Void
    @State private var hovered: String?

    private struct Item {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let shortcut: String?
    }

    private var groups: [[Item]] {
        [
        [
            .init(id: "togglePin", icon: "pin",         title: isPinned ? "Unpin chat" : "Pin chat", shortcut: "⌥⌘P"),
            .init(id: "rename",   icon: "pencil",      title: "Rename chat", shortcut: "⌥⌘R"),
            .init(id: "archive",  icon: "archivebox",  title: "Archive chat",  shortcut: "⇧⌘A"),
        ],
        [
            .init(id: "copyCwd",  icon: "doc.on.doc",  title: "Copy working directory", shortcut: "⇧⌘C"),
            .init(id: "copyId",   icon: "doc.on.doc",  title: "Copy session ID",       shortcut: "⌥⌘C"),
            .init(id: "copyLink", icon: "doc.on.doc",  title: "Copy direct link",        shortcut: "⌥⌘L"),
            .init(id: "copyMd",   icon: "doc.on.doc",  title: "Copy as Markdown",         shortcut: nil),
        ],
        [
            .init(id: "forkConv",      icon: "branchArrows",             title: "Fork conversation",        shortcut: nil),
            .init(id: "openSide",      icon: "plus.app",                 title: "Open side chat",         shortcut: nil),
            .init(id: "forkLocal",     icon: "laptopcomputer",           title: "Fork to local",            shortcut: nil),
            .init(id: "forkWorktree",  icon: "arrow.triangle.branch",    title: "Fork to new worktree", shortcut: nil),
        ],
        [
            .init(id: "miniWindow", icon: "macwindow.on.rectangle", title: "Open in mini window", shortcut: nil),
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
            isOpen = false
            switch item.id {
            case "togglePin": onTogglePin()
            case "rename":    onRename()
            case "archive":   onArchive()
            case "forkConv":  onForkConversation()
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
                    .font(BodyFont.system(size: 13.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == item.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = item.id }
            else if hovered == item.id { hovered = nil }
        }
    }
}

// MARK: - Search popover overlay

private struct SearchPopoverOverlay: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var queryFocused: Bool

    private static let popupCornerRadius: CGFloat = 26
    private static let popupStrokeColor = Color.white.opacity(0.18)
    private static let popupStrokeWidth: CGFloat = 0.9

    private var pinnedChats: [Chat] {
        appState.chats
            .filter { $0.isPinned && !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredPinnedChats: [Chat] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pinnedChats }
        return pinnedChats.filter { $0.title.lowercased().contains(q) }
    }

    private func projectName(for chat: Chat) -> String? {
        guard let pid = chat.projectId else { return nil }
        return appState.projects.first(where: { $0.id == pid })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            divider
            content
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
        .onAppear { queryFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 14)
                .foregroundColor(Color(white: 0.55))
            TextField("Search chats", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 15))
                .foregroundColor(Color(white: 0.94))
                .focused($queryFocused)
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Color(white: 0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            let pinned = filteredPinnedChats
            if !pinned.isEmpty {
                Text("Pinned chats")
                    .font(BodyFont.system(size: 11.5))
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
                            onSelect: { appState.currentRoute = .chat(chat.id) }
                        )
                    }
                }
                .padding(.bottom, 8)
            } else if !appState.searchQuery.isEmpty {
                Text("No matches")
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            } else {
                Text("You do not have any pinned chats yet")
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
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
}

private struct SearchPinnedRow: View {
    let title: String
    let projectName: String?
    let shortcutNumber: Int
    let isFirst: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            PinIcon(size: 13, lineWidth: 1.0)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(BodyFont.system(size: 13.5))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let projectName {
                Text(projectName)
                    .font(BodyFont.system(size: 12))
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
    }
}

private struct ShortcutGlyph: View {
    let number: Int

    var body: some View {
        Text("⌘\(number)")
            .font(BodyFont.system(size: 11, weight: .medium))
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
        DispatchQueue.main.async {
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
