import Foundation
import AppKit

/// Modes the user can pick from in Settings for how the hotkey behaves.
enum DictationHotkeyMode: String, CaseIterable, Codable {
    /// Tap = toggle on/off; hold (longer than `holdThreshold`) = push
    /// to talk and release to stop. The default — covers both styles
    /// without making the user pick.
    case hybrid
    /// Always push-to-talk: hold to record, release to stop.
    case pushToTalk
    /// Always toggle: tap to start, tap again to stop.
    case toggle
}

/// Trigger options for the dictation hotkey. Default is `.off` —
/// shipping a bare modifier as the default would fire on every Right
/// Command press and feel like a runaway. The user opts in from
/// Settings > Voice to Text once they've downloaded a model.
enum DictationHotkeyTrigger: String, CaseIterable, Codable {
    case off
    case rightCommand
    case rightOption
    case rightControl
    case rightShift
    case fn

    /// Virtual key code emitted in `event.keyCode` when the modifier
    /// transitions. Right modifiers and Fn live above 0x36; left
    /// modifiers (0x37 etc.) are intentionally omitted to leave Cmd+V
    /// and Cmd+C alone. `.off` returns a code that never fires.
    var keyCode: UInt16 {
        switch self {
        case .off:          return 0xFFFF
        case .rightCommand: return 0x36
        case .rightOption:  return 0x3D
        case .rightControl: return 0x3E
        case .rightShift:   return 0x3C
        case .fn:           return 0x3F
        }
    }

    /// Modifier flag we test against `event.modifierFlags` to know
    /// whether the key is currently down. Right-side variants share
    /// the parent flag (`.command`, `.option`, etc.), so we also
    /// inspect the device-independent flag (kCGEventFlagMaskRight…)
    /// inside `keyDown` to disambiguate left vs right.
    var deviceIndependentMask: NSEvent.ModifierFlags {
        switch self {
        case .off:          return []
        case .rightCommand: return .command
        case .rightOption:  return .option
        case .rightControl: return .control
        case .rightShift:   return .shift
        case .fn:           return .function
        }
    }

    var displayName: String {
        switch self {
        case .off:          return "Off"
        case .rightCommand: return "Right ⌘"
        case .rightOption:  return "Right ⌥"
        case .rightControl: return "Right ⌃"
        case .rightShift:   return "Right ⇧"
        case .fn:           return "Fn"
        }
    }
}

