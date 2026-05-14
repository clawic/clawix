import Foundation

enum ClawixPersistentSurfacePathComponents {
    static func temporaryVaultDatabaseName(id: UUID) -> String {
        "clawix-vault-\(id.uuidString).sqlite"
    }
}
