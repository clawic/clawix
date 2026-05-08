import Foundation

enum VaultPaths {
    /// Vault directory. Honors `CLAWIX_VAULT_DIR` so dummy mode (and tests)
    /// can sandbox the vault away from the user's real Application Support
    /// folder. Without it the real production location is used.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAWIX_VAULT_DIR"],
           !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base.appendingPathComponent("Clawix/secrets", isDirectory: true)
    }

    static var databaseFile: URL {
        directory.appendingPathComponent("vault.sqlite")
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
        let key = "clawix.secrets.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
