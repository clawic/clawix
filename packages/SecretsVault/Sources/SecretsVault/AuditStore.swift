import Foundation
import CryptoKit
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence

public enum AuditStoreError: Swift.Error, Equatable, CustomStringConvertible {
    case decryptionFailed
    case eventNotFound

    public var description: String {
        switch self {
        case .decryptionFailed: return "AuditStore: could not decrypt event payload"
        case .eventNotFound: return "AuditStore: event not found"
        }
    }
}

public struct NewAuditEvent: Sendable {
    public var kind: AuditEventKind
    public var source: AuditEventSource
    public var secretId: EntityID?
    public var vaultId: EntityID?
    public var versionId: EntityID?
    public var success: Bool?
    public var sessionId: String?
    public var payload: AuditEventPayload

    public init(
        kind: AuditEventKind,
        source: AuditEventSource,
        secretId: EntityID? = nil,
        vaultId: EntityID? = nil,
        versionId: EntityID? = nil,
        success: Bool? = nil,
        sessionId: String? = nil,
        payload: AuditEventPayload = AuditEventPayload()
    ) {
        self.kind = kind
        self.source = source
        self.secretId = secretId
        self.vaultId = vaultId
        self.versionId = versionId
        self.success = success
        self.sessionId = sessionId
        self.payload = payload
    }
}

public struct DecryptedAuditEvent: Sendable, Hashable {
    public let id: EntityID
    public let secretId: EntityID?
    public let vaultId: EntityID?
    public let versionId: EntityID?
    public let kind: AuditEventKind
    public let timestamp: Timestamp
    public let source: AuditEventSource
    public let success: Bool?
    public let deviceId: String?
    public let sessionId: String?
    public let payload: AuditEventPayload

    public init(
        id: EntityID,
        secretId: EntityID? = nil,
        vaultId: EntityID? = nil,
        versionId: EntityID? = nil,
        kind: AuditEventKind,
        timestamp: Timestamp,
        source: AuditEventSource,
        success: Bool? = nil,
        deviceId: String? = nil,
        sessionId: String? = nil,
        payload: AuditEventPayload
    ) {
        self.id = id
        self.secretId = secretId
        self.vaultId = vaultId
        self.versionId = versionId
        self.kind = kind
        self.timestamp = timestamp
        self.source = source
        self.success = success
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.payload = payload
    }
}

public struct AuditIntegrityReport: Sendable, Hashable {
    public let totalEvents: Int
    public let firstBrokenAt: EntityID?

    public var isIntact: Bool { firstBrokenAt == nil }

    public init(totalEvents: Int, firstBrokenAt: EntityID? = nil) {
        self.totalEvents = totalEvents
        self.firstBrokenAt = firstBrokenAt
    }
}

public struct AuditEventFilter: Sendable, Hashable {
    public var secretId: EntityID?
    public var vaultId: EntityID?
    public var kinds: [AuditEventKind]
    public var sources: [AuditEventSource]
    public var since: Timestamp?
    public var until: Timestamp?
    public var sessionId: String?

    public init(
        secretId: EntityID? = nil,
        vaultId: EntityID? = nil,
        kinds: [AuditEventKind] = [],
        sources: [AuditEventSource] = [],
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        sessionId: String? = nil
    ) {
        self.secretId = secretId
        self.vaultId = vaultId
        self.kinds = kinds
        self.sources = sources
        self.since = since
        self.until = until
        self.sessionId = sessionId
    }
}

public final class AuditStore {

    public let database: SecretsDatabase
    private let auditMacKey: LockableSecret
    private let chainGenesis: Data
    public let deviceId: String

    public init(database: SecretsDatabase, auditMacKey: LockableSecret, chainGenesis: Data, deviceId: String) {
        self.database = database
        self.auditMacKey = auditMacKey
        self.chainGenesis = chainGenesis
        self.deviceId = deviceId
    }

