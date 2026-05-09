import Foundation

/// Locates the ClawJS runtime that `bundle_clawjs.sh` plants under
/// `Clawix.app/Contents/Helpers/clawjs/`. The version is pinned in
/// `macos/CLAWJS_VERSION` and surfaced through the generated
/// `Info.plist` as `ClawJSVersion`. Phase 2's `ClawJSServiceManager`
/// will spawn `nodeBinaryURL cliScriptURL open <service> ...`.
enum ClawJSRuntime {
    /// The `@clawjs/cli` release this build is integrated against, read
    /// from the Info.plist key `ClawJSVersion`. Never hardcode the
    /// version inline; bumps go through `macos/CLAWJS_VERSION`.
    static let expectedVersion: String = {
        Bundle.main.infoDictionary?["ClawJSVersion"] as? String ?? "0.0.0"
    }()

    /// `Clawix.app/Contents/Helpers/clawjs/` — root of the bundled tree.
    static var bundleRootURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/clawjs", isDirectory: true)
    }

    /// The Node binary `bundle_clawjs.sh` placed at the bundle root.
    static var nodeBinaryURL: URL {
        bundleRootURL.appendingPathComponent("node", isDirectory: false)
    }

    /// Entrypoint script the bundled CLI exposes. Invoke it with the
    /// bundled `node`, never with the user's system Node, so behavior
    /// stays pinned to the version this Clawix build was tested with.
    static var cliScriptURL: URL {
        bundleRootURL
            .appendingPathComponent("node_modules/@clawjs/cli/bin/clawjs.mjs", isDirectory: false)
    }

    /// True only when both the Node binary and the CLI entrypoint are
    /// present. The bundle is mandatory in release builds (the release
    /// pipeline rejects mismatches); in dev a missing bundle just means
    /// `bundle_clawjs.sh` has not run yet, and the caller should log a
    /// clear error instead of attempting to spawn a nonexistent helper.
    static var isAvailable: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: nodeBinaryURL.path)
            && fm.fileExists(atPath: cliScriptURL.path)
    }
}
