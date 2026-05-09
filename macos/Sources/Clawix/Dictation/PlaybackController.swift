import Foundation
import AppKit

/// Pauses the currently playing media app while a dictation session is
/// active and resumes only that app afterwards. Complementary to
/// `MediaController` (which mutes system output): pausing keeps the
/// track in place rather than letting it advance silently.
///
/// AppleScript is used for the player IPC because it's the only path
/// that works for both Music.app (no MediaRemote scripting interface)
/// and Spotify.app (well-known scriptable). Apps that aren't running
/// are skipped — we never auto-launch a media app the user closed.
///
/// Only one app is paused per session (the first one we find playing
/// in the priority order Music → Spotify → Podcasts) so resume can't
/// accidentally start an app that wasn't playing in the first place.
@MainActor
final class PlaybackController {

    static let shared = PlaybackController()

    static let enabledKey = "dictation.pauseMediaWhileRecording"
    static let resumeDelayKey = "dictation.pauseResumeDelaySeconds"

    private let defaults: UserDefaults
    private var resumeWorkItem: DispatchWorkItem?
    /// Identifier of the app we paused (`Music`, `Spotify`,
    /// `Podcasts`). Nil when no pause happened.
    private var pausedApp: String?

    private static let candidateApps: [String] = ["Music", "Spotify", "Podcasts"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default OFF: this is more intrusive than muting. The mute
        // toggle covers the noise problem; pause is for users who'd
        // rather not lose their place in the track.
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.resumeDelayKey) == nil {
            defaults.set(0, forKey: Self.resumeDelayKey)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var resumeDelaySeconds: Int {
        let v = defaults.integer(forKey: Self.resumeDelayKey)
        return max(0, min(5, v))
    }

    // MARK: - Lifecycle

    func pauseIfNeeded() {
        guard isEnabled else { return }
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        for app in Self.candidateApps {
            guard isAppRunning(app) else { continue }
            guard isPlaying(app: app) else { continue }
            if pause(app: app) {
                pausedApp = app
                break
            }
        }
    }

    func resumeAfterDelay() {
        guard let app = pausedApp else {
            resumeWorkItem?.cancel()
            resumeWorkItem = nil
            return
        }
        pausedApp = nil
        let delay = TimeInterval(resumeDelaySeconds)
        let work = DispatchWorkItem { [weak self] in
            _ = self?.play(app: app)
        }
        resumeWorkItem?.cancel()
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - AppleScript helpers

    private func isAppRunning(_ name: String) -> Bool {
        // `is running` doesn't auto-launch the app like a `tell`-block
        // would, so it's safe to evaluate even on apps the user has
        // closed.
        let source = "tell application \"System Events\" to (name of processes) contains \"\(name)\""
        return runBoolScript(source) ?? false
    }

    /// Returns `true` only if the app reports a "playing" state. Music,
    /// Spotify and Podcasts all expose a `player state` property; Music
    /// uses `playing` (lowercase enum) while Spotify uses `playing` as
    /// well, so the same comparison works for both.
    private func isPlaying(app: String) -> Bool {
        let source = """
        tell application \"\(app)\"
            try
                if player state is playing then
                    return true
                else
                    return false
                end if
            on error
                return false
            end try
        end tell
        """
        return runBoolScript(source) ?? false
    }

    @discardableResult
    private func pause(app: String) -> Bool {
        runVoidScript("tell application \"\(app)\" to pause")
    }

    @discardableResult
    private func play(app: String) -> Bool {
        // `play` resumes from the last position (won't start a new
        // track) on Music and Spotify both.
        runVoidScript("tell application \"\(app)\" to play")
    }

    private func runBoolScript(_ source: String) -> Bool? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if errorDict != nil { return nil }
        return result.booleanValue
    }

    @discardableResult
    private func runVoidScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorDict: NSDictionary?
        _ = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            NSLog("[Clawix.PlaybackController] script failed: \(err)")
            return false
        }
        return true
    }
}
