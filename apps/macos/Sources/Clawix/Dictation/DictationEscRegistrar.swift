import AppKit
import Carbon.HIToolbox

/// Captures bare-Esc system-wide while a dictation session is active.
///
/// `addLocalMonitorForEvents` only delivers when *Clawix itself* is
/// frontmost, so a user dictating into another app would press Esc,
/// the foreground app would beep (it has nothing to consume Esc), and
/// the overlay's handler would never fire. The reference dictation
/// app fixes this with the `KeyboardShortcuts` package, which under
/// the hood calls Carbon's `RegisterEventHotKey` — that's the only
/// public macOS API that intercepts a chord for the calling process
/// regardless of frontmost app, *and* consumes the event so no beep
/// reaches the foreground app.
///
/// We keep this tightly scoped: register on `arm()` (called when the
/// pill becomes visible) and unregister on `disarm()` (when it goes
/// away). Bare Esc is intrusive — it breaks every other app's Esc
/// while armed — so the lifetime must match the recording session.
///
/// Patterned after `QuickAskHotkeyManager`. The signature char-code
/// (`ClDi` for "Clawix Dictation") is different so the two managers
/// don't fight over the same `EventHotKeyID`.
@MainActor
final class DictationEscRegistrar {

    static let shared = DictationEscRegistrar()

    /// Fired on the main thread on every Esc press while armed.
    /// `DictationOverlay` wires this to the coordinator's double-tap
    /// handler.
    var onPress: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Distinct four-CC signature ("ClDi") so registrations don't
    /// collide with `QuickAskHotkeyManager`'s ("Clwx") in the same
    /// process.
    private let signature: OSType = {
        let chars: [UInt8] = [0x43, 0x6C, 0x44, 0x69]
        return OSType(chars[0]) << 24 | OSType(chars[1]) << 16 | OSType(chars[2]) << 8 | OSType(chars[3])
    }()
    private let hotkeyID: UInt32 = 1

    private init() {}

    /// Install the Carbon handler (once) and register bare Esc as a
    /// hotkey. Safe to call repeatedly — re-registers idempotently.
    func arm() {
        installEventHandlerOnce()
        register()
    }

    /// Drop the bare-Esc registration so the rest of the system gets
    /// Esc back. The Carbon event handler stays installed (it's cheap
    /// and the next `arm()` is faster without re-installing).
    func disarm() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    // MARK: - Carbon plumbing

    private func installEventHandlerOnce() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon delivers the press on the main thread. We bridge to
        // Swift via an unretained pointer to `self`; the registrar is
        // a process-lifetime singleton so the pointer is always valid.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<DictationEscRegistrar>
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
            guard status == noErr else { return status }
            DispatchQueue.main.async {
                manager.onPress?()
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
        }
    }

    private func register() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        let id = EventHotKeyID(signature: signature, id: hotkeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0, // no modifier mask: bare Esc
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotkeyRef = ref
        }
    }
}
