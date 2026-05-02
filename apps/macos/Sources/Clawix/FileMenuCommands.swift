import SwiftUI
import AppKit

struct FileMenuCommands: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Close") {
            FileMenuActions.closeWindow()
        }
        .keyboardShortcut("w", modifiers: [.command])

        Button("New Window") {
            openWindow(id: FileMenuActions.mainWindowID)
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Button("New Chat") {
            FileMenuActions.newChat(appState: appState)
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("Quick Chat") {
            FileMenuActions.quickChat(appState: appState)
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button("Open Folder…") {
            FileMenuActions.openFolder(appState: appState)
        }
        .keyboardShortcut("o", modifiers: [.command])
    }
}

enum FileMenuActions {
    static let mainWindowID = "main"

    static func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    @MainActor
    static func newChat(appState: AppState) {
        appState.composer.text = ""
        appState.currentRoute = .home
        appState.requestComposerFocus()
    }

    @MainActor
    static func quickChat(appState: AppState) {
        appState.composer.text = ""
        appState.currentRoute = .home
        appState.requestComposerFocus()
    }

    @MainActor
    static func openFolder(appState: AppState) {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        let name = url.lastPathComponent
        if let existing = appState.projects.first(where: { ($0.path as NSString).expandingTildeInPath == path }) {
            appState.selectedProject = existing
        } else {
            let project = Project(id: UUID(), name: name, path: path)
            appState.projects.insert(project, at: 0)
            appState.selectedProject = project
        }
        appState.currentRoute = .project
    }
}
