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

/// Watches global `flagsChanged` events for any of the configured
/// modifier triggers and translates press/release into start/stop
/// calls on the `DictationCoordinator`. Hold-vs-tap routing follows
/// each binding's own `DictationHotkeyMode`.
///
/// Two simultaneous bindings are supported (Shortcut 1 + Shortcut 2)
/// so a power user can have, say, Right ⌘ for hybrid quick toggles
/// AND Fn for deliberate push-to-talk. Each binding owns its own
/// hold/tap state machine so they can be active at the same time
/// without interference.
@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()

    /// Per-binding mutable state, owned by the manager. Two of these
    /// live at once — one for Shortcut 1, one for Shortcut 2. Carried
    /// in a class so `handle()` can mutate via reference without
    /// having to look up by index every event.
    private final class Binding {
        let slot: Int
        var pressedAt: Date?
        var isPressed: Bool = false
        var wasIdleAtKeyDown: Bool = false
        let triggerKey: String
        let modeKey: String

        init(slot: Int, triggerKey: String, modeKey: String) {
            self.slot = slot
            self.triggerKey = triggerKey
            self.modeKey = modeKey
        }
    }

    nonisolated static let modeDefaultsKey = "dictation.hotkeyMode"
    nonisolated static let triggerDefaultsKey = "dictation.hotkeyTrigger"
    /// Second-binding keys. `.off` by default so existing users see
    /// no behavior change unless they opt in.
    nonisolated static let mode2DefaultsKey = "dictation.hotkey2Mode"
    nonisolated static let trigger2DefaultsKey = "dictation.hotkey2Trigger"

    /// Threshold above which a press counts as "held" instead of
    /// "tapped" in `.hybrid` mode. 500 ms is comfortable: short enough
    /// that intentional holds are crisp, long enough that the user can
    /// tap without triggering hold accidentally.
    private let holdThreshold: TimeInterval = 0.5

    private let defaults: UserDefaults
    private weak var coordinator: DictationCoordinator?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let bindings: [Binding]

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
        self.bindings = [
            Binding(slot: 1, triggerKey: Self.triggerDefaultsKey, modeKey: Self.modeDefaultsKey),
            Binding(slot: 2, triggerKey: Self.trigger2DefaultsKey, modeKey: Self.mode2DefaultsKey)
        ]
        if defaults.object(forKey: Self.triggerDefaultsKey) == nil {
            defaults.set(DictationHotkeyTrigger.off.rawValue, forKey: Self.triggerDefaultsKey)
        }
        // Default the second slot to off explicitly so the picker has
        // a value to render on first launch.
        if defaults.object(forKey: Self.trigger2DefaultsKey) == nil {
            defaults.set(DictationHotkeyTrigger.off.rawValue, forKey: Self.trigger2DefaultsKey)
        }
    }

    // MARK: - Public mode/trigger accessors (slot 1)

    var mode: DictationHotkeyMode {
        get { mode(forSlot: 1) }
        set { setMode(newValue, forSlot: 1) }
    }

    var trigger: DictationHotkeyTrigger {
        get { trigger(forSlot: 1) }
        set { setTrigger(newValue, forSlot: 1) }
    }

    // MARK: - Public mode/trigger accessors (slot 2)

    var mode2: DictationHotkeyMode {
        get { mode(forSlot: 2) }
        set { setMode(newValue, forSlot: 2) }
    }

    var trigger2: DictationHotkeyTrigger {
        get { trigger(forSlot: 2) }
        set { setTrigger(newValue, forSlot: 2) }
    }

    // MARK: - Generic per-slot helpers

    private func binding(forSlot slot: Int) -> Binding {
        bindings[slot - 1]
    }

    private func mode(forSlot slot: Int) -> DictationHotkeyMode {
        let key = binding(forSlot: slot).modeKey
        return DictationHotkeyMode(rawValue: defaults.string(forKey: key) ?? "") ?? .hybrid
    }

    private func setMode(_ value: DictationHotkeyMode, forSlot slot: Int) {
        defaults.set(value.rawValue, forKey: binding(forSlot: slot).modeKey)
    }

    private func trigger(forSlot slot: Int) -> DictationHotkeyTrigger {
        let key = binding(forSlot: slot).triggerKey
        return DictationHotkeyTrigger(rawValue: defaults.string(forKey: key) ?? "") ?? .off
    }

    private func setTrigger(_ value: DictationHotkeyTrigger, forSlot slot: Int) {
        defaults.set(value.rawValue, forKey: binding(forSlot: slot).triggerKey)
        // If the user just enabled a trigger and the coordinator is
        // already known, retry registration. The global monitor may
        // have been skipped at bootstrap (Input Monitoring not yet
        // granted) and the user may have just granted it.
        if value != .off, let coordinator {
            register(coordinator: coordinator)
        }
    }

    /// Connect to the coordinator that should react to presses and
    /// install the event monitors. Called from `AppDelegate` (via
    /// `bootstrap`) and from the Settings toggle (via
    /// `requestPermissionAndRegister`). Idempotent — safe to call
    /// repeatedly; only installs each monitor once.
    ///
    /// Two monitors are needed because `addGlobalMonitorForEvents`
    /// only delivers when *another* app is active. Without the local
    /// monitor the hotkey would feel broken whenever Clawix itself is
    /// frontmost.
    ///
    /// The global monitor requires Input Monitoring (TCC) to actually
    /// receive events; without the grant the callback is silently a
    /// no-op until the user enables the app from the Privacy pane.
    /// We install it only after a trigger is configured so macOS adds
    /// Clawix to the Input Monitoring privacy list in a user-initiated
    /// flow. The explicit
    /// `IOHIDRequestAccess` in `requestPermissionAndRegister` surfaces
    /// the consent dialog as soon as the user picks a trigger so they
    /// don't have to find Settings on their own.
    ///
    /// To avoid the macOS 26 (Tahoe) "frozen-input bug" — where
    /// installing the global monitor with no user-facing reason at
    /// cold start could freeze event delivery — both monitors are
    /// only installed once at least one slot has a non-`.off` trigger.
    /// On a fresh install the default is `.off`, so the monitors stay
    /// uninstalled until the user opts in from Settings.
    func register(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        // Cancel binding lives in `KeyboardShortcuts.Name.dictationCancel`
        // wired by `DictationShortcutsInstaller.installAll()`. No
        // separate monitor needed here.
        let anyTriggerActive = trigger != .off || trigger2 != .off
        Self.debug("register() trigger1=\(trigger.rawValue) trigger2=\(trigger2.rawValue) inputMon=\(DictationPermissions.inputMonitoring()) anyActive=\(anyTriggerActive)")
        guard anyTriggerActive else {
            Self.debug("register() skipped: no trigger configured")
            return
        }
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
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return }
                Task { @MainActor in self.handle(event: event, scope: "global") }
            }
            Self.debug("globalMonitor installed=\(globalMonitor != nil)")
        }
    }

    /// Bootstrap entry called once from `applicationDidFinishLaunching`.
    /// Installs both monitors if the user already had a trigger
    /// configured from a previous session. Fresh installs default to
    /// `.off` and the monitors stay uninstalled until the user picks
    /// a trigger from Settings, which routes through
    /// `requestPermissionAndRegister` and surfaces the Input Monitoring
    /// prompt with the Settings window in focus.
    func bootstrap(coordinator: DictationCoordinator) {
        register(coordinator: coordinator)
        // Push the model into the GPU cache early so the first real
        // dictation of the session doesn't pay the cold-load tax.
        // Honors `dictation.prewarmOnLaunch`; skipped silently when
        // the model isn't downloaded.
        coordinator.prewarmIfEnabled()
        // Install the user-customizable quick-action bindings (#9):
        // Toggle / Cancel / Paste Last / Retry Last / Toggle
        // Enhancement. The framework persists each binding under its
        // Name, so the user's recorded combos survive relaunches
        // without us touching UserDefaults.
        DictationShortcutsInstaller.installAll()
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
        guard let coordinator else { return }
        // Iterate every binding, dispatch to whichever matches the
        // event's keyCode. Two simultaneous bindings could in theory
        // share a keyCode (would be a UX bug — Settings should warn
        // and prevent it) but the loop is robust to it: only the
        // first matching binding fires.
        for binding in bindings {
            let trig = trigger(forSlot: binding.slot)
            guard trig != .off else { continue }
            guard event.keyCode == trig.keyCode else { continue }
            let down = isModifierDown(event: event, trigger: trig)
            Self.debug(String(format: "match slot=%d down=%@ scope=%@", binding.slot, String(down), scope))
            if down {
                keyDown(coordinator: coordinator, binding: binding)
            } else {
                keyUp(coordinator: coordinator, binding: binding)
            }
            return
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

    private func keyDown(coordinator: DictationCoordinator, binding: Binding) {
        guard !binding.isPressed else { return }
        binding.isPressed = true
        let mode = mode(forSlot: binding.slot)
        switch mode {
        case .pushToTalk, .hybrid:
            binding.pressedAt = Date()
            binding.wasIdleAtKeyDown = coordinator.state == .idle
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

    private func keyUp(coordinator: DictationCoordinator, binding: Binding) {
        guard binding.isPressed else {
            Self.debug("keyUp ignored: !isPressed slot=\(binding.slot)")
            return
        }
        binding.isPressed = false
        let mode = mode(forSlot: binding.slot)
        switch mode {
        case .pushToTalk:
            Self.debug("keyUp pushToTalk → stop slot=\(binding.slot) coordState=\(coordinator.state)")
            coordinator.stop()
        case .hybrid:
            let elapsed: TimeInterval = binding.pressedAt.map { Date().timeIntervalSince($0) } ?? 0
            binding.pressedAt = nil
            let wasIdle = binding.wasIdleAtKeyDown
            binding.wasIdleAtKeyDown = false
            Self.debug("keyUp hybrid slot=\(binding.slot) elapsed=\(String(format: "%.3f", elapsed)) wasIdle=\(wasIdle) coordState=\(coordinator.state)")
            if elapsed >= holdThreshold {
                Self.debug("→ branch=held → stop()")
                coordinator.stop()
            } else if !wasIdle, coordinator.state == .recording {
                Self.debug("→ branch=tap-on-running → stop()")
                coordinator.stop()
            } else {
                Self.debug("→ branch=tap-on-idle → leave running")
            }
        case .toggle:
            break
        }
    }
}
