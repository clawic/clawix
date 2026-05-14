import Foundation
import AppKit

/// Mutes system audio output while a dictation session is active so a
/// running video, music track, or notification beep doesn't bleed into
/// the microphone (especially with built-in mics or AirPods).
///
/// Uses macOS's system-level "output muted" setting via AppleScript:
/// `set volume output muted true/false`. Going through the system mute
/// rather than per-device Core Audio properties means the same call
/// works for built-in speakers, USB DACs and Bluetooth outputs without
/// per-device fallbacks (some Bluetooth devices reject the
/// `kAudioDevicePropertyMute` write but always honour the system mute).
///
/// We track whether *we* did the muting so we never unmute audio that
/// the user had already muted before starting dictation. After stop,
/// the unmute is delayed by `resumeDelaySeconds` to let any pending
/// app resume cleanly without a volume snap.
@MainActor
final class MediaController {

    static let shared = MediaController()

    /// `true` when the toggle is enabled. Default ON: this is the
    /// behaviour 95% of users want and matches the reference dictation
    /// tools we benchmarked against.
    nonisolated static let enabledKey = "dictation.muteAudioWhileRecording"

    /// Seconds to wait before unmuting after the session ends. 0 by
    /// default. Up to 5; values >5 land in Advanced settings UI.
    nonisolated static let resumeDelayKey = "dictation.muteResumeDelaySeconds"

    private let defaults: UserDefaults
    private var resumeWorkItem: DispatchWorkItem?
    /// Tracks a deferred mute scheduled via `muteAfter(_:)` so it can
    /// be cancelled if the session ends before it fires (would
    /// otherwise leave the system permanently muted).
    private var deferredMuteItem: DispatchWorkItem?
    /// Set to `true` only when *we* flipped the system mute on. The
    /// user might already have output muted before starting dictation;
    /// we leave that alone and restore nothing in that case.
    private var didMute: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // First-run defaults. Match the common dictation-tool default
        // so users migrating across tools see consistent behaviour.
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.resumeDelayKey) == nil {
            defaults.set(0, forKey: Self.resumeDelayKey)
        }
    }

    /// Read the current toggle state. Read each call so flipping it in
    /// Settings takes effect on the next dictation without restart.
    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var resumeDelaySeconds: Int {
        let v = defaults.integer(forKey: Self.resumeDelayKey)
        return max(0, min(5, v))
    }

    // MARK: - Public lifecycle

    /// Mute system output if the toggle is on and the user hadn't
    /// already muted it. Idempotent across repeated calls.
    func muteIfNeeded() {
        guard isEnabled else { return }
        // Drop any deferred mute scheduled for this session — we're
        // about to mute synchronously below.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        // If a deferred unmute from a previous session is queued,
        // cancel it AND inherit ownership: the system is currently
        // muted because *we* muted it before, even if the AppleScript
        // unmute didn't fire yet. Without this, a fast cancel→start
        // sequence would orphan the mute (didMute=false), so the next
        // stop wouldn't restore audio.
        let inheritedPendingMute = (resumeWorkItem != nil)
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        if inheritedPendingMute {
            didMute = true
            return
        }
        // Don't re-mute: user already had output muted, keep their
        // state authoritative.
        if currentMutedState() == true {
            didMute = false
            return
        }
        if setMuted(true) {
            didMute = true
        }
    }

    /// Synchronously unmute now, ignoring `resumeDelaySeconds`. Used
    /// just before playing a cue (cancel/stop/done) so the cue is
    /// audible. No-op if we didn't mute.
    func unmuteImmediately() {
        // Drop any pending deferred mute from this session so it
        // doesn't fire after the unmute and leave the system muted.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        guard didMute else { return }
        didMute = false
        _ = setMuted(false)
    }

    /// Schedule `muteIfNeeded()` after `delay` seconds. Used at the
    /// start of a session so the start cue plays into an unmuted
    /// system; the mute kicks in once the cue has finished.
    func muteAfter(_ delay: TimeInterval) {
        guard isEnabled else { return }
        // Cancel any pending unmute from a prior session so we don't
        // re-enter a clean state mid-session.
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        // Replace any in-flight deferred mute so we don't double-fire.
        deferredMuteItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.deferredMuteItem = nil
            self?.muteIfNeeded()
        }
        deferredMuteItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Unmute after `resumeDelaySeconds`. No-op if we didn't mute.
    func unmuteAfterDelay() {
        // Drop any pending deferred mute scheduled by `muteAfter(_:)`
        // so it doesn't fire after we return to idle and silently
        // re-mute the system.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        guard didMute else {
            // Make sure no stale work item is left behind (e.g. user
            // toggled the setting off mid-session).
            resumeWorkItem?.cancel()
            resumeWorkItem = nil
            return
        }
        didMute = false
        let delay = TimeInterval(resumeDelaySeconds)
        let work = DispatchWorkItem { [weak self] in
            _ = self?.setMuted(false)
        }
        resumeWorkItem?.cancel()
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - AppleScript bridge

    /// Returns `true` if currently muted, `false` if not, `nil` if the
    /// query failed (sandbox blocked the AppleScript, etc.).
    private func currentMutedState() -> Bool? {
        let source = "output muted of (get volume settings)"
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if errorDict != nil { return nil }
        // AppleScript returns booleans as typeTrue/typeFalse or
        // typeBoolean; booleanValue normalizes all of them.
        return result.booleanValue
    }

    /// Returns `true` if the system mute write succeeded.
    @discardableResult
    private func setMuted(_ muted: Bool) -> Bool {
        let value = muted ? "true" : "false"
        let source = "set volume output muted \(value)"
        guard let script = NSAppleScript(source: source) else { return false }
        var errorDict: NSDictionary?
        _ = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            NSLog("[Clawix.MediaController] mute=\(muted) failed: \(err)")
            return false
        }
        return true
    }
}
