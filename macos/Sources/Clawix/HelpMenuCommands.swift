import SwiftUI
import AppKit

struct HelpMenuCommands: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button("Send feedback about \(appDisplayName) to Apple") {
            HelpMenuActions.sendFeedbackToApple()
        }

        Divider()

        Button("Model Context Protocol") {
            HelpMenuActions.open("https://modelcontextprotocol.io/")
        }

        Divider()

        Button("Start Performance Trace") {
            HelpMenuActions.startPerformanceTrace()
        }

        Divider()

        Button("Keyboard Shortcuts") {
            appState.isCommandPaletteOpen = true
        }
        .keyboardShortcut("/", modifiers: [.command])
    }
}

enum HelpMenuActions {
    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    static func sendFeedbackToApple() {
        open("https://www.apple.com/feedback/macos.html")
    }

    static func startPerformanceTrace() {
        NSSound.beep()
    }
}
