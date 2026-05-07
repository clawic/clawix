import Foundation
import AppIntents

/// AppIntents that surface Clawix's dictation actions inside macOS
/// Shortcuts.app, Stream Deck plugins, BetterTouchTool, Raycast and
/// any other automation tool that consumes AppIntents.
///
/// We expose dictation actions as standalone intents (not parameterized
/// commands) so the user can bind a system-wide hotkey via
/// Shortcuts.app's "Run as keyboard shortcut" action — that's what
/// closes the loop with #9 (full key combos) without us having to
/// reimplement the binding UI inside Clawix.

@available(macOS 13.0, *)
struct ToggleDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle dictation"
    static var description = IntentDescription(
        "Start dictation if idle; stop dictation and paste the transcript if recording."
    )
    /// `openAppWhenRun` keeps Clawix backgrounded; the dictation
    /// pipeline doesn't need a foreground window.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationCoordinator.shared.toggleFromHotkey()
        return .result()
    }
}

@available(macOS 13.0, *)
struct CancelDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel dictation"
    static var description = IntentDescription(
        "Abandon the current dictation session without pasting."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationCoordinator.shared.cancel()
        return .result()
    }
}

@available(macOS 13.0, *)
struct PasteLastTranscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Paste last transcription"
    static var description = IntentDescription(
        "Re-paste the most recent dictation transcript at the cursor."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try LastTranscriptionStore.shared.pasteLastOriginal()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RetryLastTranscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Retry last transcription"
    static var description = IntentDescription(
        "Re-run transcription on the previous audio with the currently active model."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await LastTranscriptionStore.shared.retryLast()
        return .result()
    }
}
