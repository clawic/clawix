import Foundation

/// Resolves the per-session admin token used to authenticate against the
/// bundled Drive daemon over loopback. Mirrors `DatabaseAdminToken`.
@MainActor
enum DriveAdminToken {
    static func currentAdminToken() throws -> String {
        if let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .drive) {
            return token
        }
        return try ClawJSServiceManager.adminTokenFromDataDir(for: .drive)
    }
}
