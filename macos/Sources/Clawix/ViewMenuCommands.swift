import SwiftUI

struct ViewMenuCommands: View {
    @ObservedObject var appState: AppState

    private var isChatRoute: Bool {
        if case .chat = appState.currentRoute { return true }
        return false
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
        Button("New Browser Tab") {
            appState.requestBrowserCommand(.newTab)
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
}
