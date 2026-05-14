import Foundation
import LocalAuthentication

enum SecretsReauthentication {
    static func canUseBiometricUnlock() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static func requireBiometricUnlock(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? NSError(
                domain: "SecretsReauthentication",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This Mac cannot unlock Secrets with biometrics."]
            )
        }

        try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

    static func require(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(
                domain: "SecretsReauthentication",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This Mac cannot reauthenticate sensitive secret access."]
            )
        }

        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
