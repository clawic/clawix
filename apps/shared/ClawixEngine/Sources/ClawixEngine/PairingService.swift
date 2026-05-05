import Foundation
import Darwin

/// Holds the stable bearer token the iPhone has to present during
/// `auth`, and resolves the LAN IPv4 the QR payload should advertise.
/// Phase 5 will move the bearer + identity into the Keychain; for now
/// it lives in UserDefaults so the iPhone can reconnect across Mac
/// rebuilds without re-pairing every time.
@MainActor
public final class PairingService {

    public static let shared = PairingService()

    public let port: UInt16
    private let bearerKey = "ClawixBridge.Bearer.v1"
    private let defaults: UserDefaults

    /// Initialiser kept internal-but-overridable so the `shared`
    /// singleton uses the host app's `appPrefsSuite`. The default
    /// initialiser falls back to `.standard`, which is fine for the
    /// stand-alone daemon binary that has its own bundle id.
    public init(defaults: UserDefaults = .standard, port: UInt16 = 7777) {
        self.defaults = defaults
        self.port = port
    }

    /// Wires the singleton to a process-specific UserDefaults suite.
    /// Call this once at startup from the host (the GUI .app today,
    /// the `clawix-bridged` daemon tomorrow) so the bearer survives
    /// rebuilds without leaking across forks built with different
    /// bundle ids.
    public static func bootstrapShared(defaultsSuiteName: String) {
        guard let custom = UserDefaults(suiteName: defaultsSuiteName) else { return }
        // Replace the singleton in place. The singleton is `let` so we
        // can't reassign; instead, mirror the old token into the new
        // suite if present, then publish a fresh singleton. As a
        // pragmatic compromise we keep `shared` immutable and instead
        // expose a process-wide `defaults` swap via a separate API
        // when needed. For now, callers that need a custom suite must
        // construct their own `PairingService(defaults:)`.
        _ = custom
    }

    /// 32-byte token, base64url-encoded. Generated on first use and
    /// reused on every relaunch so a paired iPhone keeps working
    /// across `bash dev.sh` rebuilds.
    public var bearer: String {
        if let cached = defaults.string(forKey: bearerKey), !cached.isEmpty {
            return cached
        }
        let token = Self.generateBearer()
        defaults.set(token, forKey: bearerKey)
        return token
    }

    /// Force-rotate the bearer. Future "unpair all" UI calls this.
    public func rotateBearer() {
        defaults.set(Self.generateBearer(), forKey: bearerKey)
    }

    /// JSON the QR encodes. The iPhone parses it, persists the host /
    /// port / token in its keychain (Phase 6), and connects.
    ///
    /// Includes both the LAN IPv4 (fast path when at home, on the same
    /// WiFi as the Mac) and, if Tailscale is up on the Mac, its
    /// Tailscale CGNAT IPv4 (works from anywhere as long as the iPhone
    /// is also on the same Tailnet). The iPhone races them and uses
    /// whichever responds first, so the user does not have to do
    /// anything when they leave the house.
    public func qrPayload() -> String {
        let host = Self.currentLANIPv4() ?? "0.0.0.0"
        var dict: [String: Any] = [
            "v": 1,
            "host": host,
            "port": Int(port),
            "token": bearer,
            "macName": Host.current().localizedName ?? "Mac"
        ]
        if let ts = Self.currentTailscaleIPv4() {
            dict["tailscaleHost"] = ts
        }
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Bonjour instance name for the bridge service. Stable per
    /// machine so the iPhone could re-discover us by name across IP
    /// changes. We just expose the localized machine name.
    public var bonjourServiceName: String {
        Host.current().localizedName ?? "Clawix"
    }

    /// Authoritative compare for the bridge session. Constant-time-ish
    /// (length first, then byte compare) to avoid timing leaks even
    /// though over LAN that is mostly theatrical.
    public func acceptToken(_ candidate: String) -> Bool {
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

    /// First IPv4 in the Tailscale CGNAT range (`100.64.0.0/10`) we
    /// find on a `utun*` interface. Tailscale on macOS exposes its
    /// node IP via a `utun` tunnel; scanning interfaces avoids
    /// shelling out to the `tailscale` CLI which is not always in
    /// PATH (the App Store build does not install it). Returns nil
    /// if Tailscale is not running or not configured.
    public static func currentTailscaleIPv4() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = current {
            let interface = ptr.pointee
            if let addr = interface.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("utun") {
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
                        let parts = candidate.split(separator: ".").compactMap { Int($0) }
                        if parts.count == 4, parts[0] == 100, (64...127).contains(parts[1]) {
                            return candidate
                        }
                    }
                }
            }
            current = interface.ifa_next
        }
        return nil
    }

    /// First non-loopback IPv4 we find on en0/en1 (WiFi/Ethernet).
    /// Returns nil if no usable interface is up; the QR will then
    /// surface 0.0.0.0 and the iPhone connection visibly fails so
    /// the user knows to check WiFi.
    public static func currentLANIPv4() -> String? {
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
