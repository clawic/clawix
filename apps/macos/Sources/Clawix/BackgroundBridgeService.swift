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
    @Published private(set) var lastError: String?

    private let plistName = "clawix.bridge.plist"
    private let agent: SMAppService

    private init() {
        self.agent = SMAppService.agent(plistName: plistName)
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    /// Re-read status from launchd. Useful after `register`/`unregister`
    /// to surface the new state without polling.
    func refresh() {
        status = agent.status
    }

    func enable() {
        do {
            try agent.register()
            lastError = nil
        } catch {
            lastError = "register failed: \(error.localizedDescription)"
        }
        refresh()
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
        case .enabled:       return "Running in background"
        case .requiresApproval:
            return "Approve in System Settings → General → Login Items"
        case .notFound:
            return "Helper missing from this build"
        @unknown default:
            return "Unknown status"
        }
    }
}
