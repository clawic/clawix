import Foundation
import SecretsModels
import SecretsVault

/// Seeds the vault from a JSON fixture when `CLAWIX_SECRETS_FIXTURE` is
/// set. Used by dummy mode to populate hundreds of plausible fake
/// secrets through the same `store.createSecret` path the UI uses, so
/// values get encrypted with the live master key.
///
/// Idempotent: any entry whose `internalName` already exists in the
/// target vault is skipped, so re-launching dummy mode (which wipes
/// the vault dir but not the fixture file) reseeds cleanly.
///
/// Fixture root accepts two shapes (auto-detected):
/// - **Legacy**: a plain array of secret entries.
/// - **Current**: an object `{ "secrets": [...], "globalAuditEvents": [...] }`.
///
/// Each secret entry can describe the full UI surface — governance,
/// timestamps, OTP, grants, audit events. Anything not provided keeps
/// the default the regular `createSecret` path produces.
///
/// All `*DaysAgo` fields are floats so we can place events at fractions
/// of a day (e.g. 0.05 = roughly an hour ago). All `*DaysFromNow`
/// fields are floats too. Backdating only takes effect when the env
/// var `CLAWIX_FIXTURE_SEEDING=1` is set; in production the fixture
/// loader and the underlying seeding hooks are no-ops.
enum SecretsFixtureLoader {
    static func loadIfNeeded(
        store: SecretsStore,
        audit: AuditStore?,
        grants: AgentGrantStore?,
        vaults: [VaultRecord]
    ) {
        guard
            let raw = ProcessInfo.processInfo.environment["CLAWIX_SECRETS_FIXTURE"],
            !raw.isEmpty
        else { return }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return }
        let payload: FixturePayload
        do {
            payload = try Self.decodePayload(from: data)
        } catch {
            FileHandle.standardError.write(Data("clawix: fixture decode failed: \(error)\n".utf8))
            return
        }
        guard let target = vaults.first else { return }

        let existing: Set<String> = (try? Set(store.listSecrets(includeTrashed: true).map { $0.internalName })) ?? []

        var seeded = 0
        var seededAuditEvents = 0
        var seededGrants = 0
        let now = Clock.now()

        for entry in payload.secrets where !existing.contains(entry.internalName) {
            do {
                let secret = try store.createSecret(in: target, draft: entry.toDraft())

                if let governance = entry.governanceStruct(now: now) {
                    _ = try? store.updateGovernance(secretId: secret.id, to: governance)
                }
                if entry.archived == true {
                    _ = try? store.updateTitle(
                        secretId: secret.id,
                        title: secret.title,
                        archived: true
                    )
                }
                if entry.compromised == true {
                    _ = try? store.setCompromised(id: secret.id, flag: true, reason: "fixture seed")
                }
                let trashedAt = entry.trashedDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                let createdAt = entry.createdDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                let lastUsedAt = entry.lastUsedDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                let lastRotatedAt = entry.lastRotatedDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                if createdAt != nil || lastUsedAt != nil || lastRotatedAt != nil ||
                    entry.useCount != nil || trashedAt != nil ||
                    entry.readOnly != nil || entry.locked != nil {
                    try? store._fixtureTouch(
                        secretId: secret.id,
                        createdAt: createdAt,
                        updatedAt: createdAt,
                        lastUsedAt: lastUsedAt,
                        lastRotatedAt: lastRotatedAt,
                        useCount: entry.useCount,
                        trashedAt: trashedAt,
                        readOnly: entry.readOnly,
                        isLocked: entry.locked
                    )
                }

                if let entryGrants = entry.grants {
                    for grantEntry in entryGrants {
                        guard
                            let capability = AgentCapability(rawValue: grantEntry.capability),
                            let grants
                        else { continue }
                        let grantCreatedAt = Self.timestamp(now: now, daysAgo: grantEntry.createdDaysAgo)
                        let expiresAt = Self.timestampInFuture(now: now, daysFromNow: grantEntry.expiresDaysFromNow)
                        let revokedAt = grantEntry.revokedDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                        let lastUsedAt = grantEntry.lastUsedDaysAgo.map { Self.timestamp(now: now, daysAgo: $0) }
                        if let _ = try? grants._fixtureSeedGrant(
                            accountId: secret.accountId,
                            agent: grantEntry.agent,
                            secretId: secret.id,
                            capability: capability,
                            reason: grantEntry.reason ?? "fixture seed",
                            scope: grantEntry.scope ?? [:],
                            createdAt: grantCreatedAt,
                            expiresAt: expiresAt,
                            revokedAt: revokedAt,
                            usedCount: grantEntry.usedCount ?? 0,
                            lastUsedAt: lastUsedAt
                        ) {
                            seededGrants += 1
                        }
                    }
                }

                if let entryEvents = entry.auditEvents, let audit {
                    let resolved = entryEvents
                        .compactMap { e -> ResolvedAudit? in
                            guard let kind = AuditEventKind(rawValue: e.kind),
                                  let source = AuditEventSource(rawValue: e.source ?? "ui")
                            else { return nil }
                            let ts = Self.timestamp(now: now, daysAgo: e.daysAgo)
                            return ResolvedAudit(
                                timestamp: ts,
                                kind: kind,
                                source: source,
                                success: e.success,
                                payload: e.payload(secret: secret),
                                secretId: secret.id,
                                vaultId: secret.vaultId
                            )
                        }
                        .sorted(by: { $0.timestamp < $1.timestamp })
                    for ev in resolved {
                        if let _ = try? audit._fixtureAppendBackdated(
                            NewAuditEvent(
                                kind: ev.kind,
                                source: ev.source,
                                secretId: ev.secretId,
                                vaultId: ev.vaultId,
                                success: ev.success,
                                payload: ev.payload
                            ),
                            timestamp: ev.timestamp,
                            accountId: secret.accountId
                        ) {
                            seededAuditEvents += 1
                        }
                    }
                }

                seeded += 1
            } catch {
                continue
            }
        }

