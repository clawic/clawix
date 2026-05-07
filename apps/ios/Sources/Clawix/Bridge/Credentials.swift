import Foundation

struct Credentials: Codable, Equatable {
    var host: String
    var port: Int
    var token: String
    var macName: String?
    /// Tailscale CGNAT IPv4 of the Mac, if it was running Tailscale at
    /// pairing time. Used as a fallback when the LAN host is not
    /// reachable (iPhone on cellular, on a different WiFi, traveling).
    /// Optional so old pairings without this field keep working.
    var tailscaleHost: String?

    var websocketURL: URL? {
        URL(string: "ws://\(host):\(port)")
    }

    /// Ordered list the bridge client should try, fastest-first.
    /// LAN goes first so being at home stays sub-second; Tailscale is
    /// the away path. Empty hosts are skipped so a malformed pairing
    /// does not produce `ws://:7777`.
    var candidateURLs: [URL] {
        var urls: [URL] = []
        for host in [host, tailscaleHost ?? ""] {
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "0.0.0.0" else { continue }
            if let url = URL(string: "ws://\(trimmed):\(port)") {
                urls.append(url)
            }
        }
        return urls
    }
}

final class CredentialStore {
    static let shared = CredentialStore()

    private let key = "ClawixBridge.Credentials.v1"
    private let defaults = UserDefaults.standard

    func load() -> Credentials? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    func save(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct PairingPayload: Codable {
    var v: Int
    var host: String
    var port: Int
    var token: String
    var macName: String?
    var tailscaleHost: String?
    /// Optional 9-character short code the Mac embeds alongside the
    /// long bearer in v0.1.1+. The QR scan path ignores it because
    /// the long bearer is enough to authenticate, but parsing it
    /// keeps the payload future-compatible.
    var shortCode: String?

    static func parse(_ raw: String) -> PairingPayload? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PairingPayload.self, from: data)
    }

    var asCredentials: Credentials {
        Credentials(
            host: host,
            port: port,
            token: token,
            macName: macName,
            tailscaleHost: tailscaleHost
        )
    }
}
