import Foundation

enum BridgeClientIdentity {
    static let clientId = "clawix.macos.desktop"

    static var installationId: String {
        persistedId(forKey: "clawix.bridge.installationId")
    }

    static var deviceId: String {
        persistedId(forKey: "clawix.bridge.deviceId")
    }

    private static func persistedId(forKey key: String) -> String {
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}