        if let audit, let globalEvents = payload.globalAuditEvents {
            let resolved = globalEvents
                .compactMap { e -> ResolvedAudit? in
                    guard let kind = AuditEventKind(rawValue: e.kind),
                          let source = AuditEventSource(rawValue: e.source ?? "system")
                    else { return nil }
                    let ts = Self.timestamp(now: now, daysAgo: e.daysAgo)
                    return ResolvedAudit(
                        timestamp: ts,
                        kind: kind,
                        source: source,
                        success: e.success,
                        payload: e.payload(secret: nil),
                        secretId: nil,
                        vaultId: target.id
                    )
                }
                .sorted(by: { $0.timestamp < $1.timestamp })
            for ev in resolved {
                if let _ = try? audit._fixtureAppendBackdated(
                    NewAuditEvent(
                        kind: ev.kind,
                        source: ev.source,
                        secretId: ev.secretId,
                        vaultId: ev.vaultId,
                        success: ev.success,
                        payload: ev.payload
                    ),
                    timestamp: ev.timestamp
                ) {
                    seededAuditEvents += 1
                }
            }
        }

        if seeded > 0 {
            FileHandle.standardError.write(Data(
                "clawix: seeded \(seeded) fixture secret(s), \(seededGrants) grant(s), \(seededAuditEvents) audit event(s) from \(url.path)\n".utf8
            ))
        }
    }

    // MARK: - Decoding helpers

    private static func decodePayload(from data: Data) throws -> FixturePayload {
        let decoder = JSONDecoder()
        if let object = try? decoder.decode(FixturePayload.self, from: data),
           !object.secrets.isEmpty {
            return object
        }
        let array = try decoder.decode([Entry].self, from: data)
        return FixturePayload(secrets: array, globalAuditEvents: nil)
    }

    private static func timestamp(now: Timestamp, daysAgo: Double) -> Timestamp {
        let millis = Int64(daysAgo * 24 * 60 * 60 * 1000)
        return now - millis
    }

    private static func timestampInFuture(now: Timestamp, daysFromNow: Double) -> Timestamp {
        let millis = Int64(daysFromNow * 24 * 60 * 60 * 1000)
        return now + millis
    }
}

// MARK: - JSON shapes

private struct FixturePayload: Decodable {
    let secrets: [Entry]
    let globalAuditEvents: [AuditEntry]?
}

private struct Entry: Decodable {
    let kind: String
    let internalName: String
    let title: String
    let brandPreset: String?
    let tags: [String]?
    let notes: String?
    let archived: Bool?
    let compromised: Bool?
    let trashedDaysAgo: Double?
    let readOnly: Bool?
    let locked: Bool?
    let createdDaysAgo: Double?
    let lastUsedDaysAgo: Double?
    let lastRotatedDaysAgo: Double?
    let useCount: Int?
    let governance: GovernanceEntry?
    let fields: [Field]?
    let grants: [GrantEntry]?
    let auditEvents: [AuditEntry]?

