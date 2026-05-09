import AppKit
import Carbon.HIToolbox
import Combine

/// Persisted shape of a key-combo hotkey: a virtual key code plus a
/// bitmask of modifier flags (Cmd/Option/Ctrl/Shift) using Carbon's
/// numeric constants (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
///
/// We keep raw modifier bits rather than `NSEvent.ModifierFlags` so the
/// stored value round-trips losslessly into `RegisterEventHotKey`'s API
/// without conversion ambiguities.
struct QuickAskHotkey: Codable, Equatable {
    /// Virtual keycode (e.g. `kVK_Space`, `kVK_ANSI_K`).
    var keyCode: UInt32
    /// Carbon modifier mask (e.g. `cmdKey | optionKey | controlKey`).
    var modifiers: UInt32

    /// Default shortcut shipped on first launch: ⌃Space.
    /// Easy to reach with one hand, and configurable in Settings if
    /// the user has another global hotkey on this combo.
    static let defaultValue = QuickAskHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey)
    )

    /// Human-readable label like "⌃⌥⌘K". Used in Settings rows.
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyCodeDisplay(UInt16(keyCode))
        return s
    }
}

/// Maps a virtual keycode to the glyph macOS shows in menus. Covers the
/// keys we'll realistically let the user pick (letters, digits, common
/// special keys). Unknown codes fall back to a hex string so the
/// settings UI never renders an empty pill.
private func keyCodeDisplay(_ keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_Space:        return "Space"
    case kVK_Return:       return "↩"
    case kVK_Escape:       return "⎋"
    case kVK_Tab:          return "⇥"
    case kVK_Delete:       return "⌫"
    case kVK_ANSI_Slash:   return "/"
    case kVK_ANSI_Period:  return "."
    case kVK_ANSI_Comma:   return ","
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote:   return "'"
    case kVK_ANSI_LeftBracket:  return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Minus:   return "-"
    case kVK_ANSI_Equal:   return "="
    case kVK_F1:  return "F1"
    case kVK_F2:  return "F2"
    case kVK_F3:  return "F3"
    case kVK_F4:  return "F4"
    case kVK_F5:  return "F5"
    case kVK_F6:  return "F6"
    case kVK_F7:  return "F7"
    case kVK_F8:  return "F8"
    case kVK_F9:  return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default:
        return String(format: "0x%02X", keyCode)
    }
}

/// Process-wide global hotkey registered via Carbon's
/// `RegisterEventHotKey`, which is the only public macOS API that
/// reliably triggers a callback when the user presses a chord while
/// any other app has focus, without needing Accessibility or Input
/// Monitoring permission.
///
/// Single-instance: only one hotkey is registered at a time. Calling
/// `update(_:)` re-registers, which is what Settings does when the
/// user picks a new combo.
@MainActor
final class QuickAskHotkeyManager: ObservableObject {

    static let shared = QuickAskHotkeyManager()

    /// UserDefaults key holding the JSON-encoded `QuickAskHotkey`.
    /// Kept under the same suite as the rest of the app so a fork
    /// with a different bundle id gets isolated prefs automatically.
    static let defaultsKey = "quickAsk.hotkey"

    /// Published mirror so SwiftUI Settings views update when the user
    /// records a new combo.
    @Published private(set) var current: QuickAskHotkey = QuickAskHotkey.defaultValue

    /// Closure invoked on the main actor when the hotkey fires.
    /// Wired by `QuickAskController` at install time.
    var onTrigger: (() -> Void)?

    private let defaults: UserDefaults
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = loadFromDefaults() ?? QuickAskHotkey.defaultValue
    }

    /// Install the Carbon event handler and register the current
    /// shortcut. Idempotent: subsequent calls are no-ops.
    func install() {
        QuickAskDiag.log("hotkey install() current=\(current.displayString) keyCode=\(current.keyCode) modifiers=0x\(String(current.modifiers, radix: 16))")
        installEventHandler()
        registerCurrent()
    }

    /// Replace the active shortcut. Persists to defaults and
    /// re-registers immediately so the new combo is live without a
    /// relaunch.
    func update(_ hotkey: QuickAskHotkey) {
        current = hotkey
        saveToDefaults(hotkey)
        registerCurrent()
    }

    // MARK: - Carbon plumbing

    /// Four-CC signature owned by Clawix. Carbon needs an
    /// `OSType` (FourCharCode) per app to scope `EventHotKeyID`s; using
    /// our own avoids collisions with anything else loaded in-process.
    private let signature: OSType = {
        let chars: [UInt8] = [0x43, 0x6C, 0x77, 0x78] // "Clwx"
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()
    private let hotkeyID: UInt32 = 1

    private func installEventHandler() {
        guard eventHandler == nil else {
            QuickAskDiag.log("installEventHandler skipped (already installed)")
            return
        }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon delivers the press on the main thread. We bridge to
        // Swift via an unretained pointer to `self`; the manager is a
        // process-lifetime singleton so the pointer is always valid.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<QuickAskHotkeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr else {
                QuickAskDiag.log("Carbon callback: GetEventParameter failed status=\(status)")
                return status
            }
            QuickAskDiag.log("Carbon callback fired hkID.id=\(hkID.id) hkID.signature=0x\(String(hkID.signature, radix: 16))")
            DispatchQueue.main.async {
                if manager.onTrigger == nil {
                    QuickAskDiag.log("Carbon callback: onTrigger is nil, no-op")
                }
                manager.onTrigger?()
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
        if status == noErr {
            eventHandler = handlerRef
            QuickAskDiag.log("InstallEventHandler ok handlerRef=\(handlerRef != nil)")
        } else {
            QuickAskDiag.log("InstallEventHandler FAILED status=\(status)")
        }
    }

    private func registerCurrent() {
        // Drop any previous registration first, otherwise the OS keeps
        // both alive and the hotkey fires twice.
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        let id = EventHotKeyID(signature: signature, id: hotkeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            current.keyCode,
            current.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotkeyRef = ref
            QuickAskDiag.log("RegisterEventHotKey ok combo=\(current.displayString) ref=\(ref != nil)")
        } else {
            QuickAskDiag.log("RegisterEventHotKey FAILED status=\(status) combo=\(current.displayString) keyCode=\(current.keyCode) modifiers=0x\(String(current.modifiers, radix: 16))")
        }
    }

    // MARK: - Persistence

    private func loadFromDefaults() -> QuickAskHotkey? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(QuickAskHotkey.self, from: data)
    }

    private func saveToDefaults(_ hotkey: QuickAskHotkey) {
        guard let data = try? JSONEncoder().encode(hotkey) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
