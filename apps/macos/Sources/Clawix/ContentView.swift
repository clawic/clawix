import SwiftUI
import AppKit

let sidebarDefaultWidth: CGFloat = 372
let sidebarMaxWidth: CGFloat = 558           // 372 + 50%
let sidebarMinVisibleWidth: CGFloat = 220    // can't shrink below while open
let sidebarCloseThreshold: CGFloat = 200     // drag-release below → snap closed
private let rightSidebarWidth: CGFloat = 340
private let rightSidebarBrowserWidth: CGFloat = 720
private let contentCornerRadius: CGFloat = 14

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("LeftSidebarWidth", store: SidebarPrefs.store)
    private var leftSidebarWidthRaw: Double = Double(sidebarDefaultWidth)

    @State private var sidebarResizeHovered = false

    private var leftSidebarWidth: CGFloat {
        min(sidebarMaxWidth, max(sidebarMinVisibleWidth, CGFloat(leftSidebarWidthRaw)))
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
        switch appState.rightSidebarContent {
        case .browser:    return rightSidebarBrowserWidth
        case .empty:      return rightSidebarWidth
        case .fileViewer: return rightSidebarBrowserWidth
        }
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
                .overlay(Color.black.opacity(0.08))
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
                        SidebarResizeHandle(
                            widthRaw: $leftSidebarWidthRaw,
                            hovered: $sidebarResizeHovered
                        )
                        .frame(width: 10)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Content column (chrome + routed content)
                VStack(spacing: 0) {
                    ContentTopChrome()

                    Group {
                        switch appState.currentRoute {
                        case .home:          MainContentView()
                        case .search:
                            MainContentView()
                                .overlay(SearchPopoverOverlay().offset(x: -300, y: -70))
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
                .overlay(
                    ZStack {
                        // Always-visible faint border around the whole panel.
                        contentShape
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                        // Left-edge brightening on resize hover. Masked so the
                        // highlight covers only the two leading curves + the
                        // straight left side, fading into the top/bottom edges.
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
                            )
                            .opacity(sidebarResizeHovered ? 1 : 0)
                            .animation(.easeOut(duration: 0.14), value: sidebarResizeHovered)
                    }
                )
                .bodyDropTarget(enabled: routeAcceptsFileDrops)

                if appState.isRightSidebarOpen {
                    RightSidebarColumn()
                        .frame(width: rightSidebarColumnWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: appState.isLeftSidebarOpen)
            .animation(.easeInOut(duration: 0.18), value: appState.isRightSidebarOpen)
            .animation(.easeInOut(duration: 0.18), value: appState.rightSidebarContent)

            } // end logged-in branch
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay(CommandPaletteOverlay(appState: appState))
        .overlay(ImagePreviewOverlay(appState: appState))
    }
}

// MARK: - Logged-out chrome

/// Whole-window layout shown while the user has no runtime credentials. We
/// keep the traffic-light dots so the window stays draggable / closable
/// and place LoginGateView in the spot where the chat content normally
/// renders. No sidebar, no resize handle, no right panel.
private struct LoggedOutChrome: View {
    @EnvironmentObject var appState: AppState

    private var contentShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: contentCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.20)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.30)).frame(width: 12, height: 12)
                }
                .padding(.leading, 14)
                Spacer(minLength: 0)
            }
            .frame(height: 38)

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
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Real macOS-style colored traffic lights
            HStack(spacing: 8) {
                trafficDot(Color(red: 1.00, green: 0.37, blue: 0.34))
                trafficDot(Color(red: 1.00, green: 0.74, blue: 0.20))
                trafficDot(Color(red: 0.30, green: 0.78, blue: 0.30))
            }
            .padding(.leading, 14)

            // Sidebar-toggle icon
            Button {
                appState.isLeftSidebarOpen.toggle()
            } label: {
                SidebarToggleIcon(side: .left, size: 16, color: Color(white: 0.55))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .accessibilityLabel("Hide sidebar")

            // Disabled back / forward arrows
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.32))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.32))
            }
            .padding(.leading, 10)

            Spacer(minLength: 0)
        }
        .frame(height: 38)
    }

    private func trafficDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
    }
}

