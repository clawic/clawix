import Foundation
import AppKit

/// User-customizable cancel shortcut. The default cancellation path
/// (double-tap Esc on the floating overlay, see
/// `DictationCoordinator.handleEscapeFromOverlay`) is unconditional and
/// always available; this binding lets a user remap *immediate*
/// cancellation onto another single-press combo (e.g. Cmd+. as in
/// macOS standard cancel, or Ctrl+G).
///
/// We don't try to re-implement the full KeyboardShortcuts framework
/// here. The model is intentionally simple: the user picks a key code
/// + modifier flags via the Settings recorder UI, we register a
/// global key-down monitor only while a recording is in flight, and we
/// fire `coordinator.cancel()` on a match.
///
/// Note on focus: the global monitor is gated by Input Monitoring TCC,
/// the same permission as `HotkeyManager`. The local monitor stays
/// installed unconditionally so cancellation works while Clawix
/// itself is frontmost.
@MainActor
final class CancelHotkey {

    static let shared = CancelHotkey()

    /// `true` when the toggle is enabled. Default false: the
    /// double-tap Esc behaviour is the canonical path; users opt into
    /// a custom shortcut.
    static let enabledKey = "dictation.cancelShortcut.enabled"
    /// `UInt16` virtual key code (0x33 for backspace, 0x35 for esc,
    /// etc.) stored as Int because @AppStorage doesn't take UInt16.
    static let keyCodeKey = "dictation.cancelShortcut.keyCode"
    /// `NSEvent.ModifierFlags.rawValue` masked to the canonical bits.
    static let modifierFlagsKey = "dictation.cancelShortcut.modifierFlags"

    private let defaults: UserDefaults
    private weak var coordinator: DictationCoordinator?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
        }
        // Default combo: Cmd+. (the standard macOS "cancel" key).
        // Stored even though the toggle is OFF by default so the
        // recorder shows a sensible value when the user enables it.
        if defaults.object(forKey: Self.keyCodeKey) == nil {
            defaults.set(0x2F, forKey: Self.keyCodeKey) // 0x2F = "."
        }
        if defaults.object(forKey: Self.modifierFlagsKey) == nil {
            // NSEvent.ModifierFlags.command.rawValue
            defaults.set(Int(NSEvent.ModifierFlags.command.rawValue), forKey: Self.modifierFlagsKey)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var keyCode: UInt16 { UInt16(defaults.integer(forKey: Self.keyCodeKey)) }
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Self.modifierFlagsKey)))
    }

    /// Wire up monitors. Idempotent. Safe to call from
    /// `register(coordinator:)` of `HotkeyManager` so both binding
    /// types come up at the same point in the app lifecycle.
    func register(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                Task { @MainActor in self.handle(event: event) }
                return event
            }
        }
        guard globalMonitor == nil else { return }
        guard DictationPermissions.inputMonitoring() == .granted else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handle(event: event) }
        }
    }

    /// Programmatic update. Called from the Settings recorder.
    func updateBinding(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        // Strip the device-dependent + non-modifier bits so we don't
        // store junk that won't match an incoming event.
        let canonical = modifierFlags.intersection(canonicalMask)
        defaults.set(Int(canonical.rawValue), forKey: Self.modifierFlagsKey)
    }

    // MARK: - Private

    private let canonicalMask: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift, .function
    ]

    private func handle(event: NSEvent) {
        guard isEnabled else { return }
        guard let coordinator else { return }
        // Only react while we're actually recording — the cancel
        // shortcut shouldn't tank a `.transcribing` task or fire while
        // the user is typing in another app with no session in flight.
        guard coordinator.state == .recording else { return }

        guard event.keyCode == keyCode else { return }
        let masked = event.modifierFlags.intersection(canonicalMask)
        guard masked == modifierFlags else { return }
        coordinator.cancel()
    }
}
