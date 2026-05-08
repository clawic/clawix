import SwiftUI

struct ViewMenuCommands: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button("Toggle Sidebar") {
            appState.isLeftSidebarOpen.toggle()
        }
        .keyboardShortcut("b", modifiers: .command)
        Button("Toggle Terminal") {}
            .keyboardShortcut("j", modifiers: .command)
        Button("Toggle File Tree") {}
            .keyboardShortcut("e", modifiers: [.shift, .command])
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
        Button("Toggle Diff Panel") {}
            .keyboardShortcut("b", modifiers: [.option, .command])
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

        Button("Previous Chat") {}
            .keyboardShortcut("ñ", modifiers: [.shift, .command])
        Button("Next Chat") {}
            .keyboardShortcut("'", modifiers: [.shift, .command])
        Button("Back") {}
            .keyboardShortcut("ñ", modifiers: .command)
        Button("Forward") {}
            .keyboardShortcut("'", modifiers: .command)

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
