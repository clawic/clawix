import Foundation
import SecretsModels
import SecretsVault

/// HTTP-backed shims for `SecretsStore`, `AuditStore`, `AgentGrantStore`.
/// Same method names + signatures the SwiftUI Secrets views consume,
/// implementations talk to the bundled ClawJS Secrets over loopback HTTP.
///
/// Sync surface intentional: existing views call these inside `try`
/// blocks without `await`. `runSync` blocks the calling thread on a
/// `DispatchSemaphore`. Acceptable here because the views fire these on
/// user actions, not in hot loops.

// MARK: - Errors

enum ClawJSBackendError: Error, LocalizedError {
    case notUnlocked
    case notFound
    case invalidResponse(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notUnlocked: return "Secrets is locked"
        case .notFound: return "Item not found"
        case .invalidResponse(let detail): return "Invalid secrets response: \(detail)"
        case .server(let message): return message
        }
    }
}

// MARK: - Sync runner

@inline(__always)
fileprivate func runSync<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var captured: Result<T, Error>!
    Task.detached(priority: .userInitiated) {
        let outcome: Result<T, Error>
        do {
            let value = try await operation()
            outcome = .success(value)
        } catch {
            outcome = .failure(error)
        }
        lock.lock()
        captured = outcome
        lock.unlock()
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 5) == .timedOut {
        throw ClawJSBackendError.server("Secrets service did not respond within 5 seconds.")
    }
    lock.lock()
    defer { lock.unlock() }
    return try captured.get()
}

// MARK: - Mappers (HTTP DTO → SecretsModels DTO)

enum ClawJSMapper {
    static func mapFolder(_ row: ClawJSSecretsClient.Folder) -> VaultRecord {
        VaultRecord(
            id: parseId(row.id),
            accountId: 0,
            name: row.name,
            icon: row.icon,
            color: row.color,
            sortOrder: row.sortOrder,
            trashedAt: parseTimestamp(row.trashedAt),
            createdAt: parseTimestamp(row.createdAt) ?? Clock.now(),
            updatedAt: parseTimestamp(row.updatedAt) ?? Clock.now()
        )
    }

    static func mapDescribedSecret(_ s: ClawJSSecretsClient.DescribedSecret) -> SecretRecord {
        let id = parseId(s.id)
        let folderId = s.folderId.flatMap { parseId($0) } ?? UUID()
        let kind: SecretKind = SecretKind(rawValue: s.typeId ?? "generic") ?? .apiKey
        var record = SecretRecord(
            id: id,
            accountId: 0,
            vaultId: folderId,
            kind: kind,
            brandPreset: s.typeId,
            internalName: s.internalName,
            title: s.title,
            wrappedItemKey: Data(),
            currentVersionId: UUID()
        )
        record.isArchived = s.states.isArchived
        record.isCompromised = s.states.isCompromised
        record.isLocked = s.states.isLocked
        record.readOnly = s.states.readOnly
        record.trashedAt = parseTimestamp(s.states.trashedAt)
        record.allowInUrl = s.governance.allowInUrl
        record.allowInBody = s.governance.allowInBody
        record.allowInEnv = s.governance.allowInEnv
        record.allowInsecureTransport = s.governance.allowInsecureTransport
        record.allowLocalNetwork = s.governance.allowLocalNetwork
        record.approvalMode = ApprovalMode(rawValue: s.governance.approvalMode) ?? .auto
        record.approvalWindowMinutes = s.governance.approvalWindowMinutes
        record.ttlExpiresAt = parseTimestamp(s.governance.ttlExpiresAt)
        record.maxUses = s.governance.maxUses
        record.useCount = s.counters.useCount
        record.rotationReminderDays = s.governance.rotationReminderDays
        record.lastRotatedAt = parseTimestamp(s.counters.lastRotatedAt)
        record.lastUsedAt = parseTimestamp(s.counters.lastUsedAt)
        record.redactionLabel = s.governance.redactionLabel
        if let cs = s.governance.clipboardClearSeconds { record.clipboardClearSeconds = cs }
        record.auditRetentionDays = s.governance.auditRetentionDays
        record.allowedHostsJson = encodeJsonArray(s.governance.allowedHosts)
        record.allowedHeadersJson = encodeJsonArray(s.governance.allowedHeaders)
        if let agents = s.governance.allowedAgents { record.allowedAgentsJson = encodeJsonArray(agents) }
        record.tagsJson = encodeJsonArray(s.tags)
        return record
    }