    @discardableResult
    public func append(_ new: NewAuditEvent, accountId: Int64 = 0) throws -> AuditEventRecord {
        let id = EntityID.newID()

        // Per-event key, wrapped by the audit MAC key (NOT the master key) so
        // password rotation does not invalidate any historical event payload.
        let eventKeyBytes = SecureRandom.bytes(32)
        let eventKey = LockableSecret(bytes: eventKeyBytes)
        let wrappedEventKey = try AEAD.seal(
            plaintext: eventKeyBytes,
            key: auditMacKey,
            aad: Self.aadForKeyWrap(eventId: id)
        )
        let payloadJSON = try JSONEncoder().encode(new.payload)
        let payloadCiphertext = try AEAD.seal(
            plaintext: payloadJSON,
            key: eventKey,
            aad: Self.aadForPayload(eventId: id)
        )

        return try database.write { [self] db -> AuditEventRecord in
            let prevRow = try AuditEventRecord
                .order(Column("timestamp").desc)
                .limit(1)
                .fetchOne(db)
            let prevHash = prevRow?.selfHash ?? chainGenesis
            let now = Clock.now()
            let timestamp: Timestamp
            if let prev = prevRow {
                timestamp = max(now, prev.timestamp + 1)
            } else {
                timestamp = now
            }
            let canonical = Self.canonicalClear(
                id: id, accountId: accountId,
                secretId: new.secretId, vaultId: new.vaultId, versionId: new.versionId,
                kind: new.kind, timestamp: timestamp, source: new.source,
                success: new.success, deviceId: deviceId, sessionId: new.sessionId,
                prevHash: prevHash
            )
            let selfHash = computeSelfHash(canonical: canonical, ciphertext: payloadCiphertext)
            let record = AuditEventRecord(
                id: id,
                accountId: accountId,
                secretId: new.secretId,
                vaultId: new.vaultId,
                versionId: new.versionId,
                kind: new.kind,
                timestamp: timestamp,
                source: new.source,
                success: new.success,
                deviceId: deviceId,
                sessionId: new.sessionId,
                wrappedEventKey: wrappedEventKey,
                payloadCiphertext: payloadCiphertext,
                prevHash: prevHash,
                selfHash: selfHash
            )
            try record.insert(db)
            return record
        }
    }

    // MARK: Fixture seeding (DEV ONLY)
    //
    // Inserts an event using an explicit timestamp instead of Clock.now()
    // so dummy-mode fixtures can paint a realistic activity timeline.
    // Gated by `CLAWIX_FIXTURE_SEEDING=1` (set by `dummy.sh`); a no-op in
    // production. Seed events MUST be appended in ascending timestamp
    // order before any real (non-seed) events run, so the cryptographic
    // chain stays valid: each call uses the latest existing event's
    // selfHash as prevHash, exactly like `append`. If `timestamp` is not
    // strictly greater than the latest existing event, it gets bumped to
    // `prev.timestamp + 1` to preserve the monotonic invariant.
    @discardableResult
    public func _fixtureAppendBackdated(
        _ new: NewAuditEvent,
        timestamp explicitTimestamp: Timestamp,
        accountId: Int64 = 0
    ) throws -> AuditEventRecord? {
        guard ProcessInfo.processInfo.environment["CLAWIX_FIXTURE_SEEDING"] == "1" else { return nil }
        let id = EntityID.newID()
        let eventKeyBytes = SecureRandom.bytes(32)
        let eventKey = LockableSecret(bytes: eventKeyBytes)
        let wrappedEventKey = try AEAD.seal(
            plaintext: eventKeyBytes,
            key: auditMacKey,
            aad: Self.aadForKeyWrap(eventId: id)
        )
        let payloadJSON = try JSONEncoder().encode(new.payload)
        let payloadCiphertext = try AEAD.seal(
            plaintext: payloadJSON,
            key: eventKey,
            aad: Self.aadForPayload(eventId: id)
        )

        return try database.write { [self] db -> AuditEventRecord in
            let prevRow = try AuditEventRecord
                .order(Column("timestamp").desc)
                .limit(1)
                .fetchOne(db)
            let prevHash = prevRow?.selfHash ?? chainGenesis
            let timestamp: Timestamp
            if let prev = prevRow {
                timestamp = max(explicitTimestamp, prev.timestamp + 1)
            } else {
                timestamp = explicitTimestamp
            }
            let canonical = Self.canonicalClear(
                id: id, accountId: accountId,
                secretId: new.secretId, vaultId: new.vaultId, versionId: new.versionId,
                kind: new.kind, timestamp: timestamp, source: new.source,
                success: new.success, deviceId: deviceId, sessionId: new.sessionId,
                prevHash: prevHash
            )
            let selfHash = computeSelfHash(canonical: canonical, ciphertext: payloadCiphertext)
            let record = AuditEventRecord(
                id: id,
                accountId: accountId,
                secretId: new.secretId,
                vaultId: new.vaultId,
                versionId: new.versionId,
                kind: new.kind,
                timestamp: timestamp,
                source: new.source,
                success: new.success,
                deviceId: deviceId,
                sessionId: new.sessionId,
                wrappedEventKey: wrappedEventKey,
                payloadCiphertext: payloadCiphertext,
                prevHash: prevHash,
                selfHash: selfHash
            )
            try record.insert(db)
            return record
        }
    }

