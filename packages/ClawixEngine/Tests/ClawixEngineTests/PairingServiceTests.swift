import XCTest
@testable import ClawixEngine

@MainActor
final class PairingServiceTests: XCTestCase {
    func testQrPayloadUsesStableV1JsonContract() throws {
        let defaults = try isolatedDefaults()
        defaults.set("token-test", forKey: ClawixPersistentSurfaceKeys.bridgeBearer)
        defaults.set("ABC-234-XYZ", forKey: ClawixPersistentSurfaceKeys.bridgeShortCode)

        let service = PairingService(defaults: defaults, port: 24080)
        let json = service.qrPayload()
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["port"] as? Int, 24080)
        XCTAssertEqual(object["token"] as? String, "token-test")
        XCTAssertEqual(object["shortCode"] as? String, "ABC-234-XYZ")
        XCTAssertNotNil(object["host"] as? String)
        XCTAssertNotNil(object["hostDisplayName"] as? String)
        XCTAssertNil(object["bearer"])
        XCTAssertFalse(json.contains("clawix://pair"))
    }

    func testShortCodeAndBearerAreAcceptedForAuthHandshake() throws {
        let defaults = try isolatedDefaults()
        defaults.set("token-test", forKey: ClawixPersistentSurfaceKeys.bridgeBearer)
        defaults.set("ABC-234-XYZ", forKey: ClawixPersistentSurfaceKeys.bridgeShortCode)

        let service = PairingService(defaults: defaults, port: 24080)

        XCTAssertTrue(service.acceptToken("token-test"))
        XCTAssertFalse(service.acceptToken("wrong-token"))
        XCTAssertTrue(service.acceptShortCode("abc234xyz"))
        XCTAssertTrue(service.acceptShortCode("ABC-234-XYZ"))
        XCTAssertFalse(service.acceptShortCode("ABC-234-XYQ"))
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "clawix.pairing.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
