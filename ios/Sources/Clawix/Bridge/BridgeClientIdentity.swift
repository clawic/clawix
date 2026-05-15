import Foundation
import UIKit

enum BridgeClientIdentity {
    static let clientId = "clawix.ios.companion"

    static var installationId: String {
        persistedId(forKey: "clawix.bridge.installationId")
    }

    static var deviceId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString.lowercased(), !vendorId.isEmpty {
            return vendorId
        }
        return persistedId(forKey: "clawix.bridge.deviceId")
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
