import XCTest
import SecretsModels
@testable import SecretsVault

final class AnomalyDetectorTests: XCTestCase {

    private func event(
        kind: AuditEventKind = .proxyRequest,
        secretId: EntityID? = nil,
        host: String? = nil,
        agent: String? = nil,
        timestamp: Timestamp,
        secretName: String? = nil
    ) -> DecryptedAuditEvent {
        DecryptedAuditEvent(
            id: EntityID.newID(),
            secretId: secretId,
            vaultId: nil,
            versionId: nil,
            kind: kind,
            timestamp: timestamp,
            source: .proxy,
            success: true,
            deviceId: "test-device",
            sessionId: nil,
            payload: AuditEventPayload(
                agentName: agent,
                host: host,
                secretInternalNameFrozen: secretName
            )
        )
    }

    func testNewHostFlagged() {
        let now: Timestamp = 1_700_000_000_000
        let secretId = EntityID.newID()
        let day = Timestamp(24 * 60 * 60 * 1000)
        let events: [DecryptedAuditEvent] = [
            // 6 days ago: api.example.com (baseline)
            event(secretId: secretId, host: "api.example.com", timestamp: now - 6 * day, secretName: "service"),
            // 5 days ago: api.example.com (baseline)
            event(secretId: secretId, host: "api.example.com", timestamp: now - 5 * day, secretName: "service"),
            // 1 hour ago: NEW host evil.example.com
            event(secretId: secretId, host: "evil.example.com", timestamp: now - 60 * 60 * 1000, secretName: "service")
        ]
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.contains { $0.kind == .newHost && $0.summary.contains("evil.example.com") })
    }

    func testNewAgentFlagged() {
        let now: Timestamp = 1_700_000_000_000
        let day = Timestamp(24 * 60 * 60 * 1000)
        let secretId = EntityID.newID()
        let events: [DecryptedAuditEvent] = [
            event(secretId: secretId, host: "api.example.com", agent: "codex", timestamp: now - 4 * day, secretName: "x"),
            event(secretId: secretId, host: "api.example.com", agent: "claude-code", timestamp: now - 60 * 1000, secretName: "x")
        ]
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.contains { $0.kind == .newAgent && $0.summary.contains("claude-code") })
    }

    func testUsageSpikeFlagged() {
        let now: Timestamp = 1_700_000_000_000
        let day = Timestamp(24 * 60 * 60 * 1000)
        let secretId = EntityID.newID()
        var events: [DecryptedAuditEvent] = []
        // Baseline: 6 events spread across 6 days = 1/day.
        for i in 1...6 {
            events.append(event(secretId: secretId, host: "h", timestamp: now - Timestamp(i) * day, secretName: "x"))
        }
        // Lookback: 20 events in last 24h → 20x baseline.
        for i in 0..<20 {
            events.append(event(secretId: secretId, host: "h", timestamp: now - Timestamp(i) * 60_000, secretName: "x"))
        }
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.contains { $0.kind == .usageSpike })
    }

    func testFailedUnlockSpikeFlagged() {
        let now: Timestamp = 1_700_000_000_000
        var events: [DecryptedAuditEvent] = []
        for i in 0..<7 {
            events.append(event(kind: .vaultFailedUnlock, timestamp: now - Timestamp(i) * 60_000))
        }
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.contains { $0.kind == .failedUnlockSpike })
    }

    func testOffHoursFlagged() {
        // Pick a timestamp that lands at 03:00 local time.
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 8
        components.hour = 3
        components.minute = 30
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: components)!
        let ts = Timestamp(date.timeIntervalSince1970 * 1000)
        let now = ts + 60 * 60 * 1000  // 1h later (still inside lookback window)
        let secretId = EntityID.newID()
        let events: [DecryptedAuditEvent] = [
            event(secretId: secretId, host: "h", timestamp: ts, secretName: "x")
        ]
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.contains { $0.kind == .offHoursAccess })
    }

    func testNoFalsePositivesWithBaseline() {
        let now: Timestamp = 1_700_000_000_000
        let day = Timestamp(24 * 60 * 60 * 1000)
        let secretId = EntityID.newID()
        var events: [DecryptedAuditEvent] = []
        // 7 days of "1 access per day to api.example.com from codex" — no anomaly.
        for i in 0...6 {
            events.append(event(secretId: secretId, host: "api.example.com", agent: "codex", timestamp: now - Timestamp(i) * day, secretName: "x"))
        }
        let anomalies = AnomalyDetector.detect(events: events, now: now)
        XCTAssertTrue(anomalies.allSatisfy { $0.kind != .newHost && $0.kind != .newAgent && $0.kind != .usageSpike })
    }

    func testAnomalyIDIsStableForDeduplication() {
        let secretId = EntityID.newID()
        let a = Anomaly(kind: .newHost, secretId: secretId, secretInternalName: "x", detectedAt: 1, summary: "First-time host 'h' for secret x")
        let b = Anomaly(kind: .newHost, secretId: secretId, secretInternalName: "x", detectedAt: 999, summary: "First-time host 'h' for secret x")
        XCTAssertEqual(a.id, b.id, "anomalies with same kind+secret+summary must dedupe by id")
    }
}
