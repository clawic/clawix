import Foundation
import KeyboardShortcuts

/// User-customizable keyboard-shortcut names for dictation quick
/// actions (#9). Each `KeyboardShortcuts.Name` is its own persisted
/// binding the user can record / clear from Settings, and the
/// framework handles global key-down via Carbon EventHotKey so the
/// shortcuts fire regardless of foreground app.
///
/// Defaults are deliberately blank so users opt in — global
/// hotkeys that fire by default in every other app would feel like
/// a regression. Settings UI shows an empty Recorder; the user
/// records whatever combo they like.
extension KeyboardShortcuts.Name {
    static let dictationToggle = Self("dictation.toggle")
    static let dictationCancel = Self("dictation.cancel")
    static let pasteLastTranscription = Self("dictation.pasteLast")
    static let retryLastTranscription = Self("dictation.retryLast")
    static let toggleEnhancement = Self("dictation.toggleEnhancement")
}

/// Wires every `KeyboardShortcuts.Name` declared above to its
/// runtime action. Idempotent: calling `installAll()` more than once
/// re-binds without leaking observers (the framework dedupes by
/// Name).
@MainActor
enum DictationShortcutsInstaller {
    static func installAll() {
        KeyboardShortcuts.onKeyUp(for: .dictationToggle) {
            DictationCoordinator.shared.toggleFromHotkey()
        }
        KeyboardShortcuts.onKeyUp(for: .dictationCancel) {
            DictationCoordinator.shared.cancel()
        }
        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) {
            try? LastTranscriptionStore.shared.pasteLastOriginal()
        }
        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) {
            Task { @MainActor in
                try? await LastTranscriptionStore.shared.retryLast()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleEnhancement) {
            let key = EnhancementSettings.enabledKey
            let current = UserDefaults.standard.bool(forKey: key)
            UserDefaults.standard.set(!current, forKey: key)
        }
    }
}
