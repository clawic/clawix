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
        Button("Open Browser Tab") {}
            .keyboardShortcut("t", modifiers: .command)
        Button("Reload Browser Page") {}
            .keyboardShortcut("r", modifiers: .command)
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

        Button("Zoom In") {}
            .keyboardShortcut("+", modifiers: .command)
        Button("Zoom Out") {}
            .keyboardShortcut("-", modifiers: .command)
        Button("Actual Size") {}
            .keyboardShortcut("0", modifiers: .command)
    }
}
