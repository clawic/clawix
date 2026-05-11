import Foundation

/// Resolves the per-session admin token for the clawjs-iot daemon.
///
/// Phase 1 ships read-only tools that the daemon serves without
/// authentication, so this resolver returns nil and `IoTClient`
/// short-circuits the `Authorization` header. Phase 2 introduces
/// mutating tools (control, scene activation, automation run) gated by
/// `IoTRiskLevel`; when that lands, the daemon will start writing a
/// 0600 admin-token file under its data dir and this resolver returns
/// its contents so every Clawix client (Mac, iOS, CLI) authenticates
/// with the same token, even when they share a daemon already owned by
/// the background bridge helper.
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
