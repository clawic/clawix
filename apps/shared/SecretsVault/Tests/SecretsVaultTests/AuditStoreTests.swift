import XCTest
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence
@testable import SecretsVault
import ClawixArgon2

final class AuditStoreTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func makeStore() throws -> (AuditStore, VaultBootstrap, SecretsDatabase) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let audit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "device-1"
        )
        return (audit, bootstrap, database)
    }

    func testAppendAndDecryptRoundTrip() throws {
        let (audit, _, _) = try makeStore()
        let payload = AuditEventPayload(
            host: "api.example.com",
            httpMethod: "GET",
            redactedRequest: #"{"headers":{"Authorization":"Bearer [REDACTED:service_main]"}}"#,
            secretInternalNameFrozen: "service_main",
            secretKindFrozen: .apiKey
        )
        let record = try audit.append(NewAuditEvent(
            kind: .proxyRequest,
            source: .proxy,
            secretId: EntityID.newID(),
            vaultId: EntityID.newID(),
            success: true,
            payload: payload
        ))
        XCTAssertEqual(record.kind, .proxyRequest)
        XCTAssertEqual(record.deviceId, "device-1")
        XCTAssertEqual(record.prevHash.count, 32)
        XCTAssertEqual(record.selfHash.count, 32)

        let decoded = try audit.decrypt(record)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(decoded.kind, .proxyRequest)
    }

    func testChainStaysIntactAcrossManyAppends() throws {
        let (audit, _, _) = try makeStore()
        for i in 0..<50 {
            try audit.append(NewAuditEvent(
                kind: .uiReveal,
                source: .ui,
                payload: AuditEventPayload(notes: "iteration \(i)")
            ))
        }
        let report = try audit.verifyIntegrity()
        XCTAssertEqual(report.totalEvents, 50)
        XCTAssertNil(report.firstBrokenAt)
        XCTAssertTrue(report.isIntact)
    }

    func testTamperingPayloadCiphertextBreaksIntegrity() throws {
        let (audit, _, database) = try makeStore()
        try audit.append(NewAuditEvent(kind: .vaultSetup, source: .system))
        let inserted = try audit.append(NewAuditEvent(kind: .uiCopy, source: .ui))

        try database.write { db in
            var corrupted = inserted.payloadCiphertext
            let lastIdx = corrupted.endIndex - 1
            corrupted[lastIdx] ^= 0x80
            try db.execute(
                sql: "UPDATE auditEvents SET payloadCiphertext = ? WHERE id = ?",
                arguments: [corrupted, inserted.id.uuidString.uppercased()]
            )
        }

        let report = try audit.verifyIntegrity()
        XCTAssertEqual(report.firstBrokenAt, inserted.id)
        XCTAssertFalse(report.isIntact)
    }

    func testTamperingClearKindBreaksIntegrity() throws {
        let (audit, _, database) = try makeStore()
        try audit.append(NewAuditEvent(kind: .vaultSetup, source: .system))
        let inserted = try audit.append(NewAuditEvent(kind: .uiReveal, source: .ui))

        try database.write { db in
            try db.execute(
                sql: "UPDATE auditEvents SET kind = ? WHERE id = ?",
                arguments: ["ui_copy", inserted.id.uuidString.uppercased()]
            )
        }

        let report = try audit.verifyIntegrity()
        XCTAssertEqual(report.firstBrokenAt, inserted.id)
    }

    func testDeletingMiddleEventBreaksChain() throws {
        let (audit, _, database) = try makeStore()
        try audit.append(NewAuditEvent(kind: .vaultSetup, source: .system))
        let middle = try audit.append(NewAuditEvent(kind: .adminCreate, source: .admin))
        try audit.append(NewAuditEvent(kind: .uiReveal, source: .ui))

        try database.write { db in
            try db.execute(
                sql: "DELETE FROM auditEvents WHERE id = ?",
                arguments: [middle.id.uuidString.uppercased()]
            )
        }

        let report = try audit.verifyIntegrity()
        XCTAssertNotNil(report.firstBrokenAt)
        XCTAssertEqual(report.totalEvents, 2)
    }

    func testWrongAuditMacKeyFailsToDecrypt() throws {
        let (audit, _, database) = try makeStore()
        let inserted = try audit.append(NewAuditEvent(
            kind: .uiReveal,
            source: .ui,
            payload: AuditEventPayload(notes: "secret note")
        ))

        let alien = AuditStore(
            database: database,
            auditMacKey: LockableSecret.random(byteCount: 32),
            chainGenesis: Data(repeating: 0xFF, count: 32),
            deviceId: "device-1"
        )
        XCTAssertThrowsError(try alien.decrypt(inserted)) { err in
            XCTAssertEqual(err as? AuditStoreError, .decryptionFailed)
        }
    }

    func testEventsForSecretFilters() throws {
        let (audit, _, _) = try makeStore()
        let s1 = EntityID.newID()
        let s2 = EntityID.newID()
        try audit.append(NewAuditEvent(kind: .adminCreate, source: .admin, secretId: s1))
        try audit.append(NewAuditEvent(kind: .uiReveal, source: .ui, secretId: s1))
        try audit.append(NewAuditEvent(kind: .adminCreate, source: .admin, secretId: s2))

        let onlyS1 = try audit.eventsForSecret(s1)
        XCTAssertEqual(onlyS1.count, 2)
        XCTAssertTrue(onlyS1.allSatisfy { $0.secretId == s1 })

        let onlyS2 = try audit.eventsForSecret(s2)
        XCTAssertEqual(onlyS2.count, 1)
    }

    func testFilteredEventsByKind() throws {
        let (audit, _, _) = try makeStore()
        try audit.append(NewAuditEvent(kind: .adminCreate, source: .admin))
        try audit.append(NewAuditEvent(kind: .uiReveal, source: .ui))
        try audit.append(NewAuditEvent(kind: .uiCopy, source: .ui))

        let creates = try audit.filteredEvents(AuditEventFilter(kinds: [.adminCreate]))
        XCTAssertEqual(creates.count, 1)

        let userActions = try audit.filteredEvents(AuditEventFilter(kinds: [.uiReveal, .uiCopy]))
        XCTAssertEqual(userActions.count, 2)
    }

    func testTimestampsAreMonotonic() throws {
        let (audit, _, _) = try makeStore()
        var lastTs: Timestamp = 0
        for _ in 0..<200 {
            let r = try audit.append(NewAuditEvent(kind: .uiView, source: .ui))
            XCTAssertGreaterThan(r.timestamp, lastTs)
            lastTs = r.timestamp
        }
    }

    func testIntegrityHoldsAfterPasswordRotation() throws {
        // Audit MAC key survives password change. New events appended with the
        // post-rotation key set must verify against the same chain as the
        // pre-rotation events.
        let bootstrap = try VaultCrypto.setUp(masterPassword: "old", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let beforeAudit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "device-1"
        )
        try beforeAudit.append(NewAuditEvent(kind: .vaultSetup, source: .system))
        try beforeAudit.append(NewAuditEvent(kind: .adminCreate, source: .admin))

        let change = try VaultCrypto.changePassword(
            currentMasterKey: bootstrap.masterKey,
            newPassword: "new",
            currentMeta: bootstrap.meta
        )
        let afterAudit = AuditStore(
            database: database,
            auditMacKey: change.auditMacKey,
            chainGenesis: change.meta.auditChainGenesis,
            deviceId: "device-1"
        )
        try afterAudit.append(NewAuditEvent(kind: .vaultPasswordChange, source: .system))
        try afterAudit.append(NewAuditEvent(kind: .uiReveal, source: .ui))

        let report = try afterAudit.verifyIntegrity()
        XCTAssertTrue(report.isIntact, "chain must survive password rotation")
        XCTAssertEqual(report.totalEvents, 4)
    }
}