    func toDraft() -> DraftSecret {
        let resolvedKind = SecretKind(rawValue: kind) ?? .secureNote
        let draftFields = (fields ?? []).enumerated().map { idx, f -> DraftField in
            DraftField(
                name: f.name,
                fieldKind: FieldKind(rawValue: f.fieldKind ?? "password") ?? .password,
                placement: FieldPlacement(rawValue: f.placement ?? "none") ?? .none,
                isSecret: f.isSecret ?? true,
                isConcealed: f.isConcealed ?? true,
                publicValue: f.publicValue,
                secretValue: f.secretValue,
                otpPeriod: f.otpPeriod,
                otpDigits: f.otpDigits,
                otpAlgorithm: f.otpAlgorithm.flatMap { OtpAlgorithm(rawValue: $0) },
                sortOrder: idx
            )
        }
        return DraftSecret(
            kind: resolvedKind,
            brandPreset: brandPreset,
            internalName: internalName,
            title: title,
            fields: draftFields,
            notes: notes,
            tags: tags ?? []
        )
    }

    func governanceStruct(now: Timestamp) -> Governance? {
        guard let g = governance else { return nil }
        let approval = g.approvalMode.flatMap { ApprovalMode(rawValue: $0) } ?? .auto
        let ttl = g.ttlDaysFromNow.map { delta -> Timestamp in
            let millis = Int64(delta * 24 * 60 * 60 * 1000)
            return now + millis
        }
        return Governance(
            allowedHosts: g.allowedHosts ?? [],
            allowedHeaders: g.allowedHeaders ?? ["Authorization"],
            allowInUrl: g.allowInUrl ?? false,
            allowInBody: g.allowInBody ?? false,
            allowInEnv: g.allowInEnv ?? true,
            allowInsecureTransport: g.allowInsecureTransport ?? false,
            allowLocalNetwork: g.allowLocalNetwork ?? false,
            allowedAgents: g.allowedAgents,
            approvalMode: approval,
            approvalWindowMinutes: g.approvalWindowMinutes,
            ttlExpiresAt: ttl,
            maxUses: g.maxUses,
            rotationReminderDays: g.rotationReminderDays,
            redactionLabel: g.redactionLabel,
            clipboardClearSeconds: g.clipboardClearSeconds ?? 30,
            auditRetentionDays: g.auditRetentionDays
        )
    }
}

private struct Field: Decodable {
    let name: String
    let fieldKind: String?
    let placement: String?
    let isSecret: Bool?
    let isConcealed: Bool?
    let publicValue: String?
    let secretValue: String?
    let otpPeriod: Int?
    let otpDigits: Int?
    let otpAlgorithm: String?
}

private struct GovernanceEntry: Decodable {
    let allowedHosts: [String]?
    let allowedHeaders: [String]?
    let allowInUrl: Bool?
    let allowInBody: Bool?
    let allowInEnv: Bool?
    let allowInsecureTransport: Bool?
    let allowLocalNetwork: Bool?
    let allowedAgents: [String]?
    let approvalMode: String?
    let approvalWindowMinutes: Int?
    let ttlDaysFromNow: Double?
    let maxUses: Int?
    let rotationReminderDays: Int?
    let redactionLabel: String?
    let clipboardClearSeconds: Int?
    let auditRetentionDays: Int?
}

private struct GrantEntry: Decodable {
    let agent: String
    let capability: String
    let reason: String?
    let scope: [String: String]?
    let createdDaysAgo: Double
    let expiresDaysFromNow: Double
    let revokedDaysAgo: Double?
    let usedCount: Int?
    let lastUsedDaysAgo: Double?
}

private struct AuditEntry: Decodable {
    let kind: String
    let source: String?
    let daysAgo: Double
    let success: Bool?
    let host: String?
    let agentName: String?
    let httpMethod: String?
    let requestId: String?
    let latencyMs: Int?
    let responseSize: Int?
    let errorCode: String?
    let userLabel: String?
    let notes: String?

    func payload(secret: SecretRecord?) -> AuditEventPayload {
        AuditEventPayload(
            agentName: agentName,
            host: host,
            httpMethod: httpMethod,
            requestId: requestId,
            responseSize: responseSize,
            latencyMs: latencyMs,
            errorCode: errorCode,
            notes: notes,
            secretInternalNameFrozen: secret?.internalName,
            secretKindFrozen: secret?.kind,
            userLabel: userLabel
        )
    }
}

private struct ResolvedAudit {
    let timestamp: Timestamp
    let kind: AuditEventKind
    let source: AuditEventSource
    let success: Bool?
    let payload: AuditEventPayload
    let secretId: EntityID?
    let vaultId: EntityID?
}
