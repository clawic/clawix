import CryptoKit
import Foundation

enum ClawJSActorAssertion {
    private static let keyId = "clawix-local-v1"
    private static let issuer = "com.clawix.app"
    private static let hostId = Bundle.main.bundleIdentifier ?? "com.clawix.app"
    private static let sessionId = UUID().uuidString
    private static let signingKey = Curve25519.Signing.PrivateKey()

    static func environment(now: Date = Date()) -> [String: String] {
        let issuedAt = isoString(now)
        let expiresAt = isoString(now.addingTimeInterval(5 * 60))
        let scope = ["claw.cli", "claw.app-state", "claw.resources"]
        let payload = canonicalPayload(
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            scope: scope
        )
        guard let payloadData = payload.data(using: .utf8),
              let signature = try? signingKey.signature(for: payloadData)
        else { return [:] }

        let assertion = "{"
            + payload.dropFirst().dropLast()
            + ",\"signature\":\(jsonString(base64Url(Data(signature))))"
            + "}"
        let trustedKeys = "[{\"keyId\":\(jsonString(keyId)),\"publicKeyPem\":\(jsonString(publicKeyPEM())),\"trustSource\":\"signed-host\",\"issuer\":\(jsonString(issuer))}]"
        return [
            "CLAW_ACTOR_ASSERTION": assertion,
            "CLAW_ACTOR_TRUSTED_KEYS": trustedKeys
        ]
    }

    private static func canonicalPayload(
        issuedAt: String,
        expiresAt: String,
        scope: [String]
    ) -> String {
        let sortedScope = scope.sorted().map(jsonString).joined(separator: ",")
        return "{"
            + "\"schemaVersion\":1,"
            + "\"actorKind\":\"human\","
            + "\"actorId\":\"local-user\","
            + "\"sessionId\":\(jsonString(sessionId)),"
            + "\"hostId\":\(jsonString(hostId)),"
            + "\"issuedAt\":\(jsonString(issuedAt)),"
            + "\"expiresAt\":\(jsonString(expiresAt)),"
            + "\"scope\":[\(sortedScope)],"
            + "\"trustSource\":\"signed-host\","
            + "\"issuer\":\(jsonString(issuer)),"
            + "\"keyId\":\(jsonString(keyId))"
            + "}"
    }

    private static func publicKeyPEM() -> String {
        let ed25519SubjectPublicKeyInfoPrefix = Data([
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
            0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
        ])
        let der = ed25519SubjectPublicKeyInfoPrefix + signingKey.publicKey.rawRepresentation
        return "-----BEGIN PUBLIC KEY-----\n\(der.base64EncodedString())\n-----END PUBLIC KEY-----"
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private static func base64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