    static func mapField(_ f: ClawJSSecretsClient.DescribedField, secretId: EntityID, versionId: EntityID) -> SecretFieldRecord {
        SecretFieldRecord(
            id: UUID(),
            secretId: secretId,
            versionId: versionId,
            fieldName: f.fieldName,
            fieldKind: FieldKind(rawValue: f.fieldKind) ?? .text,
            placement: FieldPlacement(rawValue: f.placement) ?? .none,
            isSecret: f.isSecret,
            isConcealed: f.isConcealed,
            publicValue: f.publicValue,
            valueCiphertext: nil,
            otpPeriod: f.otpPeriod,
            otpDigits: f.otpDigits,
            otpAlgorithm: f.otpAlgorithm.flatMap { OtpAlgorithm(rawValue: $0) },
            sortOrder: f.sortOrder
        )
    }

    static func mapAuditEvent(_ e: ClawJSSecretsClient.AuditEvent) -> DecryptedAuditEvent {
        let payload = AuditEventPayload(notes: stringify(e.payload))
        return DecryptedAuditEvent(
            id: parseId(e.id),
            secretId: e.secretId.flatMap { parseId($0) },
            vaultId: nil,
            versionId: nil,
            kind: AuditEventKind(rawValue: e.kind) ?? .anomalyDetected,
            timestamp: parseTimestamp(e.timestamp) ?? Clock.now(),
            source: AuditEventSource(rawValue: e.source) ?? .system,
            success: e.success,
            deviceId: nil,
            sessionId: nil,
            payload: payload
        )
    }

    static func mapGrantSummary(_ g: ClawJSSecretsClient.AgentGrantSummary) -> AgentGrantRecord {
        let capabilityKind = (g.capability["kind"]?.value as? String) ?? "custom"
        let capability = AgentCapability(rawValue: capabilityKind) ?? .githubGitPush
        let scopeJson: String? = {
            var scope = g.capability
            scope.removeValue(forKey: "kind")
            guard !scope.isEmpty else { return nil }
            let cleaned = scope.mapValues { $0.value }
            return try? String(data: JSONSerialization.data(withJSONObject: cleaned), encoding: .utf8)
        }()
        return AgentGrantRecord(
            id: parseId(g.id),
            accountId: 0,
            agent: g.agent,
            secretId: parseId(g.secretId),
            capability: capability,
            scopeJson: scopeJson,
            reason: g.reason,
            tokenHash: Data(),
            createdAt: parseTimestamp(g.createdAt) ?? Clock.now(),
            expiresAt: parseTimestamp(g.expiresAt) ?? Clock.now(),
            revokedAt: parseTimestamp(g.revokedAt),
            usedCount: g.usedCount,
            lastUsedAt: parseTimestamp(g.lastUsedAt)
        )
    }

    private static func parseId(_ s: String) -> EntityID {
        UUID(uuidString: s) ?? UUID()
    }

