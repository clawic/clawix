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
        AppShortcut(
            intent: ShowLastCaptureIntent(),
            phrases: [
                "Show last \(.applicationName) capture"
            ],
            shortTitle: "Show last capture",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: PinLastCaptureIntent(),
            phrases: [
                "Pin last \(.applicationName) capture"
            ],
            shortTitle: "Pin last capture",
            systemImageName: "pin.fill"
        )
        AppShortcut(
            intent: CopyLastCaptureIntent(),
            phrases: [
                "Copy last \(.applicationName) capture"
            ],
            shortTitle: "Copy last capture",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: OpenLastCaptureIntent(),
            phrases: [
                "Open last \(.applicationName) capture"
            ],
            shortTitle: "Open last capture",
            systemImageName: "arrow.up.right.square"
        )
        AppShortcut(
            intent: RevealLastCaptureIntent(),
            phrases: [
                "Reveal last \(.applicationName) capture"
            ],
            shortTitle: "Reveal last capture",
            systemImageName: "folder"
        )
        AppShortcut(
            intent: RecognizeLastCaptureTextIntent(),
            phrases: [
                "Recognize last \(.applicationName) capture text",
                "Copy text from last \(.applicationName) capture"
            ],
            shortTitle: "Recognize capture text",
            systemImageName: "doc.text.viewfinder"
        )
        AppShortcut(
            intent: RevealCaptureFolderIntent(),
            phrases: [
                "Reveal \(.applicationName) capture folder"
            ],
            shortTitle: "Reveal capture folder",
            systemImageName: "folder"
        )
    }
}
