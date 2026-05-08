import SwiftUI
import AppKit

// MARK: - Data

struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let shortcut: String?
    let action: @MainActor (AppState) -> Void
}

struct PaletteSection: Identifiable {
    let id: String
    let title: String
    let items: [PaletteItem]
}

private enum PaletteCatalog {
    static let sections: [PaletteSection] = [
        PaletteSection(id: "sugerido", title: "Suggested", items: [
            PaletteItem(id: "new-chat", icon: "square.and.pencil",
                        title: "New chat", shortcut: "⌘N",
                        action: { FileMenuActions.newChat(appState: $0) }),
            PaletteItem(id: "open-folder", icon: "folder",
                        title: "Open folder", shortcut: "⌘O",
                        action: { FileMenuActions.openFolder(appState: $0) }),
            PaletteItem(id: "settings", icon: "gearshape",
                        title: "Settings", shortcut: "⌘,",
                        action: { $0.currentRoute = .settings }),
            PaletteItem(id: "find-files", icon: "magnifyingglass",
                        title: "Find files", shortcut: "⌘P",
                        action: { _ in NSSound.beep() }),
        ]),
        PaletteSection(id: "chat", title: "Chat", items: [
            PaletteItem(id: "find-chats", icon: "magnifyingglass",
                        title: "Find chats", shortcut: "⌘G",
                        action: { $0.currentRoute = .search }),
            PaletteItem(id: "quick-chat", icon: "square.and.pencil",
                        title: "New quick chat", shortcut: "⌥⌘N",
                        action: { FileMenuActions.quickChat(appState: $0) }),
            PaletteItem(id: "mini-window", icon: "macwindow.on.rectangle",
                        title: "Open in mini window", shortcut: nil,
                        action: { _ in NSSound.beep() }),
        ]),
        PaletteSection(id: "navegacion", title: "Navigation", items: [
            PaletteItem(id: "prev-chat", icon: "arrow.up",
                        title: "Previous chat", shortcut: "⇧⌘[",
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "next-chat", icon: "arrow.down",
                        title: "Next chat", shortcut: "⇧⌘]",
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "find", icon: "magnifyingglass",
                        title: "Find", shortcut: "⌘F",
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "back", icon: "arrow.left",
                        title: "Back", shortcut: "⌘[",
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "forward", icon: "arrow.right",
                        title: "Forward", shortcut: "⌘]",
                        action: { _ in NSSound.beep() }),
        ]),
        PaletteSection(id: "paneles", title: "Panels", items: [
            PaletteItem(id: "toggle-sidebar", icon: "sidebar.left",
                        title: "Toggle sidebar", shortcut: "⌘B",
                        action: { $0.isLeftSidebarOpen.toggle() }),
            PaletteItem(id: "toggle-terminal", icon: "apple.terminal",
                        title: "Toggle terminal", shortcut: "⌘J",
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "browser-tab", icon: "globe",
                        title: "Open browser tab", shortcut: "⌘T",
                        action: { $0.openBrowser() }),
            PaletteItem(id: "browser-panel", icon: "globe",
                        title: "Toggle browser panel", shortcut: "⇧⌘B",
                        action: { state in
                            if state.isRightSidebarOpen, case .web = state.activeSidebarItem {
                                state.closeBrowserPanel()
                            } else {
                                state.openBrowser()
                            }
                        }),
            PaletteItem(id: "diff-panel", icon: "plusminus",
                        title: "Toggle diff panel", shortcut: "⌥⌘B",
                        action: { _ in NSSound.beep() }),
        ]),
        PaletteSection(id: "habilidades", title: "Skills", items: [
            PaletteItem(id: "reload-skills", icon: "arrow.triangle.2.circlepath",
                        title: "Force reload skills", shortcut: nil,
                        action: { _ in NSSound.beep() }),
            /*
            PaletteItem(id: "go-skills", icon: "cube",
                        title: "Go to skills", shortcut: nil,
                        action: { $0.currentRoute = .plugins }),
            */
        ]),
        PaletteSection(id: "configurar", title: "Configure", items: [
            PaletteItem(id: "light-theme", icon: "sun.max",
                        title: "Switch to light theme", shortcut: nil,
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "mcp", icon: "paperclip",
                        title: "MCP", shortcut: nil,
                        action: { _ in NSSound.beep() }),
            PaletteItem(id: "personality", icon: "person.circle",
                        title: "Personality", shortcut: nil,
                        action: { _ in NSSound.beep() }),
        ]),
        PaletteSection(id: "aplicacion", title: "App", items: [
            // Automations row kept commented out for now.
            // PaletteItem(id: "automations", icon: "clock",
            //             title: "Manage automations", shortcut: nil,
            //             action: { $0.currentRoute = .automations }),
            PaletteItem(id: "logout", icon: "rectangle.portrait.and.arrow.right",
                        title: "Log out", shortcut: nil,
                        action: { $0.performBackendLogout() }),
        ]),
    ]
}