    private static func parseTimestamp(_ s: String?) -> Timestamp? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return Timestamp(d.timeIntervalSince1970 * 1000) }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return Timestamp(d.timeIntervalSince1970 * 1000) }
        return nil
    }

    private static func encodeJsonArray(_ arr: [String]) -> String? {
        guard !arr.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stringify(_ payload: [String: AnyCodable]) -> String {
        let cleaned = payload.mapValues { $0.value }
        guard let data = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}

// MARK: - SecretsStore shim

final class ClawJSSecretsStore {
    private let client: ClawJSSecretsClient

    init(client: ClawJSSecretsClient) {
        self.client = client
    }

    func listVaults(includeTrashed: Bool = false) throws -> [VaultRecord] {
        let containers = try runSync { try await self.client.listContainers(includeTrashed: includeTrashed) }
        return containers.map(ClawJSMapper.mapFolder)
    }

    @discardableResult
    func createVault(name: String, icon: String? = nil, color: String? = nil) throws -> VaultRecord {
        let row = try runSync { try await self.client.createContainer(name: name, icon: icon, color: color) }
        return ClawJSMapper.mapFolder(row)
    }

    func listSecrets(includeTrashed: Bool = false) throws -> [SecretRecord] {
        let described = try runSync {
            try await self.client.listSecrets(
                search: nil,
                folderId: nil,
                includeTrashed: includeTrashed,
                includeArchived: false,
                includePublicValues: true
            )
        }
        return described.map(ClawJSMapper.mapDescribedSecret)
    }

    @discardableResult
    func createSecret(in vault: VaultRecord, draft: DraftSecret) throws -> SecretRecord {
        let payload = ClawJSDraftEncoder.encode(draft, folderId: vault.id.uuidString)
        let described = try runSync { try await self.client.createSecret(draft: payload) }
        return ClawJSMapper.mapDescribedSecret(described)
    }

    func fetchSecret(byInternalName name: String) throws -> SecretRecord? {
        let described = try runSync { try await self.client.describeSecret(name: name, includePublicValues: true) }
        return described.map(ClawJSMapper.mapDescribedSecret)
    }

    func fetchFields(forSecret secretId: EntityID, version: EntityID) throws -> [SecretFieldRecord] {
        guard let secret = try fetchSecretById(secretId) else { return [] }
        let described = try runSync { try await self.client.describeSecret(name: secret.internalName, includePublicValues: true) }
        guard let described else { return [] }
        return described.fields.map { ClawJSMapper.mapField($0, secretId: secretId, versionId: version) }
    }

    func revealField(_ field: SecretFieldRecord, purpose: FieldAccessPurpose = .reveal) throws -> RevealedField {
        guard let secret = try fetchSecretById(field.secretId) else { throw ClawJSBackendError.notFound }
        let purposeString = (purpose == .copy) ? "uiCopy" : "uiReveal"
        let value = try runSync {
            try await self.client.revealField(secretName: secret.internalName, fieldName: field.fieldName, purpose: purposeString)
        }
        return RevealedField(
            name: field.fieldName,
            fieldKind: field.fieldKind,
            placement: field.placement,
            value: value.value,
            otpPeriod: field.otpPeriod,
            otpDigits: field.otpDigits,
            otpAlgorithm: field.otpAlgorithm
        )
    }

    func revealNotes(secret: SecretRecord) throws -> String? {
        guard let described = try runSync({ try await self.client.describeSecret(name: secret.internalName) })
        else { return nil }
        guard described.hasNotes else { return nil }
        let result = try runSync {
            try await self.client.revealField(secretName: secret.internalName, fieldName: "notes", purpose: "uiReveal")
        }
        return result.value
    }

    func trashSecret(id: EntityID) throws {
        guard let secret = try fetchSecretById(id) else { return }
        try runSync { try await self.client.trashSecret(name: secret.internalName) }
    }

    func restoreSecret(id: EntityID) throws {
        guard let secret = try fetchSecretById(id) else { return }
        try runSync { try await self.client.restoreSecret(name: secret.internalName) }
    }

    func setCompromised(id: EntityID, flag: Bool, reason: String? = nil) throws {
        guard let secret = try fetchSecretById(id) else { return }
        try runSync { try await self.client.compromiseSecret(name: secret.internalName, compromised: flag, reason: reason) }
    }

    @discardableResult
    func updateGovernance(secretId: EntityID, to governance: Governance) throws -> SecretRecord {
        guard let secret = try fetchSecretById(secretId) else { throw ClawJSBackendError.notFound }
        let payload = ClawJSGovernanceEncoder.encode(governance)
        let described = try runSync { try await self.client.updateSecret(name: secret.internalName, governance: payload) }
        guard let described else { throw ClawJSBackendError.notFound }
        return ClawJSMapper.mapDescribedSecret(described)
    }

    @discardableResult
    func updatePlainMetadata(
        secretId: EntityID,
        title: String,
        lastUsedAt: Date?,
        values: [String: String?]
    ) throws -> SecretRecord {
        guard let secret = try fetchSecretById(secretId) else { throw ClawJSBackendError.notFound }
        var encodedValues: [String: Any] = [:]
        for (key, value) in values {
            encodedValues[key] = value ?? NSNull()
        }
        var metadata: [String: Any] = [
            "title": title,
            "values": encodedValues
        ]
        if let lastUsedAt {
            metadata["lastUsedAt"] = ISO8601DateFormatter().string(from: lastUsedAt)
        } else {
            metadata["lastUsedAt"] = NSNull()
        }
        let described = try runSync {
            try await self.client.updateSecret(name: secret.internalName, metadata: metadata)
        }
        guard let described else { throw ClawJSBackendError.notFound }
        return ClawJSMapper.mapDescribedSecret(described)
    }

    func purgeTrashed(olderThan: Timestamp) throws -> Int {
        // The HTTP server has no explicit purge endpoint yet; mirroring
        // the legacy behavior we treat this as a no-op and return 0.
        _ = olderThan
        return 0
    }

    func snapshotForBackup() throws -> BackupContents {
        throw ClawJSBackendError.server("Backup export not yet wired to ClawJS Secrets HTTP backend")
    }

    func restoreBackup(_ contents: BackupContents) throws -> (created: Int, skipped: Int) {
        _ = contents
        throw ClawJSBackendError.server("Backup import not yet wired to ClawJS Secrets HTTP backend")
    }

    private func fetchSecretById(_ id: EntityID) throws -> SecretRecord? {
        let all = try listSecrets(includeTrashed: true)
        return all.first { $0.id == id }
    }
}

// MARK: - AuditStore shim

final class ClawJSAuditStore {
    private let client: ClawJSSecretsClient

    init(client: ClawJSSecretsClient) {
        self.client = client
    }

    func append(_ event: NewAuditEvent) throws {
        // Server appends on every state-changing endpoint; client-side
        // append is a no-op. Keep the method to preserve call sites.
        _ = event
    }

    func recentEvents(limit: Int) throws -> [DecryptedAuditEvent] {
        let events = try runSync { try await self.client.queryAudit(limit: limit) }
        return events.map(ClawJSMapper.mapAuditEvent)
    }

    func eventsForSecret(_ secretId: EntityID, limit: Int) throws -> [DecryptedAuditEvent] {
        let events = try runSync { try await self.client.queryAudit(limit: limit) }
        return events
            .filter { $0.secretId == secretId.uuidString }
            .map(ClawJSMapper.mapAuditEvent)
    }

    func filteredEvents(_ filter: AuditEventFilter, limit: Int) throws -> [DecryptedAuditEvent] {
        let kinds = filter.kinds.isEmpty ? nil : filter.kinds.map { $0.rawValue }
        let events = try runSync {
            try await self.client.queryAudit(kinds: kinds, since: nil, limit: limit)
        }
        var mapped = events.map(ClawJSMapper.mapAuditEvent)
        if let secretId = filter.secretId {
            mapped = mapped.filter { $0.secretId == secretId }
        }
        if !filter.sources.isEmpty {
            mapped = mapped.filter { filter.sources.contains($0.source) }
        }
        return mapped
    }

    func verifyIntegrity() throws -> AuditIntegrityReport {
        let report = try runSync { try await self.client.verifyAuditIntegrity() }
        let firstBroken = report.tampered.first.flatMap { UUID(uuidString: $0.eventId) }
        return AuditIntegrityReport(totalEvents: report.totalEvents, firstBrokenAt: firstBroken)
    }
}

// MARK: - Grants shim

final class ClawJSGrantStore {
    private let client: ClawJSSecretsClient

    init(client: ClawJSSecretsClient) {
        self.client = client
    }

    func listActive() throws -> [AgentGrantRecord] {
        let grants = try runSync { try await self.client.listGrants() }
        let now = Clock.now()
        return grants
            .filter { $0.revokedAt == nil }
            .map(ClawJSMapper.mapGrantSummary)
            .filter { $0.expiresAt > now }
    }

    func listAll(limit: Int) throws -> [AgentGrantRecord] {
        let grants = try runSync { try await self.client.listGrants() }
        return Array(grants.map(ClawJSMapper.mapGrantSummary).prefix(limit))
    }

    @discardableResult
    func revoke(grantId: EntityID) throws -> AgentGrantRecord? {
        let revoked = try runSync { try await self.client.revokeGrant(id: grantId.uuidString) }
        return revoked.map(ClawJSMapper.mapGrantSummary)
    }
}

// MARK: - Encoders for outgoing payloads

enum ClawJSDraftEncoder {
    static func encode(_ draft: DraftSecret, folderId: String) -> [String: Any] {
        var fields: [[String: Any]] = []
        for (idx, field) in draft.fields.enumerated() {
            var f: [String: Any] = [
                "fieldName": field.name,
                "fieldKind": field.fieldKind.rawValue,
                "placement": field.placement.rawValue,
                "isSecret": field.isSecret,
                "isConcealed": field.isConcealed,
                "sortOrder": field.sortOrder == 0 ? idx : field.sortOrder,
            ]
            if let v = field.publicValue { f["publicValue"] = v }
            if let v = field.secretValue { f["secretValue"] = v }
            if let v = field.otpPeriod { f["otpPeriod"] = v }
            if let v = field.otpDigits { f["otpDigits"] = v }
            if let v = field.otpAlgorithm { f["otpAlgorithm"] = v.rawValue }
            fields.append(f)
        }
        var payload: [String: Any] = [
            "folderId": folderId,
            "internalName": draft.internalName,
            "title": draft.title,
            "fields": fields,
            "tags": draft.tags,
        ]
        if let preset = draft.brandPreset {
            payload["typeId"] = preset
        } else {
            payload["typeId"] = draft.kind.rawValue
        }
        if let notes = draft.notes {
            payload["notes"] = notes
        }
        return payload
    }
}

enum ClawJSGovernanceEncoder {
    static func encode(_ g: Governance) -> [String: Any] {
        var out: [String: Any] = [
            "allowedHosts": g.allowedHosts,
            "allowedHeaders": g.allowedHeaders,
            "allowInUrl": g.allowInUrl,
            "allowInBody": g.allowInBody,
            "allowInEnv": g.allowInEnv,
            "allowInsecureTransport": g.allowInsecureTransport,
            "allowLocalNetwork": g.allowLocalNetwork,
            "approvalMode": g.approvalMode.rawValue,
            "clipboardClearSeconds": g.clipboardClearSeconds,
        ]
        if let v = g.allowedAgents { out["allowedAgents"] = v }
        if let v = g.approvalWindowMinutes { out["approvalWindowMinutes"] = v }
        if let v = g.ttlExpiresAt { out["ttlExpiresAt"] = formatTimestamp(v) }
        if let v = g.maxUses { out["maxUses"] = v }
        if let v = g.rotationReminderDays { out["rotationReminderDays"] = v }
        if let v = g.redactionLabel { out["redactionLabel"] = v }
        if let v = g.auditRetentionDays { out["auditRetentionDays"] = v }
        return out
    }

    private static func formatTimestamp(_ t: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(t) / 1000)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

// (Legacy types `RevealedField`, `AuditEventFilter`, `AuditIntegrityReport`,
//  `FieldAccessPurpose`, `BackupContents` come from the SecretsVault
//  package; we reuse them so the existing views compile unchanged.)
