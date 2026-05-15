import XCTest
@testable import Clawix

final class ClawixProtocolEncodingTests: XCTestCase {
    func testInitializeCapabilitiesUseStableLocalNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            InitializeCapabilities(
                extensionFields: true,
                optOutNotificationMethods: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["experimentalApi"] as? Bool, true)
        XCTAssertNil(object?["extensionFields"])
    }

    func testThreadStartUsesStableLocalPersonalizationNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            ThreadStartParams(
                cwd: "/tmp/project",
                model: "gpt-5.4",
                approvalPolicy: "never",
                sandbox: "danger-full-access",
                personalizationPreset: "pragmatic",
                serviceTier: "fast",
                activeSkills: nil,
                collaborationMode: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["personality"] as? String, "pragmatic")
        XCTAssertNil(object?["personalizationPreset"])
    }
}
