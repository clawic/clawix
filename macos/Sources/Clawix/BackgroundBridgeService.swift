import Foundation
import ServiceManagement

/// Wrapper around `SMAppService.agent` that lets the user opt into the
/// LaunchAgent daemon (`clawix-bridged`). When registered, launchd
/// keeps the daemon alive across Cmd+Q of the GUI, app crashes, and
/// logout/login. Bundle layout (helper at
/// `Contents/Helpers/clawix-bridged`, plist at
/// `Contents/Library/LaunchAgents/clawix.bridge.plist`) is set up by
/// `dev.sh` and the release script; this service only flips the
/// registration on or off.
///
/// The LaunchAgent label is the literal `clawix.bridge`, public and
/// shared with the standalone `clawix` CLI: both register the same
/// agent slot so installing the GUI on a machine that already runs the
/// CLI (or vice versa) cleanly hands ownership over without leaking a
/// second daemon on the same loopback port.
@MainActor
final class BackgroundBridgeService: ObservableObject {

    static let shared = BackgroundBridgeService()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var daemonReachable = false
    @Published private(set) var lastError: String?

    private let plistName = "clawix.bridge.plist"
    private let agent: SMAppService
    private var recoveryTimer: Timer?

    private init() {
        self.agent = SMAppService.agent(plistName: plistName)
        refresh()
        recoverRegisteredDaemonIfNeeded()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    /// True when *any* `clawix-bridged` daemon is reachable on this Mac,
    /// regardless of who registered it. Reads
    /// `~/.clawix/state/bridge-status.json` (the daemon's heartbeat file)
    /// and confirms the recorded PID is still alive.
    ///
    /// Why this exists: SMAppService.status is bundle-relative. A
    /// LaunchAgent registered by the npm CLI (its plist sitting in
    /// `~/Library/LaunchAgents/clawix.bridge.plist` and pointing at
    /// `~/.clawix/bin/clawix-bridged`) does NOT show up as `.enabled`
    /// for the GUI app's SMAppService.agent — that API only sees agents
    /// the calling .app itself registered through `register()`. So a
    /// dev build launched via dev.sh sees `isEnabled = false` even
    /// though a daemon is alive on loopback owning Codex.
    /// `isActive` (below) combines both signals so the GUI routes
    /// through the daemon either way.
    var isDaemonReachable: Bool {
        Self.computeDaemonReachable()
    }

    private static func computeDaemonReachable() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clawix/state/bridge-status.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = obj["pid"] as? Int,
              let state = obj["state"] as? String,
              state == "ready" || state == "syncing"
        else { return false }
        // Heartbeat freshness: the daemon writes every 2s but the
        // write happens on a utility queue and the file's mtime can
        // lag by a few seconds during GUI startup contention. 60s is
        // generous enough to survive that race while still catching
        // a daemon that has actually wedged or been kill -9'd. Real
        // liveness is the PID check below; freshness is just a cheap
        // sanity gate against a leftover heartbeat from a long-dead
        // run whose PID happens to be reused.
        if let lastHeartbeatAt = obj["lastHeartbeatAt"] as? String,
           let date = Self.isoParser.date(from: lastHeartbeatAt) {
            if Date().timeIntervalSince(date) > 60 { return false }
        }
        // PID liveness: signal 0 returns 0 if the process exists and
        // we have permission to signal it; ESRCH means it's gone.
        return kill(pid_t(pid), 0) == 0
    }

    /// True when the GUI should treat the daemon as the canonical
    /// owner of Codex. A user-enabled LaunchAgent still owns that role
    /// while launchd is starting it, so `recoverRegisteredDaemonIfNeeded`
    /// makes a best effort to load stale registrations before `AppState`
    /// decides whether to spawn an in-process backend.
    var isActive: Bool { isEnabled || daemonReachable || isDaemonReachable }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Re-read status from launchd. Useful after `register`/`unregister`
    /// to surface the new state without polling.
    func refresh() {
        status = agent.status
        daemonReachable = isDaemonReachable
        updateRecoveryTimer()
    }

    func enable() {
        do {
            try agent.register()
            lastError = nil
        } catch {
            lastError = "register failed: \(error.localizedDescription)"
        }
        refresh()
        recoverRegisteredDaemonIfNeeded()
    }

    func disable() {
        do {
            try agent.unregister()
            lastError = nil
        } catch {
            lastError = "unregister failed: \(error.localizedDescription)"
        }
        refresh()
    }

    func toggle(_ on: Bool) {
        if on { enable() } else { disable() }
    }

    /// `SMAppService.status` can survive an app reinstall or manual
    /// launchd bootout while the actual user-domain job is gone. When
    /// that happens, reconnect the installed LaunchAgent instead of
    /// letting the GUI route to a daemon that will never start.
    func recoverRegisteredDaemonIfNeeded() {
        refresh()
        guard isEnabled, !isDaemonReachable else { return }
        if BridgeAgentControl.bootstrapBridgeAgentIfInstalled() {
            lastError = nil
        } else {
            lastError = "background bridge registered but not loaded"
        }
        refresh()
    }

    private func updateRecoveryTimer() {
        guard isEnabled else {
            recoveryTimer?.invalidate()
            recoveryTimer = nil
            return
        }
        guard recoveryTimer == nil else { return }
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recoveryTick()
            }
        }
    }

    private func recoveryTick() {
        refresh()
        guard isEnabled else { return }
        if daemonReachable {
            lastError = nil
        } else {
            recoverRegisteredDaemonIfNeeded()
        }
    }

    /// Snapshot taken before a Sparkle install swap. We unregister the
    /// LaunchAgent (so launchd lets go of file handles into the .app
    /// bundle Sparkle is about to move) and remember whether to
    /// re-enable it on relaunch. Sparkle replaces the bundle and
    /// relaunches the app; on next `init` `BackgroundBridgeService`
    /// re-reads `wasEnabledKey` and calls `enable()` again to restore
    /// the previous state.
    private static let wasEnabledKey = "ClawixBackgroundBridge.wasEnabledBeforeUpdate.v1"

    /// Call from the Sparkle delegate's "ready to install" hook so the
    /// daemon doesn't hold the .app open while Sparkle moves it.
    func prepareForUpdateInstall() {
        let wasEnabled = isEnabled
        UserDefaults.standard.set(wasEnabled, forKey: Self.wasEnabledKey)
        if wasEnabled {
            disable()
        }
    }

    /// Re-enable the daemon if it was on before the Sparkle update.
    /// Called once at startup so the user does not have to flip the
    /// toggle again.
    func restoreAfterUpdateIfNeeded() {
        guard UserDefaults.standard.object(forKey: Self.wasEnabledKey) != nil else { return }
        let wasEnabled = UserDefaults.standard.bool(forKey: Self.wasEnabledKey)
        UserDefaults.standard.removeObject(forKey: Self.wasEnabledKey)
        if wasEnabled, !isEnabled {
            enable()
        }
    }

    /// Plain-language status for the UI. Hides launchd's many internal
    /// states behind the three the user actually cares about.
    var statusLabel: String {
        switch status {
        case .notRegistered: return "Not running"
        case .enabled:
            return daemonReachable || isDaemonReachable ? "Running in background" : "Starting background bridge"
        case .requiresApproval:
            return "Approve in System Settings → General → Login Items"
        case .notFound:
            return "Helper missing from this build"
        @unknown default:
            return "Unknown status"
        }
    }
}
