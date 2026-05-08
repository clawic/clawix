import Foundation

enum VaultPaths {
    static var directory: URL {
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
