import XCTest
@testable import AIProviders

final class InternalNameTests: XCTestCase {

    func testRoundTripEncodeDecode() {
        let id = UUID()
        let raw = InternalName.encode(providerId: .openai, accountId: id)
        let decoded = InternalName.decode(raw)
        XCTAssertEqual(decoded?.providerId, .openai)
        XCTAssertEqual(decoded?.accountId, id)
    }

    func testEncodeIsLowercaseUUID() {
        let id = UUID()
        let raw = InternalName.encode(providerId: .anthropic, accountId: id)
        XCTAssertTrue(raw.contains(id.uuidString.lowercased()))
        XCTAssertFalse(raw.contains(id.uuidString))
            // ^ guard rail: if both happen to be equal (all zeros UUID
            //   case) this assertion would still pass because lowercased
            //   form still contains uppercased form. Acceptable: real
            //   UUIDs always differ.
    }

    func testDecodeRejectsMissingPrefix() {
        XCTAssertNil(InternalName.decode("openai:\(UUID().uuidString)"))
    }

    func testDecodeRejectsUnknownProvider() {
        let id = UUID().uuidString.lowercased()
        XCTAssertNil(InternalName.decode("provider:not_a_provider:\(id)"))
    }

    func testDecodeRejectsBadUUID() {
        XCTAssertNil(InternalName.decode("provider:openai:not-a-uuid"))
    }

    func testIsOrphanFlagsKnownPatternUnknownProvider() {
        let id = UUID().uuidString.lowercased()
        XCTAssertTrue(InternalName.isOrphan("provider:not_a_provider:\(id)"))
        XCTAssertFalse(InternalName.isOrphan("enhancement.openai"))
        XCTAssertFalse(InternalName.isOrphan(InternalName.encode(providerId: .openai, accountId: UUID())))
    }

    func testAuthMethodStorageTagRoundTrip() {
        let methods: [AuthMethod] = [
            .apiKey,
            .oauth(.anthropicClaudeAi),
            .deviceCode(.githubCopilot),
            .none
        ]
        for method in methods {
            let tag = method.storageTag
            XCTAssertEqual(AuthMethod(storageTag: tag), method,
                           "Round-trip failed for \(method)")
        }
    }
}
