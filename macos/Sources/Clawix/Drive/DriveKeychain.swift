import Foundation
import Security

/// Stores the auto-created Drive admin password in the macOS Keychain
/// under `com.clawix.app.clawjs-drive-admin`. The Vault and Database
/// services use the same pattern in their own service slots.
enum DriveKeychain {

    private static let service = "com.clawix.app.clawjs-drive-admin"
    private static let account = "clawix@local"

    /// Returns an existing password or generates and stores a new strong
    /// random one. Returns `nil` if Keychain access fails (e.g., locked).
    static func ensureAdminPassword() -> String? {
        if let existing = read() { return existing }
        let password = generatePassword()
        return write(password) ? password : nil
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) {
            return password
        }
        return nil
    }

    @discardableResult
    static func write(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attributes as CFDictionary) // ignore status; tolerate missing
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func adminEmail() -> String { account }

    private static func generatePassword() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        // Fallback: still high entropy via UUIDs (less ideal but never returns weak).
        return "\(UUID().uuidString)-\(UUID().uuidString)"
    }
}
