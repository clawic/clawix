// SECRETS-SECRET-KEY-KEYCHAIN-OK
import Foundation
import Security

enum SecretsLocalSecretKey {
    private static let service = "com.clawix.secrets.secret-key.v1"
    private static let account = "default"

    static func load() throws -> String? {
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
        guard status == errSecSuccess, let data = item as? Data, let secretKey = String(data: data, encoding: .utf8) else {
            throw error(status)
        }
        return secretKey
    }

    static func store(_ secretKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attributes = query
        attributes[kSecValueData as String] = Data(secretKey.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecValueData as String: Data(secretKey.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw error(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw error(status) }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func error(_ status: OSStatus) -> NSError {
        NSError(domain: "SecretsLocalSecretKey", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Could not access local Secrets Secret Key (OSStatus \(status)).",
        ])
    }
}