/// Watches global `flagsChanged` events for the configured modifier
/// trigger and translates press/release into start/stop calls on the
/// `DictationCoordinator`. Hold-vs-tap routing follows the user's
/// `DictationHotkeyMode`.
@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()

    static let modeDefaultsKey = "dictation.hotkeyMode"
    static let triggerDefaultsKey = "dictation.hotkeyTrigger"

    /// Threshold above which a press counts as "held" instead of
    /// "tapped" in `.hybrid` mode. 500 ms is comfortable: short enough
    /// that intentional holds are crisp, long enough that the user can
    /// tap without triggering hold accidentally.
    private let holdThreshold: TimeInterval = 0.5

    private let defaults: UserDefaults
    private weak var coordinator: DictationCoordinator?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressedAt: Date?
    private var isPressed = false
    /// Snapshot of `coordinator.state == .idle` taken on each keyDown.
    /// `keyUp` reads it to disambiguate "tap that just started a new
    /// session" (leave running) from "tap on an already-running session"
    /// (stop). Without this, hybrid mode can't toggle off with a tap —
    /// the original logic only stopped on a hold release.
    private var wasIdleAtKeyDown = false

    private static let debugLogPath = "/tmp/clawix-hotkey.log"

    private static func debug(_ message: String) {
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: debugLogPath)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // One-shot migration. Earlier builds defaulted the trigger to
        // `.rightCommand`, which fires on every Right ⌘ press and felt
        // like a runaway. Force the trigger to `.off` once so the
        // user has to opt in from Settings; subsequent launches honor
        // whatever they pick.
        let migrationKey = "dictation.hotkey.migratedV2"
        if !defaults.bool(forKey: migrationKey) {
            defaults.set(DictationHotkeyTrigger.off.rawValue, forKey: Self.triggerDefaultsKey)
            defaults.set(true, forKey: migrationKey)
        }
    }

    var mode: DictationHotkeyMode {
        get {
            DictationHotkeyMode(rawValue: defaults.string(forKey: Self.modeDefaultsKey) ?? "")
                ?? .hybrid
        }
        set { defaults.set(newValue.rawValue, forKey: Self.modeDefaultsKey) }
    }

    var trigger: DictationHotkeyTrigger {
        get {
            DictationHotkeyTrigger(rawValue: defaults.string(forKey: Self.triggerDefaultsKey) ?? "")
                ?? .off
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.triggerDefaultsKey)
            // If the user just enabled a trigger and the coordinator is
            // already known, retry registration. The global monitor may
            // have been skipped at bootstrap (Input Monitoring not yet
            // granted) and the user may have just granted it.
            if newValue != .off, let coordinator {
                register(coordinator: coordinator)
            }
        }
    }

    /// Connect to the coordinator that should react to presses and
    /// install the event monitors. Called from `AppDelegate` (via
    /// `bootstrapIfPermitted`) and from the Settings toggle (via
    /// `requestPermissionAndRegister`). Idempotent — safe to call
    /// repeatedly; only installs each monitor once.
    ///
    /// Two monitors are needed because `addGlobalMonitorForEvents`
    /// only delivers when *another* app is active. Without the local
    /// monitor the hotkey would feel broken whenever Clawix itself is
    /// frontmost.
    ///
    /// The global monitor requires Input Monitoring (TCC). Calling
    /// `addGlobalMonitorForEvents(matching: .flagsChanged)` without
    /// the grant freezes event delivery on macOS 26 (Tahoe) — the
    /// "frozen-input bug". So the global monitor is gated behind an
    /// explicit `IOHIDCheckAccess` and silently skipped when not
    /// permitted; the local monitor is still installed so dictation
    /// works while Clawix itself is frontmost.
    func register(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        Self.debug("register() trigger=\(trigger.rawValue) mode=\(mode.rawValue) inputMon=\(DictationPermissions.inputMonitoring())")
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                Task { @MainActor in self.handle(event: event, scope: "local") }
                // Returning the event keeps standard text-field
                // shortcut handling intact.
                return event
            }
            Self.debug("localMonitor installed=\(localMonitor != nil)")
        }
        guard globalMonitor == nil else { return }
        guard DictationPermissions.inputMonitoring() == .granted else {
            Self.debug("globalMonitor skipped: Input Monitoring not granted")
            return
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handle(event: event, scope: "global") }
        }
        Self.debug("globalMonitor installed=\(globalMonitor != nil)")
    }

    /// Bootstrap entry called once from `applicationDidFinishLaunching`.
    /// Always installs the local monitor; the global one only if Input
    /// Monitoring is already granted from a previous session. Users who
    /// haven't granted yet pick a trigger from Settings, which routes
    /// through `requestPermissionAndRegister` to surface the prompt
    /// with the Settings window in focus.
    func bootstrapIfPermitted(coordinator: DictationCoordinator) {
        register(coordinator: coordinator)
    }

    /// Settings entry called when the user picks a non-`.off` trigger.
    /// Drives the TCC flow explicitly so the consent dialog appears
    /// over the Settings sheet (not as an invisible modal during cold
    /// start, the regression that triggered the frozen-input bug). On
    /// `.granted` we register immediately; on `.notDetermined` we ask
    /// IOKit to prompt and the user re-toggles to retry; on `.denied`
    /// we open the Privacy pane so they can enable Clawix manually.
    func requestPermissionAndRegister(coordinator: DictationCoordinator) {
        switch DictationPermissions.inputMonitoring() {
        case .granted:
            register(coordinator: coordinator)
        case .notDetermined:
            DictationPermissions.requestInputMonitoring()
            // The system prompt resolves async. The trigger setter
            // re-runs `register()` on the next user toggle, so once
            // permission lands the global monitor comes online without
            // a relaunch.
        case .denied:
            DictationPermissions.openInputMonitoringSettings()
        }
    }

    // MARK: - Private

    private func handle(event: NSEvent, scope: String) {
        let trigger = self.trigger
        Self.debug(String(format: "handle scope=%@ keyCode=0x%X rawFlags=0x%lX trigger=%@ wantKeyCode=0x%X coordinator=%@",
                          scope, event.keyCode, event.modifierFlags.rawValue, trigger.rawValue, trigger.keyCode,
                          coordinator == nil ? "nil" : "ok"))
        guard let coordinator else { return }
        guard trigger != .off else { return }
        guard event.keyCode == trigger.keyCode else { return }
        let down = isModifierDown(event: event, trigger: trigger)
        Self.debug("match down=\(down) state=\(coordinator.state)")
        if down {
            keyDown(coordinator: coordinator)
        } else {
            keyUp(coordinator: coordinator)
        }
    }

    /// Distinguishing "right command" from "left command" purely from
    /// `NSEvent.modifierFlags` requires reading the device-dependent
    /// bits CoreGraphics exposes via `event.modifierFlags.rawValue`.
    /// Apple defines them in `CGEventTypes.h`:
    /// kCGEventFlagMaskCommand   = 0x100000
    /// kCGEventFlagMaskRightCommand = 0x000010
    /// We check the device-independent flag first (cheap reject) then
    /// the right-side bit if applicable.
    private func isModifierDown(event: NSEvent, trigger: DictationHotkeyTrigger) -> Bool {
        let flags = event.modifierFlags
        let rawFlags = flags.rawValue
        let parent = flags.contains(trigger.deviceIndependentMask)
        guard parent else { return false }
        switch trigger {
        case .off:          return false
        case .rightCommand: return rawFlags & 0x10 != 0
        case .rightOption:  return rawFlags & 0x40 != 0
        case .rightControl: return rawFlags & 0x2000 != 0
        case .rightShift:   return rawFlags & 0x4 != 0
        case .fn:           return true
        }
    }

    private func keyDown(coordinator: DictationCoordinator) {
        guard !isPressed else { return }
        isPressed = true
        switch mode {
        case .pushToTalk, .hybrid:
            pressedAt = Date()
            wasIdleAtKeyDown = coordinator.state == .idle
            // Start recording on the press. In hybrid we decide at
            // key-up whether to also stop (held = push to talk),
            // toggle off (tapped on a running session), or leave it
            // running (tapped on idle = start now, tap again to stop).
            if coordinator.state == .idle {
                coordinator.startFromHotkey()
            }
        case .toggle:
            coordinator.toggleFromHotkey()
        }
    }

    private func keyUp(coordinator: DictationCoordinator) {
        guard isPressed else { return }
        isPressed = false
        switch mode {
        case .pushToTalk:
            coordinator.stop()
        case .hybrid:
            let elapsed: TimeInterval = pressedAt.map { Date().timeIntervalSince($0) } ?? 0
            pressedAt = nil
            let wasIdle = wasIdleAtKeyDown
            wasIdleAtKeyDown = false
            if elapsed >= holdThreshold {
                // Held: push-to-talk style.
                coordinator.stop()
            } else if !wasIdle, coordinator.state == .recording {
                // Tap on a running session: toggle off. The state guard
                // prevents a second tap during the .transcribing phase
                // from cancelling a result the user already committed.
                coordinator.stop()
            }
            // Else: tap on idle → keyDown started a fresh session;
            // leave it running so the user can tap again to stop.
        case .toggle:
            break
        }
    }
}