    public func decrypt(_ record: AuditEventRecord) throws -> DecryptedAuditEvent {
        do {
            let eventKeyBytes = try AEAD.open(
                blob: record.wrappedEventKey,
                key: auditMacKey,
                aad: Self.aadForKeyWrap(eventId: record.id)
            )
            let eventKey = LockableSecret(bytes: eventKeyBytes)
            let payloadJSON = try AEAD.open(
                blob: record.payloadCiphertext,
                key: eventKey,
                aad: Self.aadForPayload(eventId: record.id)
            )
            let payload = try JSONDecoder().decode(AuditEventPayload.self, from: payloadJSON)
            return DecryptedAuditEvent(
                id: record.id,
                secretId: record.secretId,
                vaultId: record.vaultId,
                versionId: record.versionId,
                kind: record.kind,
                timestamp: record.timestamp,
                source: record.source,
                success: record.success,
                deviceId: record.deviceId,
                sessionId: record.sessionId,
                payload: payload
            )
        } catch {
            throw AuditStoreError.decryptionFailed
        }
    }

    public func recentEvents(limit: Int = 100) throws -> [DecryptedAuditEvent] {
        let records = try database.read { db in
            try AuditEventRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return try records.map { try decrypt($0) }
    }

    public func eventsForSecret(_ secretId: EntityID, limit: Int = 100) throws -> [DecryptedAuditEvent] {
        let records = try database.read { db in
            try AuditEventRecord
                .filter(Column("secretId") == secretId.uuidString.uppercased())
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return try records.map { try decrypt($0) }
    }

    public func filteredEvents(_ filter: AuditEventFilter, limit: Int = 200) throws -> [DecryptedAuditEvent] {
        let records = try database.read { db -> [AuditEventRecord] in
            var query: QueryInterfaceRequest<AuditEventRecord> = AuditEventRecord.all()
            if let id = filter.secretId {
                query = query.filter(Column("secretId") == id.uuidString.uppercased())
            }
            if let id = filter.vaultId {
                query = query.filter(Column("vaultId") == id.uuidString.uppercased())
            }
            if !filter.kinds.isEmpty {
                let raws = filter.kinds.map { $0.rawValue }
                query = query.filter(raws.contains(Column("kind")))
            }
            if !filter.sources.isEmpty {
                let raws = filter.sources.map { $0.rawValue }
                query = query.filter(raws.contains(Column("source")))
            }
            if let since = filter.since {
                query = query.filter(Column("timestamp") >= since)
            }
            if let until = filter.until {
                query = query.filter(Column("timestamp") <= until)
            }
            if let sid = filter.sessionId {
                query = query.filter(Column("sessionId") == sid)
            }
            return try query.order(Column("timestamp").desc).limit(limit).fetchAll(db)
        }
        return try records.map { try decrypt($0) }
    }

    public func verifyIntegrity() throws -> AuditIntegrityReport {
        let events = try database.read { db in
            try AuditEventRecord.order(Column("timestamp").asc).fetchAll(db)
        }
        var prev = chainGenesis
        for event in events {
            if event.prevHash != prev {
                return AuditIntegrityReport(totalEvents: events.count, firstBrokenAt: event.id)
            }
            let canonical = Self.canonicalClear(
                id: event.id, accountId: event.accountId,
                secretId: event.secretId, vaultId: event.vaultId, versionId: event.versionId,
                kind: event.kind, timestamp: event.timestamp, source: event.source,
                success: event.success, deviceId: event.deviceId, sessionId: event.sessionId,
                prevHash: event.prevHash
            )
            let recomputed = computeSelfHash(canonical: canonical, ciphertext: event.payloadCiphertext)
            if recomputed != event.selfHash {
                return AuditIntegrityReport(totalEvents: events.count, firstBrokenAt: event.id)
            }
            prev = event.selfHash
        }
        return AuditIntegrityReport(totalEvents: events.count, firstBrokenAt: nil)
    }

    private func computeSelfHash(canonical: Data, ciphertext: Data) -> Data {
        var input = canonical
        input.append(ciphertext)
        return auditMacKey.withBytes { mb -> Data in
            let key = SymmetricKey(data: Data(mb))
            var hmac = HMAC<SHA256>(key: key)
            hmac.update(data: input)
            return Data(hmac.finalize())
        }
    }

    private static func canonicalClear(
        id: EntityID,
        accountId: Int64,
        secretId: EntityID?,
        vaultId: EntityID?,
        versionId: EntityID?,
        kind: AuditEventKind,
        timestamp: Timestamp,
        source: AuditEventSource,
        success: Bool?,
        deviceId: String?,
        sessionId: String?,
        prevHash: Data
    ) -> Data {
        var d = Data()
        let separator: UInt8 = 0x1F
        d.append(contentsOf: "v1".utf8)
        d.append(separator)
        d.append(contentsOf: id.uuidString.uppercased().utf8)
        d.append(separator)
        var aid = accountId.bigEndian
        Swift.withUnsafeBytes(of: &aid) { d.append(contentsOf: $0) }
        d.append(separator)
        d.append(contentsOf: (secretId?.uuidString.uppercased() ?? "").utf8)
        d.append(separator)
        d.append(contentsOf: (vaultId?.uuidString.uppercased() ?? "").utf8)
        d.append(separator)
        d.append(contentsOf: (versionId?.uuidString.uppercased() ?? "").utf8)
        d.append(separator)
        d.append(contentsOf: kind.rawValue.utf8)
        d.append(separator)
        var ts = timestamp.bigEndian
        Swift.withUnsafeBytes(of: &ts) { d.append(contentsOf: $0) }
        d.append(separator)
        d.append(contentsOf: source.rawValue.utf8)
        d.append(separator)
        d.append(success.map { $0 ? UInt8(0x01) : UInt8(0x00) } ?? 0xff)
        d.append(separator)
        d.append(contentsOf: (deviceId ?? "").utf8)
        d.append(separator)
        d.append(contentsOf: (sessionId ?? "").utf8)
        d.append(separator)
        d.append(prevHash)
        return d
    }

    private static func aadForKeyWrap(eventId: EntityID) -> Data {
        Data(("audit-event-key|" + eventId.uuidString.uppercased()).utf8)
    }

    private static func aadForPayload(eventId: EntityID) -> Data {
        Data(("audit-event-payload|" + eventId.uuidString.uppercased()).utf8)
    }
}
