import Foundation

enum SecretsPaths {
    static let deviceIdKey = "clawix.secrets.deviceId"

    /// Secrets directory. Honors `CLAWIX_SECRETS_DIR` so dummy mode (and tests)
    /// can sandbox Secrets away from the user's real Application Support
    /// folder. Without it the real production location is used.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAWIX_SECRETS_DIR"],
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.secrets, isDirectory: true)
    }

    static var databaseFile: URL {
        directory.appendingPathComponent(ClawixPersistentSurfacePaths.components.secretsDatabase)
    }

    static var proxySocketFile: URL {
        directory.appendingPathComponent("proxy.sock")
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func vaultExists() -> Bool {
        FileManager.default.fileExists(atPath: databaseFile.path)
    }

    static func deviceId() -> String {
        let key = deviceIdKey
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
