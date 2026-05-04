import Foundation
import Darwin

/// Holds the stable bearer token the iPhone has to present during
/// `auth`, and resolves the LAN IPv4 the QR payload should advertise.
/// Phase 5 will move the bearer + identity into the Keychain; for now
/// it lives in UserDefaults so the iPhone can reconnect across Mac
/// rebuilds without re-pairing every time.
@MainActor
final class PairingService {

    static let shared = PairingService()

    let port: UInt16 = 7777
    private let bearerKey = "ClawixBridge.Bearer.v1"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .init(suiteName: appPrefsSuite) ?? .standard) {
        self.defaults = defaults
    }

    /// 32-byte token, base64url-encoded. Generated on first use and
    /// reused on every relaunch so a paired iPhone keeps working
    /// across `bash dev.sh` rebuilds.
    var bearer: String {
        if let cached = defaults.string(forKey: bearerKey), !cached.isEmpty {
            return cached
        }
        let token = Self.generateBearer()
        defaults.set(token, forKey: bearerKey)
        return token
    }

    /// Force-rotate the bearer. Future "unpair all" UI calls this.
    func rotateBearer() {
        defaults.set(Self.generateBearer(), forKey: bearerKey)
    }

    /// JSON the QR encodes. The iPhone parses it, persists the host /
    /// port / token in its keychain (Phase 6), and connects.
    func qrPayload() -> String {
        let host = Self.currentLANIPv4() ?? "0.0.0.0"
        let dict: [String: Any] = [
            "v": 1,
            "host": host,
            "port": Int(port),
            "token": bearer,
            "macName": Host.current().localizedName ?? "Mac"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Authoritative compare for the bridge session. Constant-time-ish
    /// (length first, then byte compare) to avoid timing leaks even
    /// though over LAN that is mostly theatrical.
    func acceptToken(_ candidate: String) -> Bool {
        let truth = bearer
        guard candidate.utf8.count == truth.utf8.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate.utf8, truth.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }

    private static func generateBearer() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard rc == errSecSuccess else {
            // Fallback that should never trigger; keep the bearer non-empty.
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// First non-loopback IPv4 we find on en0/en1 (WiFi/Ethernet).
    /// Returns nil if no usable interface is up; the QR will then
    /// surface 0.0.0.0 and the iPhone connection visibly fails so
    /// the user knows to check WiFi.
    static func currentLANIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var found: String?
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = current {
            let interface = ptr.pointee
            if let addr = interface.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let rc = getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if rc == 0 {
                        let candidate = String(cString: hostname)
                        if !candidate.hasPrefix("127.") && !candidate.hasPrefix("169.254.") {
                            found = candidate
                            if name == "en0" { break }
                        }
                    }
                }
            }
            current = interface.ifa_next
        }
        return found
    }
}
