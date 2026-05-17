import Foundation

enum BridgeAuthValidation {
    static func hasValidClientIdentity(
        clientId: String,
        installationId: String,
        deviceId: String
    ) -> Bool {
        [clientId, installationId, deviceId].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
