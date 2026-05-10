import Foundation
import AppKit

/// Bridge / launchd plumbing reused from the menu bar item: open the
/// daemon's stderr, kickstart it, and manage the standalone CLI menubar
/// agent so it doesn't show a duplicate icon next to the GUI's own
/// MenuBarExtra. Wraps `/bin/launchctl` because the GUI talks to the
/// same `clawix.bridge` agent the standalone CLI installs.
enum BridgeAgentControl {

    /// Loopback port the bundled `clawix-bridged` helper binds to.
    /// Mirrors `BRIDGE_PORT` in `cli/lib/platform.js`. Both have to
    /// agree because the iOS pairing payload bakes this in.
    static let bridgePort: UInt16 = 7778

    /// LaunchAgent label of the bundled `clawix-bridged` daemon. Same
    /// label the npm CLI registers, so installing both does not leak
    /// a second daemon. Mirrors `BRIDGE_LABEL` in `cli/lib/platform.js`.
    static let bridgeLabel = "clawix.bridge"

    /// LaunchAgent label of the standalone `clawix-menubar` accessory
    /// that ships with the npm CLI. Mirrors `MENUBAR_LABEL` in
    /// `cli/lib/platform.js`. Keep in sync.
    static let menubarLabel = "clawix.menubar"

    private static let bridgeStderrPath = "/tmp/clawix-bridged.err"

    static func openLogs() {
        let url = URL(fileURLWithPath: bridgeStderrPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/tmp")])
            return
        }
        // The daemon writes to a .err file, which macOS has no default
        // app association for. Force-open it with Console.app, which is
        // the right tool for log viewing anyway.
        if let consoleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: consoleURL, configuration: config)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func restart() {
        runLaunchctl(["kickstart", "-k", "\(userDomain())/\(bridgeLabel)"])
    }

    /// Load the user's bridge LaunchAgent when the registration exists
    /// on disk but launchd no longer has a running job for it.
    @discardableResult
    static func bootstrapBridgeAgentIfInstalled() -> Bool {
        if isBridgeAgentLoaded() {
            return true
        }
        guard FileManager.default.fileExists(atPath: bridgePlistPath) else {
            return false
        }
        let result = runLaunchctl(["bootstrap", userDomain(), bridgePlistPath], capture: true)
        if result.status != 0, !isBridgeAgentLoaded() {
            return false
        }
        return isBridgeAgentLoaded()
    }

    /// True if the standalone CLI menubar LaunchAgent is currently
    /// loaded in the user's launchd domain. Used at GUI startup to
    /// decide whether to bootout it (avoid duplicate menu bar icon).
    static func isMenubarAgentLoaded() -> Bool {
        runLaunchctl(["print", "\(userDomain())/\(menubarLabel)"], capture: true).status == 0
    }

    /// True if the user has the standalone CLI menubar plist installed
    /// at `~/Library/LaunchAgents/clawix.menubar.plist`. Used at GUI
    /// shutdown to decide whether to re-bootstrap it (the user only
    /// gets the file when they install the npm CLI, so absence means
    /// "they don't want this icon, leave them alone").
    static func isMenubarAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: menubarPlistPath)
    }

    /// True if the bundled `clawix-bridged` helper LaunchAgent is loaded.
    /// We only restore the CLI menubar at GUI shutdown if the daemon is
    /// still alive; otherwise an empty CLI menubar would just sit there
    /// saying "Bridge: not running".
    static func isBridgeAgentLoaded() -> Bool {
        runLaunchctl(["print", "\(userDomain())/\(bridgeLabel)"], capture: true).status == 0
    }

    /// Unload the standalone CLI menubar LaunchAgent. Idempotent: if
    /// the agent is not loaded, `bootout` exits non-zero and we ignore
    /// it. The agent's plist stays on disk so we can re-bootstrap it
    /// later when the GUI quits.
    static func bootoutMenubarAgent() {
        runLaunchctl(["bootout", "\(userDomain())/\(menubarLabel)"])
    }

    /// Re-bootstrap the standalone CLI menubar LaunchAgent. Only call
    /// when the plist is installed and the bridge daemon is still up
    /// (otherwise the icon serves no purpose).
    static func bootstrapMenubarAgent() {
        runLaunchctl(["bootstrap", userDomain(), menubarPlistPath])
    }

    private static var menubarPlistPath: String {
        ("~/Library/LaunchAgents/\(menubarLabel).plist" as NSString)
            .expandingTildeInPath
    }

    private static var bridgePlistPath: String {
        ("~/Library/LaunchAgents/\(bridgeLabel).plist" as NSString)
            .expandingTildeInPath
    }

    private static func userDomain() -> String {
        "gui/\(getuid())"
    }

    @discardableResult
    private static func runLaunchctl(
        _ args: [String],
        capture: Bool = false
    ) -> (status: Int32, stdout: String) {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = args
        let outPipe: Pipe? = capture ? Pipe() : nil
        if let outPipe {
            process.standardOutput = outPipe
            process.standardError = Pipe()
        }
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        process.waitUntilExit()
        var stdout = ""
        if let outPipe {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            stdout = String(data: data, encoding: .utf8) ?? ""
        }
        return (process.terminationStatus, stdout)
    }
}
