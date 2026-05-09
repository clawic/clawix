import Foundation
import Security

/// Stores the auto-generated admin credential for the bundled
/// `@clawjs/database` daemon in the macOS Keychain.
///
/// The daemon is loopback-only, but we authenticate every request with
/// a JWT issued by `/v1/auth/admin/bootstrap`. The bootstrap endpoint
/// accepts an idempotent `(email, password)` pair: first call creates the
/// admin, subsequent calls return a fresh JWT. We store the password (not
/// the JWT) because JWTs expire every 12h and we'd otherwise have to
/// re-enter the password on every refresh.
enum DatabaseKeychain {

    static let service = "com.clawix.app.clawjs-database-admin"
    static let account = "clawix@local"

    struct Credential: Equatable {
        let email: String
        let password: String
    }

    /// Loads the existing credential, or generates a fresh one and
    /// persists it transparently. Email is fixed; the password is a
    /// 32-byte URL-safe random string.
    static func loadOrCreateCredential() throws -> Credential {
        if ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] == "1" {
            return Credential(email: account, password: "clawix-dummy-database-admin")
        }
        if let existing = try load() {
            return existing
        }
        let password = generatePassword()
        let credential = Credential(email: account, password: password)
        try store(credential)
        return credential
    }

    static func load() throws -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DatabaseKeychain", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemCopyMatching failed: \(status)"
            ])
        }
        return Credential(email: account, password: password)
    }

    static func store(_ credential: Credential) throws {
        guard credential.email == account else {
            throw NSError(domain: "DatabaseKeychain", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported email; only \(account) is allowed"
            ])
        }
        guard let data = credential.password.data(using: .utf8) else {
            throw NSError(domain: "DatabaseKeychain", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Could not encode password"
            ])
        }
        // Try update first; fall back to add.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "DatabaseKeychain", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemAdd/Update failed: \(status)"
            ])
        }
    }

    static func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "DatabaseKeychain", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemDelete failed: \(status)"
            ])
        }
    }

    private static func generatePassword() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
