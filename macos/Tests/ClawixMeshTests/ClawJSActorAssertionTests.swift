import CryptoKit
import XCTest
@testable import Clawix

final class ClawJSActorAssertionTests: XCTestCase {
    func testEnvironmentCarriesSignedHumanActorAssertionAndTrustAnchor() throws {
        let env = ClawJSActorAssertion.environment()

        let assertion = try XCTUnwrap(env["CLAW_ACTOR_ASSERTION"])
        let trustedKeys = try XCTUnwrap(env["CLAW_ACTOR_TRUSTED_KEYS"])
        let assertionJSON = try jsonObject(assertion)
        let trustJSON = try jsonArray(trustedKeys)
        let trustAnchor = try XCTUnwrap(trustJSON.first as? [String: Any])

        XCTAssertEqual(assertionJSON["schemaVersion"] as? Int, 1)
        XCTAssertEqual(assertionJSON["actorKind"] as? String, "human")
        XCTAssertEqual(assertionJSON["actorId"] as? String, "local-user")
        XCTAssertEqual(assertionJSON["trustSource"] as? String, "signed-host")
        XCTAssertEqual(assertionJSON["issuer"] as? String, "com.clawix.app")
        XCTAssertEqual(assertionJSON["keyId"] as? String, "clawix-local-v1")
        XCTAssertNotNil(assertionJSON["signature"] as? String)
        XCTAssertEqual(assertionJSON["scope"] as? [String], ["claw.app-state", "claw.cli", "claw.resources"])

        XCTAssertEqual(trustAnchor["keyId"] as? String, "clawix-local-v1")
        XCTAssertEqual(trustAnchor["trustSource"] as? String, "signed-host")
        XCTAssertEqual(trustAnchor["issuer"] as? String, "com.clawix.app")
        let publicKeyPEM = try XCTUnwrap(trustAnchor["publicKeyPem"] as? String)
        XCTAssertTrue(publicKeyPEM.contains("BEGIN PUBLIC KEY"))

        let canonicalPayload = try canonicalActorAssertionPayload(assertionJSON)
        let signature = try XCTUnwrap(base64UrlDecode(try XCTUnwrap(assertionJSON["signature"] as? String)))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawEd25519PublicKey(from: publicKeyPEM))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(canonicalPayload.utf8)))
    }

    private func jsonObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func jsonArray(_ json: String) throws -> [Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    private func canonicalActorAssertionPayload(_ payload: [String: Any]) throws -> String {
        let scope = try XCTUnwrap(payload["scope"] as? [String]).sorted().map(jsonString).joined(separator: ",")
        return "{"
            + "\"schemaVersion\":\(try XCTUnwrap(payload["schemaVersion"] as? Int)),"
            + "\"actorKind\":\(jsonString(try XCTUnwrap(payload["actorKind"] as? String))),"
            + "\"actorId\":\(jsonString(try XCTUnwrap(payload["actorId"] as? String))),"
            + "\"sessionId\":\(jsonString(try XCTUnwrap(payload["sessionId"] as? String))),"
            + "\"hostId\":\(jsonString(try XCTUnwrap(payload["hostId"] as? String))),"
            + "\"issuedAt\":\(jsonString(try XCTUnwrap(payload["issuedAt"] as? String))),"
            + "\"expiresAt\":\(jsonString(try XCTUnwrap(payload["expiresAt"] as? String))),"
            + "\"scope\":[\(scope)],"
            + "\"trustSource\":\(jsonString(try XCTUnwrap(payload["trustSource"] as? String))),"
            + "\"issuer\":\(jsonString(try XCTUnwrap(payload["issuer"] as? String))),"
            + "\"keyId\":\(jsonString(try XCTUnwrap(payload["keyId"] as? String)))"
            + "}"
    }

    private func rawEd25519PublicKey(from pem: String) throws -> Data {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let der = try XCTUnwrap(Data(base64Encoded: base64))
        return der.suffix(32)
    }

    private func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64)
    }
}