// MARK: - Content top chrome (right side)

private struct ContentTopChrome: View {
    @EnvironmentObject var appState: AppState
    @State private var chatActionsOpen = false
    @State private var hoverEllipsis = false
    @State private var chatRenameTarget: Chat?

    private var currentChat: Chat? {
        if case .chat(let id) = appState.currentRoute {
            return appState.chats.first(where: { $0.id == id })
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
            if !appState.isLeftSidebarOpen {
                // When the left sidebar is hidden, traffic-light dots and the
                // sidebar toggle migrate to the leading edge of the content
                // chrome so the user keeps a way to bring the sidebar back.
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.20)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.30)).frame(width: 12, height: 12)
                }
                .padding(.leading, 14)

                Button {
                    appState.isLeftSidebarOpen.toggle()
                } label: {
                    SidebarToggleIcon(side: .left, size: 16, color: Color(white: 0.55))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .accessibilityLabel("Show sidebar")
            }
            if let chatTitle, let _ = currentChat {
                Text(chatTitle)
                    .font(.system(size: 13.5))
                    .foregroundColor(Color(white: 0.83))
                    .padding(.leading, 17)
                    .padding(.top, 6)
                Button { chatActionsOpen.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
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
                .accessibilityLabel("Chat actions")
                .anchorPreference(key: ChatActionsAnchorKey.self, value: .bounds) { $0 }
            }
            Spacer()
            EditorPickerDropdown(folderPath: resolvedFolderPath)
                .padding(.trailing, 8)
            Button {
                appState.isRightSidebarOpen.toggle()
            } label: {
                SidebarToggleIcon(
                    side: .right,
                    size: 16,
                    color: appState.isRightSidebarOpen
                        ? Color(white: 0.78)
                        : Color(white: 0.42)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .accessibilityLabel("Show right sidebar")
        }
        .frame(height: 38)
        .zIndex(1)
        .overlayPreferenceValue(ChatActionsAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if chatActionsOpen, let anchor, let chat = currentChat {
                    let buttonFrame = proxy[anchor]
                    ChatActionsMenu(
                        isOpen: $chatActionsOpen,
                        isPinned: chat.isPinned,
                        onTogglePin: { appState.togglePin(chatId: chat.id) },
                        onRename: { chatRenameTarget = chat },
                        onArchive: { appState.archiveChat(chatId: chat.id) }
                    )
                    .offset(x: buttonFrame.minX, y: buttonFrame.maxY + 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(chatActionsOpen)
        }
        .animation(MenuStyle.openAnimation, value: chatActionsOpen)
        .sheet(item: $chatRenameTarget) { chat in
            ChatRenameSheet(chat: chat) { chatRenameTarget = nil }
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
        VStack(spacing: 0) {
            switch appState.rightSidebarContent {
            case .empty:
                RightSidebarTopChrome()
                RightSidebarBody()
            case .browser:
                BrowserView()
            case .fileViewer(let path):
                FileViewerPanel(path: path)
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            Button { addMenuOpen.toggle() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
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
            .padding(.leading, 14)
            .accessibilityLabel("Add")
            .anchorPreference(key: RightSidebarAddAnchorKey.self, value: .bounds) { $0 }

            Spacer(minLength: 0)

            Button {} label: {
                Image(systemName: "arrow.up.right.and.arrow.down.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(hoverExpand ? Color(white: 0.78) : Color(white: 0.55))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .onHover { hoverExpand = $0 }
            .accessibilityLabel("Expand panel")

            Button { appState.isRightSidebarOpen = false } label: {
                SidebarToggleIcon(side: .right, size: 16, color: Color(white: 0.78))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .accessibilityLabel("Hide right sidebar")
        }
        .frame(height: 38)
        .overlayPreferenceValue(RightSidebarAddAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if addMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    RightSidebarAddMenu(isOpen: $addMenuOpen)
                        .offset(x: buttonFrame.minX, y: buttonFrame.maxY + 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .font(.system(size: 13))
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
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                Text(shortcut)
                    .font(.system(size: 10))
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
            .init(id: "togglePin", icon: "pin",         title: isPinned ? "Unpin chat" : "Anclar chat", shortcut: "⌥⌘P"),
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
        .frame(width: 308)
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
            default: break
            }
        } label: {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if item.icon == "pencil" {
                        PencilIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 11, height: 11)
                    } else {
                        IconImage(item.icon, size: 11)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(item.title)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10))
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

    private var pinnedChats: [Chat] {
        appState.chats
            .filter { $0.isPinned && !$0.isArchived }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func projectName(for chat: Chat) -> String? {
        guard let pid = chat.projectId else { return nil }
        return appState.projects.first(where: { $0.id == pid })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find chats")
                .font(.system(size: 13))
                .foregroundColor(MenuStyle.headerText)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)

            if !pinnedChats.isEmpty {
                Text("Pinned chats")
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.headerText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(pinnedChats.prefix(9).enumerated()), id: \.element.id) { index, chat in
                        SearchPinnedRow(
                            title: chat.title,
                            projectName: projectName(for: chat),
                            shortcutNumber: index + 1,
                            isFirst: index == 0,
                            onSelect: { appState.currentRoute = .chat(chat.id) }
                        )
                    }
                }
                .padding(.bottom, 4)
            } else {
                Text("You do not have any pinned chats yet")
                    .font(.system(size: 13))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 560, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: searchOpenBinding))
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
            Image(systemName: "macwindow")
                .font(.system(size: 13))
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(.system(size: 13.5))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let projectName {
                Text(projectName)
                    .font(.system(size: 12))
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
            .font(.system(size: 11, weight: .medium))
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
    var size: CGFloat = 16
    var color: Color = Color(white: 0.55)

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height) / 24
            let lineW: CGFloat = 1.575 * s
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
    func menuStandardBackground() -> some View {
        self.background(
            ZStack {
                VisualEffectBlur(material: .hudWindow,
                                 blendingMode: .withinWindow,
                                 state: .active)
                MenuStyle.fill
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
struct SidebarResizeHandle: View {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        SidebarResizeNSViewBridge(
            widthRaw: $widthRaw,
            hovered: $hovered,
            onClose: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.isLeftSidebarOpen = false
                }
            }
        )
    }
}

private struct SidebarResizeNSViewBridge: NSViewRepresentable {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(widthRaw: $widthRaw, hovered: $hovered, onClose: onClose)
    }

    func makeNSView(context: Context) -> SidebarResizeNSView {
        let view = SidebarResizeNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SidebarResizeNSView, context: Context) {
        context.coordinator.widthRaw = $widthRaw
        context.coordinator.hovered = $hovered
        context.coordinator.onClose = onClose
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var widthRaw: Binding<Double>
        var hovered: Binding<Bool>
        var onClose: () -> Void
        init(widthRaw: Binding<Double>, hovered: Binding<Bool>, onClose: @escaping () -> Void) {
            self.widthRaw = widthRaw
            self.hovered = hovered
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
        let delta = event.locationInWindow.x - dragStartLocationX
        let proposed = dragStartWidth + delta
        let clamped = max(sidebarMinVisibleWidth, min(sidebarMaxWidth, proposed))
        coordinator.widthRaw.wrappedValue = Double(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        isDragging = false
        let delta = event.locationInWindow.x - dragStartLocationX
        let proposed = dragStartWidth + delta
        if proposed < sidebarCloseThreshold {
            coordinator.onClose()
            coordinator.widthRaw.wrappedValue = Double(sidebarDefaultWidth)
        } else {
            let clamped = max(sidebarMinVisibleWidth, min(sidebarMaxWidth, proposed))
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
