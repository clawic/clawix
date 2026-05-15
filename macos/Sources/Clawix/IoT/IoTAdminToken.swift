import Foundation

/// Resolves the per-session admin token for the clawjs-iot daemon.
///
/// The current daemon serves its tool surface on loopback without a per-session
/// token, so this resolver returns nil and `IoTClient` omits the
/// `Authorization` header. Token-backed deployments can fill this resolver
/// from the daemon data dir without changing the client call sites.
///
/// Mirrors `DatabaseAdminToken` so the two surfaces stay easy to compare
/// when we extract a generic admin-token resolver later.
@MainActor
enum IoTAdminToken {
    static func currentAdminToken() -> String? {
        if let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .iot) {
            return token
        }
        return try? ClawJSServiceManager.adminTokenFromDataDir(for: .iot)
    }
}
