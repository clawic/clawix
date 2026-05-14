import SwiftUI
import AppKit

// MARK: - Logged-out chrome

/// Whole-window layout shown while the user has no runtime credentials.
/// Reserves the titlebar band so the native traffic lights float cleanly
/// above LoginGateView. No sidebar, no resize handle, no right panel.
struct LoggedOutChrome: View {
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

struct SidebarTopChrome: View {
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

struct UpdateChip: View {
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
struct WindowChromeOverlay: View {
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

struct ContentTopChrome: View {
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

struct ChatActionsAnchorKey: PreferenceKey {
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
struct ContentBodyWithTerminal<Content: View>: View {
    @EnvironmentObject var appState: AppState
    let windowHeight: CGFloat
    let content: () -> Content

    @AppStorage(ClawixPersistentSurfaceKeys.terminalPanelOpen, store: SidebarPrefs.store)
    private var panelOpenRaw: Bool = false
    @AppStorage(ClawixPersistentSurfaceKeys.terminalPanelHeight, store: SidebarPrefs.store)
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

struct RightSidebarColumn: View {
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

struct RightSidebarTopChrome: View {
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

struct RightSidebarAddAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct RightSidebarBody: View {
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

struct RightSidebarAddMenu: View {
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

struct ChatActionsMenu: View {
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
