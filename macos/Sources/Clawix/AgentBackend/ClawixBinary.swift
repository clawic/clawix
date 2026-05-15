import Foundation

// Locates the absolute path to the backend CLI. We never trust shell
// resolution because the user's nvm shell function can shadow the real
// binary in non-interactive zsh.

struct ClawixBinaryResolution {
    let path: URL
    let version: String?
}

enum ClawixBinary {
    private static let backendExecutableName = "codex"

    static func resolve() -> ClawixBinaryResolution? {
        for candidate in candidatePaths() {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                // Skipping the synchronous version probe here on purpose:
                // `Process.waitUntilExit()` pumps the runloop, which in
                // turn lets SwiftUI commit a view-graph update mid-init
                // and trip an `AG::Graph::value_set` precondition (the
                // app aborts before the first frame). The `.version`
                // field has no consumers in this target.
                return ClawixBinaryResolution(path: candidate, version: nil)
            }
        }
        return nil
    }

    /// User-supplied override (set from SettingsView). Persists in
    /// UserDefaults so the next launch can reuse it.
    static var manualOverride: URL? {
        get {
            UserDefaults.standard.string(forKey: ClawixPersistentSurfaceKeys.binaryPath)
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: ClawixPersistentSurfaceKeys.binaryPath)
        }
    }

    private static func candidatePaths() -> [URL] {
        var out: [URL] = []
        if let manual = manualOverride { out.append(manual) }

        // Standalone codex inside Codex.app: native binary, no node
        // shebang. Preferred because launching the nvm script via
        // Process() fails with "env: node: No such file" when our app
        // is launched outside a shell with PATH.
        out.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/\(backendExecutableName)"))

        // nvm: scan newest versions first. Falls back if Codex.app
        // is not installed; relies on a user PATH that includes node.
        let nvmRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil
        ) {
            let sorted = versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for v in sorted {
                out.append(v.appendingPathComponent("bin/\(backendExecutableName)"))
            }
        }

        out.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(backendExecutableName)"))
        out.append(URL(fileURLWithPath: "/usr/local/bin/\(backendExecutableName)"))
        out.append(URL(fileURLWithPath: "/usr/bin/\(backendExecutableName)"))
        return out
    }

    private static func probeVersion(at url: URL) -> String? {
        let proc = Process()
        proc.executableURL = url
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
