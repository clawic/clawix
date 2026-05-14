// SECRETS-PLATFORM-KEYCHAIN-OK
import Foundation
import Security

enum SecretsPlatformKey {
    private static let service = "com.clawix.secrets.platform-kek.v1"
    private static let account = "default"

    static func loadOrCreate() throws -> Data {
        if let existing = try load() {
            return existing
        }
        let key = try randomKey()
        try save(key)
        return key
    }

    private static func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status, "read") }
        guard let data = result as? Data, data.count == 32 else {
            throw NSError(domain: "SecretsPlatformKey", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Stored Secrets platform key is invalid."
            ])
        }
        return data
    }

    private static func save(_ key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = key
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw error(status, "save") }
    }

    private static func randomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw error(status, "generate") }
        return Data(bytes)
    }

    private static func error(_ status: OSStatus, _ operation: String) -> NSError {
        NSError(domain: "SecretsPlatformKey", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Could not \(operation) Secrets platform key (OSStatus \(status))."
        ])
    }
}
