import Foundation
import KeyboardShortcuts

/// User-customizable bindings for the integrated terminal panel.
/// Defaults track VS Code-ish conventions where they don't collide
/// with macOS or Clawix shortcuts:
///
///   ⌃`        toggle panel
///   ⇧⌘T       new terminal
///   ⇧⌘W       close terminal tab (NOT ⌘W — reserved for future
///              "close window" semantics)
///   ⇧⌘]/[     next / previous tab
///   ⌘D        split vertical
///   ⇧⌘D       split horizontal
extension KeyboardShortcuts.Name {
    static let terminalToggle = Self(
        "terminal.toggle",
        default: .init(.backtick, modifiers: [.control])
    )
    static let terminalNewTab = Self(
        "terminal.newTab",
        default: .init(.t, modifiers: [.command, .shift])
    )
    static let terminalCloseTab = Self(
        "terminal.closeTab",
        default: .init(.w, modifiers: [.command, .shift])
    )
    static let terminalNextTab = Self(
        "terminal.nextTab",
        default: .init(.rightBracket, modifiers: [.command, .shift])
    )
    static let terminalPreviousTab = Self(
        "terminal.previousTab",
        default: .init(.leftBracket, modifiers: [.command, .shift])
    )
    static let terminalSplitVertical = Self(
        "terminal.splitVertical",
        default: .init(.d, modifiers: [.command])
    )
    static let terminalSplitHorizontal = Self(
        "terminal.splitHorizontal",
        default: .init(.d, modifiers: [.command, .shift])
    )
}
