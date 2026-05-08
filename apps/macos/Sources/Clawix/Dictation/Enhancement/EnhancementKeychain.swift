import Foundation
import Security

/// Tiny Security-framework wrapper for stashing per-provider API keys.
/// Used instead of UserDefaults so the keys aren't readable by other
/// apps with file-level access to the prefs plist.
///
/// The service string is namespaced (`com.clawix.enhancement.<provider>`)
/// so the entries don't collide with anything else the app may store
/// in the future. Account is the same across reads and writes; we
/// don't try to support multiple identities per provider.
enum EnhancementKeychain {

    static let serviceBase = "com.clawix.enhancement"
    static let account = "default"

    static func service(for provider: EnhancementProviderID) -> String {
        "\(serviceBase).\(provider.rawValue)"
    }

    static func setAPIKey(_ key: String, for provider: EnhancementProviderID) {
        let svc = service(for: provider)
        // Delete any existing entry first; SecItemAdd with the same
        // attributes returns errSecDuplicateItem otherwise.
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return }
        guard let data = key.data(using: .utf8) else { return }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func apiKey(for provider: EnhancementProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: provider),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func hasAPIKey(for provider: EnhancementProviderID) -> Bool {
        guard let key = apiKey(for: provider) else { return false }
        return !key.isEmpty
    }
}
