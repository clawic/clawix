import SwiftUI

struct ViewMenuCommands: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var flags = FeatureFlags.shared
    @ObservedObject private var terminalStore = TerminalSessionStore.shared

    private var canShowTerminal: Bool {
        switch appState.currentRoute {
        case .chat, .home: return true
        default:           return false
        }
    }

    private var currentChatId: UUID? {
        switch appState.currentRoute {
        case .chat(let id): return id
        case .home:         return TerminalSessionStore.homeChatId
        default:            return nil
        }
    }

    private var hasActiveTerminalTab: Bool {
        guard let currentChatId else { return false }
        return terminalStore.activeTabId(for: currentChatId) != nil
    }

    var body: some View {
        Button("Toggle Sidebar") {
            appState.isLeftSidebarOpen.toggle()
        }
        .keyboardShortcut("b", modifiers: .command)
        Button("Toggle Terminal") {
            let key = "TerminalPanelOpen"
            let current = SidebarPrefs.store.bool(forKey: key)
            SidebarPrefs.store.set(!current, forKey: key)
        }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(!canShowTerminal)
        Button("New Terminal") {
            createTerminalTab()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .disabled(!canShowTerminal)
        Button("Close Terminal Tab") {
            closeActiveTerminalTab()
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])
        .disabled(!hasActiveTerminalTab)

        Divider()

        Button(newTabLabel) {
            if terminalStore.keyboardFocused {
                createTerminalTab()
            } else {
                appState.openBrowser()
            }
        }
        .keyboardShortcut("t", modifiers: .command)
        .disabled(newTabDisabled)
        Button("Reload Browser Page") {
            appState.requestBrowserCommand(.reload)
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!flags.isVisible(.browserUsage) || !appState.hasActiveWebTab)
        Button("Open Location") {
            appState.requestBrowserCommand(.focusURLBar)
        }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(!flags.isVisible(.browserUsage) || !appState.hasActiveWebTab)
        Button(closeTabLabel) {
            if terminalStore.keyboardFocused {
                closeActiveTerminalTab()
            } else {
                appState.requestBrowserCommand(.closeActiveTab)
            }
        }
        .keyboardShortcut("w", modifiers: .command)
        .disabled(closeTabDisabled)
        Button("Find in Chat") {
            appState.openFindBar()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(!appState.canOpenFindBar)
        Button("Search Chats") {
            appState.currentRoute = .search
        }
        .keyboardShortcut("g", modifiers: .command)

        Divider()

        Button("Zoom In") {
            appState.requestBrowserCommand(.zoomIn)
        }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(!flags.isVisible(.browserUsage) || !appState.hasActiveWebTab)
        Button("Zoom Out") {
            appState.requestBrowserCommand(.zoomOut)
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(!flags.isVisible(.browserUsage) || !appState.hasActiveWebTab)
        Button("Actual Size") {
            appState.requestBrowserCommand(.zoomReset)
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(!flags.isVisible(.browserUsage) || !appState.hasActiveWebTab)
    }

    private func createTerminalTab() {
        guard let currentChatId else { return }
        let cwd = terminalStore.activeTab(for: currentChatId)?.initialCwd
            ?? appState.chat(byId: currentChatId)?.cwd
            ?? NSHomeDirectory()
        terminalStore.createTab(chatId: currentChatId, cwd: cwd)
        SidebarPrefs.store.set(true, forKey: "TerminalPanelOpen")
    }

    private func closeActiveTerminalTab() {
        guard let currentChatId,
              let active = terminalStore.activeTabId(for: currentChatId) else { return }
        terminalStore.closeTab(chatId: currentChatId, tabId: active)
    }

    private var newTabLabel: String {
        terminalStore.keyboardFocused ? "New Terminal" : "New Browser Tab"
    }

    private var closeTabLabel: String {
        terminalStore.keyboardFocused ? "Close Terminal" : "Close Browser Tab"
    }

    private var newTabDisabled: Bool {
        if terminalStore.keyboardFocused {
            return !canShowTerminal
        }
        return !flags.isVisible(.browserUsage)
    }

    private var closeTabDisabled: Bool {
        if terminalStore.keyboardFocused {
            return !hasActiveTerminalTab
        }
        return !flags.isVisible(.browserUsage) || !appState.hasActiveWebTab
    }
}