// MARK: - Overlay mount

struct CommandPaletteOverlay: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            if appState.isCommandPaletteOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { appState.isCommandPaletteOpen = false }
                    .transition(.opacity)

                CommandPaletteView(appState: appState)
                    .frame(width: 640)
                    .padding(.top, 96)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.16), value: appState.isCommandPaletteOpen)
        .ignoresSafeArea()
    }
}

// MARK: - Palette

struct CommandPaletteView: View {
    @ObservedObject var appState: AppState
    @State private var query: String = ""
    @State private var selectedID: String?
    @FocusState private var queryFocused: Bool

    private var filtered: [(PaletteSection, [PaletteItem])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return PaletteCatalog.sections.map { ($0, $0.items) }
        }
        return PaletteCatalog.sections.compactMap { section in
            let matches = section.items.filter { $0.title.lowercased().contains(q) }
            return matches.isEmpty ? nil : (section, matches)
        }
    }

    private var flatItems: [PaletteItem] {
        filtered.flatMap { $0.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            divider
            list
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.28)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 36, y: 18)
        .background(KeyEventHandler(
            onEscape: { appState.isCommandPaletteOpen = false },
            onUp: { moveSelection(by: -1) },
            onDown: { moveSelection(by: 1) },
            onReturn: { runSelected() }
        ))
        .onAppear {
            queryFocused = true
            selectedID = flatItems.first?.id
        }
        .onChange(of: query) { _ in
            if !flatItems.contains(where: { $0.id == selectedID }) {
                selectedID = flatItems.first?.id
            }
        }
    }

    private var searchField: some View {
        TextField("Type a command", text: $query)
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 16, wght: 500))
            .foregroundColor(Color(white: 0.92))
            .focused($queryFocused)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.0.id) { section, items in
                        sectionHeader(section.title)
                        ForEach(items) { item in
                            row(item)
                                .id(item.id)
                        }
                        Spacer().frame(height: 6)
                    }
                    if filtered.isEmpty {
                        Text("No results")
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(Color(white: 0.45))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
            .thinScrollers()
            .frame(maxHeight: 460)
            .onChange(of: selectedID) { id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Color(white: 0.50))
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func row(_ item: PaletteItem) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            execute(item)
        } label: {
            HStack(spacing: 14) {
                Group {
                    if item.icon == "magnifyingglass" {
                        SearchIcon(size: 14)
                    } else {
                        Image(systemName: item.icon)
                            .font(BodyFont.system(size: 14, weight: .regular))
                    }
                }
                .foregroundColor(Color(white: 0.85))
                .frame(width: 18, alignment: .center)
                Text(item.title)
                    .font(BodyFont.system(size: 14, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Spacer(minLength: 12)
                if let shortcut = item.shortcut {
                    ShortcutChip(text: shortcut)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedID = item.id }
        }
    }

    private func moveSelection(by delta: Int) {
        let items = flatItems
        guard !items.isEmpty else { return }
        let currentIdx = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let nextIdx = max(0, min(items.count - 1, currentIdx + delta))
        selectedID = items[nextIdx].id
    }

    private func runSelected() {
        guard let id = selectedID, let item = flatItems.first(where: { $0.id == id }) else { return }
        execute(item)
    }

    private func execute(_ item: PaletteItem) {
        appState.isCommandPaletteOpen = false
        let appState = appState
        DispatchQueue.main.async { item.action(appState) }
    }
}

// MARK: - Shortcut chip

private struct ShortcutChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11.5, wght: 500))
            .foregroundColor(Color(white: 0.62))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}

// MARK: - Local key handler

private struct KeyEventHandler: NSViewRepresentable {
    var onEscape: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onEscape = onEscape
        view.onUp = onUp
        view.onDown = onDown
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? KeyView else { return }
        v.onEscape = onEscape
        v.onUp = onUp
        v.onDown = onDown
        v.onReturn = onReturn
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? KeyView)?.detach()
    }

    final class KeyView: NSView {
        var onEscape: (() -> Void)?
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onReturn: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { attach() } else { detach() }
        }

        private func attach() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, event.window == win else { return event }
                switch event.keyCode {
                case 53:  self.onEscape?(); return nil
                case 126: self.onUp?(); return nil
                case 125: self.onDown?(); return nil
                case 36, 76: self.onReturn?(); return nil
                default: return event
                }
            }
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
