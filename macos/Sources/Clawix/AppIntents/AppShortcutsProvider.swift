import Foundation
import AppIntents

/// Bundles every Clawix `AppIntent` into the system's Shortcuts.app
/// catalog. The user sees these under "Clawix" in the Shortcuts.app
/// sidebar on macOS 13+, and system search surfaces them under the
/// declared phrases (`Start dictation`, `Stop dictation`, …).
///
/// Phrases must contain `\(.applicationName)` so Apple's matcher can
/// disambiguate the action from generic "start dictation" requests
/// that go to system Dictation. Keeping the phrases short keeps Siri
/// transcription accurate.
@available(macOS 13.0, *)
struct ClawixAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: [
                "Toggle \(.applicationName) dictation",
                "Start \(.applicationName) dictation",
                "Stop \(.applicationName) dictation"
            ],
            shortTitle: "Toggle dictation",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: CancelDictationIntent(),
            phrases: [
                "Cancel \(.applicationName) dictation"
            ],
            shortTitle: "Cancel dictation",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: PasteLastTranscriptionIntent(),
            phrases: [
                "Paste last \(.applicationName) transcription"
            ],
            shortTitle: "Paste last transcription",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: RetryLastTranscriptionIntent(),
            phrases: [
                "Retry last \(.applicationName) transcription"
            ],
            shortTitle: "Retry last transcription",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "New chat in \(.applicationName)",
                "Start a new \(.applicationName) chat"
            ],
            shortTitle: "New chat",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SendPromptIntent(),
            phrases: [
                "Send to \(.applicationName)",
                "Ask \(.applicationName)"
            ],
            shortTitle: "Send prompt",
            systemImageName: "paperplane.fill"
        )
        AppShortcut(
            intent: RestoreLastCaptureIntent(),
            phrases: [
                "Restore last \(.applicationName) capture",
                "Reopen last \(.applicationName) capture"
            ],
            shortTitle: "Restore last capture",
            systemImageName: "arrow.counterclockwise"
        )
    }
}
