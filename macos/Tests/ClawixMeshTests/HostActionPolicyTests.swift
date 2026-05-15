import XCTest
@testable import Clawix

final class HostActionPolicyTests: XCTestCase {
    func testUserInitiatedActionsAreAuditedAndAllowedByDefault() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .screenTools,
            action: "captureArea",
            origin: .userInterface,
            defaults: defaults,
            auditURL: auditURL,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(result.allowed)
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].surface, .screenTools)
        XCTAssertEqual(events[0].action, "captureArea")
        XCTAssertEqual(events[0].origin, .userInterface)
        XCTAssertEqual(events[0].approval, .alwaysAsk)
        XCTAssertEqual(events[0].outcome, "allowed")
    }

    func testAgentActionsRequireExplicitApprovalByDefault() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: "clearClipboard",
            origin: .agent,
            defaults: defaults,
            auditURL: auditURL
        )

        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.outcome, "requiresApproval")
        XCTAssertEqual(result.reason, "Requires explicit host approval.")
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.surface, .macUtilities)
        XCTAssertEqual(events.first?.outcome, "requiresApproval")
    }

    func testAlwaysBlockPolicyBlocksEvenUserInitiatedActions() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()
        defaults.set(HostActionPolicy.Approval.alwaysBlock.rawValue, forKey: HostActionSurface.macUtilities.approvalKey)

        let result = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: "sleepDisplays",
            origin: .userInterface,
            defaults: defaults,
            auditURL: auditURL
        )

        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.outcome, "blocked")
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.approval, .alwaysBlock)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "HostActionPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("host-action-policy-\(UUID().uuidString)")
            .appendingPathComponent(HostActionPolicy.auditFilename)
    }

    private func readAuditEvents(_ url: URL) throws -> [HostActionPolicy.AuditEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.map { try decoder.decode(HostActionPolicy.AuditEvent.self, from: Data($0.utf8)) }
    }
}
