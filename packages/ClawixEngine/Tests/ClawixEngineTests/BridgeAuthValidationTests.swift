import XCTest
@testable import ClawixEngine

final class BridgeAuthValidationTests: XCTestCase {
    func testClientIdentityRequiresAllStableIds() {
        XCTAssertTrue(
            BridgeAuthValidation.hasValidClientIdentity(
                clientId: "client-1",
                installationId: "install-1",
                deviceId: "device-1"
            )
        )

        XCTAssertFalse(
            BridgeAuthValidation.hasValidClientIdentity(
                clientId: "",
                installationId: "install-1",
                deviceId: "device-1"
            )
        )
        XCTAssertFalse(
            BridgeAuthValidation.hasValidClientIdentity(
                clientId: "client-1",
                installationId: "   ",
                deviceId: "device-1"
            )
        )
        XCTAssertFalse(
            BridgeAuthValidation.hasValidClientIdentity(
                clientId: "client-1",
                installationId: "install-1",
                deviceId: "\n\t"
            )
        )
    }
}
