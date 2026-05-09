import XCTest
@testable import SecretsModels

final class RecordsTests: XCTestCase {

    func testSecretRecordRoundTrip() throws {
        let vaultId = EntityID.newID()
        let versionId = EntityID.newID()
        let original = SecretRecord(
            vaultId: vaultId,
            kind: .apiKey,
            internalName: "service_main",
            title: "Service · main",
            wrappedItemKey: Data(repeating: 0xFF, count: 29),
            currentVersionId: versionId,
            allowedHostsJson: #"["api.example.com"]"#,
            allowedHeadersJson: #"["Authorization"]"#
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SecretRecord.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testGovernanceComputedRoundTrip() {
        let vaultId = EntityID.newID()
        let versionId = EntityID.newID()
        var record = SecretRecord(
            vaultId: vaultId,
            kind: .apiKey,
            internalName: "x",
            title: "X",
            wrappedItemKey: Data(),
            currentVersionId: versionId
        )
        var gov = Governance.permissive
        gov.allowedHosts = ["a.example.com", "b.example.com"]
        gov.allowedHeaders = ["X-API-Key"]
        gov.allowInBody = true
        gov.approvalMode = .window
        gov.approvalWindowMinutes = 10
        gov.allowedAgents = ["codex", "claude-code"]
        record.governance = gov

        let read = record.governance
        XCTAssertEqual(read.allowedHosts, ["a.example.com", "b.example.com"])
        XCTAssertEqual(read.allowedHeaders, ["X-API-Key"])
        XCTAssertTrue(read.allowInBody)
        XCTAssertEqual(read.approvalMode, .window)
        XCTAssertEqual(read.approvalWindowMinutes, 10)
        XCTAssertEqual(read.allowedAgents, ["codex", "claude-code"])
    }

    func testTagsComputedRoundTrip() {
        var record = SecretRecord(
            vaultId: EntityID.newID(),
            kind: .secureNote,
            internalName: "n",
            title: "N",
            wrappedItemKey: Data(),
            currentVersionId: EntityID.newID()
        )
        XCTAssertEqual(record.tags, [])
        record.tags = ["personal", "important"]
        XCTAssertEqual(record.tags, ["personal", "important"])
        XCTAssertNotNil(record.tagsJson)
        record.tags = []
        XCTAssertNil(record.tagsJson)
    }

    func testAuditEventRoundTrip() throws {
        let event = AuditEventRecord(
            kind: .proxyRequest,
            source: .proxy,
            success: true,
            deviceId: "device-1",
            sessionId: "session-2",
            wrappedEventKey: Data(repeating: 0xAA, count: 29),
            payloadCiphertext: Data(repeating: 0xBB, count: 64),
            prevHash: Data(repeating: 0xCC, count: 32),
            selfHash: Data(repeating: 0xDD, count: 32)
        )
        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AuditEventRecord.self, from: encoded)
        XCTAssertEqual(decoded, event)
    }

    func testAuditEventPayloadRoundTrip() throws {
        let payload = AuditEventPayload(
            requesterPid: 12345,
            requesterImage: "/usr/local/bin/codex",
            agentName: "codex",
            capability: .githubReleaseCreate,
            host: "api.github.com",
            httpMethod: "POST",
            requestId: "req-1",
            redactedRequest: #"{"url":"https://api.github.com","headers":{"Authorization":"Bearer [REDACTED:github_main]"}}"#,
            responseSize: 1024,
            latencyMs: 312,
            errorCode: nil,
            agentGrantId: EntityID.newID(),
            notes: nil,
            secretInternalNameFrozen: "github_main",
            secretKindFrozen: .apiKey,
            userLabel: "release v0.2.0"
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AuditEventPayload.self, from: encoded)
        XCTAssertEqual(decoded, payload)
    }

    func testEnumsRawValuesAreStable() {
        XCTAssertEqual(SecretKind.passwordLogin.rawValue, "password_login")
        XCTAssertEqual(SecretKind.apiKey.rawValue, "api_key")
        XCTAssertEqual(AuditEventKind.proxyRequest.rawValue, "proxy_request")
        XCTAssertEqual(AuditEventKind.adminCompromise.rawValue, "admin_compromise")
        XCTAssertEqual(ApprovalMode.everyUse.rawValue, "every-use")
        XCTAssertEqual(AgentCapability.githubReleaseCreate.rawValue, "github_release_create")
        XCTAssertEqual(SecretVersionReason.proxyRefresh.rawValue, "proxy_refresh")
    }

    func testBrandPresetRoundTrip() throws {
        let preset = BrandPreset(
            id: "github",
            displayName: "GitHub",
            iconId: "github",
            defaultKind: .apiKey,
            prefilledFields: [
                BrandPresetField(name: "token", fieldKind: .password, placement: .header, isSecret: true)
            ],
            defaultAllowedHosts: ["api.github.com", "*.githubusercontent.com"],
            defaultAllowedHeaders: ["Authorization"],
            notes: "Personal Access Token (classic) or fine-grained PAT."
        )
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(BrandPreset.self, from: encoded)
        XCTAssertEqual(decoded, preset)
    }

    func testTimestampNowIsRecent() {
        let now = Clock.now()
        let date = now.asDate
        XCTAssertEqual(date.timeIntervalSinceNow, 0, accuracy: 1.0)
    }
}
