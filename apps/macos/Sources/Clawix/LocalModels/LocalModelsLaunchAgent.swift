import Foundation
import ServiceManagement

/// LaunchAgent registration for the local LLM runtime. When enabled,
/// `launchd` keeps the daemon alive across logout, app crashes, and
/// Cmd+Q of the GUI. The plist embedded in the .app
/// (`Contents/Library/LaunchAgents/<bundle>.local-models.plist`) is
/// written by `dev.sh` / the release scripts; this class only flips
/// registration on or off via `SMAppService.agent`.
///
/// The plist's `ProgramArguments` is a `/bin/sh -c` wrapper that
/// resolves `$HOME` at launch time, so the binary downloaded into
/// Application Support is found whatever the user's username is. If the
/// binary is missing (runtime not installed yet), the wrapper exits 0
/// and `launchd` does not relaunch — `KeepAlive { SuccessfulExit=false }`.
@MainActor
final class LocalModelsLaunchAgent: ObservableObject {

    static let shared = LocalModelsLaunchAgent()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    private let plistName: String
    private let agent: SMAppService

    private init() {
        let parentBundleId = Bundle.main.bundleIdentifier ?? "clawix.desktop"
        self.plistName = "\(parentBundleId).local-models.plist"
        self.agent = SMAppService.agent(plistName: plistName)
        refresh()
    }

    var isEnabled: Bool { status == .enabled }

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

    /// Plain-language status for the UI.
    var statusLabel: String {
        switch status {
        case .notRegistered:
            return "Not running at login"
        case .enabled:
            return "Starts automatically at login"
        case .requiresApproval:
            return "Approve in System Settings → General → Login Items"
        case .notFound:
            return "LaunchAgent missing from this build"
        @unknown default:
            return "Unknown status"
        }
    }
}
