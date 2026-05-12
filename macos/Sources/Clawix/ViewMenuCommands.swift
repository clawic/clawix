import SwiftUI

struct ViewMenuCommands: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var terminalStore = TerminalSessionStore.shared

    private var isChatRoute: Bool {
        if case .chat = appState.currentRoute { return true }
        return false
    }

    private var currentChatId: UUID? {
        if case let .chat(id) = appState.currentRoute { return id }
        return nil
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
            .disabled(!isChatRoute)
        Button("New Terminal") {
            createTerminalTab()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .disabled(!isChatRoute)
        Button("Close Terminal Tab") {
            closeActiveTerminalTab()
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])
        .disabled(!hasActiveTerminalTab)

        Divider()

        Button("New Browser Tab") {
            appState.openBrowser()
        }
        .keyboardShortcut("t", modifiers: .command)
        Button("Reload Browser Page") {
            appState.requestBrowserCommand(.reload)
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!appState.hasActiveWebTab)
        Button("Open Location") {
            appState.requestBrowserCommand(.focusURLBar)
        }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(!appState.hasActiveWebTab)
        Button("Close Browser Tab") {
            appState.requestBrowserCommand(.closeActiveTab)
        }
        .keyboardShortcut("w", modifiers: .command)
        .disabled(!appState.hasActiveWebTab)
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
        .disabled(!appState.hasActiveWebTab)
        Button("Zoom Out") {
            appState.requestBrowserCommand(.zoomOut)
        }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(!appState.hasActiveWebTab)
        Button("Actual Size") {
            appState.requestBrowserCommand(.zoomReset)
        }
        .keyboardShortcut("0", modifiers: .command)
        .disabled(!appState.hasActiveWebTab)
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
}
