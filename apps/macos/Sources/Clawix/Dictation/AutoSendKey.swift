import Foundation
import AppKit
import Carbon.HIToolbox

/// Key combo posted automatically after the dictation transcript has
/// been pasted. Lets the user "dictate then send" in chat-style apps
/// without reaching for the keyboard, with the right combo for the
/// destination: plain Return for Slack/WhatsApp web, Shift+Return for
/// some forms, Cmd+Return for Linear/ChatGPT/GitHub PR comments.
///
/// Persisted via UserDefaults under `dictation.autoSendKey`. The
/// previous bool key (`dictation.autoEnter`) is migrated on app boot in
/// `DictationCoordinator.init`: false → `.none`, true → `.enter`.
public enum DictationAutoSendKey: String, CaseIterable, Codable, Sendable {
    /// Don't send — leave the cursor where the paste landed.
    case none
    /// Plain Return.
    case enter
    /// Shift+Return.
    case shiftEnter
    /// Command+Return.
    case cmdEnter

    public var displayName: String {
        switch self {
        case .none:       return "Don't send"
        case .enter:      return "Return"
        case .shiftEnter: return "Shift + Return"
        case .cmdEnter:   return "Command + Return"
        }
    }

    /// CGEvent flags applied to the synthesized Return.
    var modifierFlags: CGEventFlags {
        switch self {
        case .none, .enter: return []
        case .shiftEnter:   return .maskShift
        case .cmdEnter:     return .maskCommand
        }
    }
}
