import Foundation
import SecretsCrypto
import SecretsModels
import SecretsPersistence
import SecretsProxyCore

/// High-level proxy operations. Bridges raw `ProxyRequest` -> `ProxyResponse`
/// using the underlying `SecretsStore` and `AuditStore`. The redaction
/// labels and sensitive value list returned by `resolve` are everything the
/// caller (the helper binary) needs to mask its output before printing.
public final class ProxyResolver {

    public let store: SecretsStore
    public let audit: AuditStore?
    public let grants: AgentGrantStore?

    public init(store: SecretsStore, audit: AuditStore? = nil, grants: AgentGrantStore? = nil) {
        self.store = store
        self.audit = audit
        self.grants = grants
    }

    public enum ResolveError: Swift.Error, Equatable, CustomStringConvertible {
        case unknownSecret(String)
        case secretLocked(String)
        case secretCompromised(String)
        case readOnly(String)
        case hostNotAllowed(String, [String])
        case headerNotAllowed(String, [String])
        case placementNotAllowed(String)
        case insecureTransportNotAllowed
        case localNetworkNotAllowed
        case unknownField(String, String)
        case fieldHasNoValue(String, String)

        public var description: String {
            switch self {
            case .unknownSecret(let n): return "Secret not found: \(n)"
            case .secretLocked(let n): return "Secret '\(n)' is administratively locked"
            case .secretCompromised(let n): return "Secret '\(n)' is marked as compromised"
            case .readOnly(let n): return "Secret '\(n)' is read-only; this request is rejected"
            case .hostNotAllowed(let host, let allowed):
                return "Host '\(host)' is not in the allowlist for this secret. Allowed: \(allowed.joined(separator: ", "))"
            case .headerNotAllowed(let header, let allowed):
                return "Header '\(header)' is not in the allowlist for this secret. Allowed: \(allowed.joined(separator: ", "))"
            case .placementNotAllowed(let placement): return "Placement '\(placement)' is not allowed for this secret"
            case .insecureTransportNotAllowed: return "Plaintext http:// is not allowed for this secret"
            case .localNetworkNotAllowed: return "Local-network targets are not allowed for this secret"
            case .unknownField(let secret, let field): return "Field '\(field)' not found on secret '\(secret)'"
            case .fieldHasNoValue(let secret, let field): return "Field '\(field)' on secret '\(secret)' has no stored value"
            }
        }
    }

    public struct ResolutionOutput: Sendable {
        public var values: [String: String]              // keyed by raw token
        public var sensitiveValues: [String]
        public var redactionLabels: [String: String]     // raw token -> redaction label
        public var resolvedSecretInternalNames: [String]
    }

    // MARK: list-secrets

    public func handleListSecrets(search: String?, vaultName: String?, kindRaw: String?) throws -> [DescribedSecret] {
        let vaults = try store.listVaults(includeTrashed: false)
        let vaultsById = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        var secrets = try store.listSecrets()
        if let search, !search.isEmpty {
            let lower = search.lowercased()
            secrets = secrets.filter {
                $0.internalName.lowercased().contains(lower) ||
                $0.title.lowercased().contains(lower)
            }
        }
        if let vaultName {
            let target = vaults.first { $0.name == vaultName }
            secrets = secrets.filter { $0.vaultId == target?.id }
        }
        if let kindRaw, let kind = SecretKind(rawValue: kindRaw) {
            secrets = secrets.filter { $0.kind == kind }
        }
        return try secrets.map { try describe($0, vaults: vaultsById, includeFields: false) }
    }

    // MARK: describe-secret

    public func handleDescribeSecret(name: String) throws -> DescribedSecret {
        guard let secret = try store.fetchSecret(byInternalName: name) else {
            throw ResolveError.unknownSecret(name)
        }
        let vaults = try store.listVaults(includeTrashed: true)
        let vaultsById = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        return try describe(secret, vaults: vaultsById, includeFields: true)
    }

    private func describe(
        _ secret: SecretRecord,
        vaults: [EntityID: VaultRecord],
        includeFields: Bool
    ) throws -> DescribedSecret {
        let governance = secret.governance
        var fields: [DescribedField] = []
        if includeFields {
            let raw = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
            fields = raw.map {
                DescribedField(
                    name: $0.fieldName,
                    fieldKind: $0.fieldKind.rawValue,
                    placement: $0.placement.rawValue,
                    isSecret: $0.isSecret
                )
            }
        }
        return DescribedSecret(
            internalName: secret.internalName,
            title: secret.title,
            kind: secret.kind.rawValue,
            brandPreset: secret.brandPreset,
            vaultName: vaults[secret.vaultId]?.name ?? "",
            allowedHosts: governance.allowedHosts,
            allowedHeaders: governance.allowedHeaders,
            allowInUrl: governance.allowInUrl,
            allowInBody: governance.allowInBody,
            allowInEnv: governance.allowInEnv,
            readOnly: secret.readOnly,
            isCompromised: secret.isCompromised,
            isLocked: secret.isLocked,
            fields: fields,
            notes: nil,
            lastUsedAt: secret.lastUsedAt,
            useCount: secret.useCount
        )
    }

    // MARK: resolve

    public func handleResolve(placeholders: [PlaceholderToken], context: ResolveContext) throws -> ResolutionOutput {
        var values: [String: String] = [:]
        var sensitiveValues: [String] = []
        var labels: [String: String] = [:]
        var resolved: [String] = []

        for token in placeholders {
            guard let secret = try store.fetchSecret(byInternalName: token.secretInternalName) else {
                throw ResolveError.unknownSecret(token.secretInternalName)
            }
            try validate(secret: secret, context: context)
            let fieldRecord = try locateField(token: token, secret: secret)
            guard let value = try store.decryptFieldSilently(fieldRecord) else {
                throw ResolveError.fieldHasNoValue(token.secretInternalName, fieldRecord.fieldName)
            }
            values[token.raw] = value
            if fieldRecord.isSecret {
                sensitiveValues.append(value)
            }
            let label = Redactor.label(
                forSecretInternalName: token.secretInternalName,
                customLabel: secret.governance.redactionLabel
            )
            labels[token.raw] = label
            try store.bumpUseCount(id: secret.id)
            if !resolved.contains(secret.internalName) {
                resolved.append(secret.internalName)
            }
        }

        return ResolutionOutput(
            values: values,
            sensitiveValues: sensitiveValues,
            redactionLabels: labels,
            resolvedSecretInternalNames: resolved
        )
    }

    private func locateField(token: PlaceholderToken, secret: SecretRecord) throws -> SecretFieldRecord {
        let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
        if let explicit = token.fieldName {
            guard let match = fields.first(where: { $0.fieldName == explicit }) else {
                throw ResolveError.unknownField(secret.internalName, explicit)
            }
            return match
        }
        // No explicit field: prefer the first secret-typed field, else the first one.
        if let primary = fields.first(where: { $0.isSecret }) {
            return primary
        }
        guard let any = fields.first else {
            throw ResolveError.unknownField(secret.internalName, "(primary)")
        }
        return any
    }

    private func validate(secret: SecretRecord, context: ResolveContext) throws {
        let name = secret.internalName
        if secret.isLocked { throw ResolveError.secretLocked(name) }
        if secret.isCompromised { throw ResolveError.secretCompromised(name) }

        let governance = secret.governance

        // Host check.
        if let host = context.host, !governance.allowedHosts.isEmpty {
            if !ProxyResolver.hostMatches(host, allowList: governance.allowedHosts) {
                throw ResolveError.hostNotAllowed(host, governance.allowedHosts)
            }
        }
        // Headers check (only enforce if the call is going through a header).
        if !context.headerNames.isEmpty, !governance.allowedHeaders.isEmpty {
            for header in context.headerNames where !governance.allowedHeaders.contains(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) {
                throw ResolveError.headerNotAllowed(header, governance.allowedHeaders)
            }
        }
        // Placement gates.
        if context.inUrl, !governance.allowInUrl { throw ResolveError.placementNotAllowed("url") }
        if context.inBody, !governance.allowInBody { throw ResolveError.placementNotAllowed("body") }
        if context.inEnv, !governance.allowInEnv { throw ResolveError.placementNotAllowed("env") }
        // Transport / network gates.
        if context.insecureTransport, !governance.allowInsecureTransport { throw ResolveError.insecureTransportNotAllowed }
        if context.localNetwork, !governance.allowLocalNetwork { throw ResolveError.localNetworkNotAllowed }
    }

    public static func hostMatches(_ host: String, allowList: [String]) -> Bool {
        let lower = host.lowercased()
        for entry in allowList {
            let pat = entry.lowercased()
            if pat.hasPrefix("*.") {
                let suffix = String(pat.dropFirst(1))
                if lower.hasSuffix(suffix) { return true }
            } else if pat == lower {
                return true
            }
        }
        return false
    }

    // MARK: activation / grants

    public struct PendingActivation: Sendable {
        public let request: ActivationRequest
        public let secretId: EntityID
        public let secretInternalName: String
    }

    public enum ActivationOutcome: Sendable {
        case approved
        case denied(reason: String?)
    }

    public struct IssuedActivation: Sendable {
        public let plain: String
        public let grant: AgentGrantRecord
    }

    public func prepareActivation(_ request: ActivationRequest) throws -> (PendingActivation, AgentCapability) {
        guard let cap = AgentCapability(rawValue: request.capability) else {
            throw ResolveError.unknownSecret(request.capability)
        }
        guard let secret = try store.fetchSecret(byInternalName: request.secretInternalName) else {
            throw ResolveError.unknownSecret(request.secretInternalName)
        }
        let pending = PendingActivation(
            request: request,
            secretId: secret.id,
            secretInternalName: secret.internalName
        )
        return (pending, cap)
    }

    public func issueAfterApproval(
        request: ActivationRequest,
        capability: AgentCapability,
        sessionId: String?
    ) throws -> IssuedActivation {
        guard let store = grants else {
            throw NSError(
                domain: "ProxyResolver",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "agent grant store not configured"]
            )
        }
        guard let secret = try self.store.fetchSecret(byInternalName: request.secretInternalName) else {
            throw ResolveError.unknownSecret(request.secretInternalName)
        }
        let issued = try store.issue(
            agent: request.agent,
            secret: secret,
            capability: capability,
            reason: request.reason,
            durationMinutes: request.durationMinutes,
            scope: request.scope
        )
        try audit?.append(NewAuditEvent(
            kind: .grantIssued,
            source: .system,
            secretId: secret.id,
            vaultId: secret.vaultId,
            success: true,
            sessionId: sessionId,
            payload: AuditEventPayload(
                agentName: request.agent,
                capability: capability,
                agentGrantId: issued.grant.id,
                notes: "Granted '\(capability.rawValue)' for \(request.durationMinutes) min · reason: \(request.reason)",
                secretInternalNameFrozen: secret.internalName,
                secretKindFrozen: secret.kind
            )
        ))
        return IssuedActivation(plain: issued.plain, grant: issued.grant)
    }

    public func recordActivationDenied(
        request: ActivationRequest,
        reason: String?,
        sessionId: String?
    ) throws {
        let secret = try store.fetchSecret(byInternalName: request.secretInternalName)
        try audit?.append(NewAuditEvent(
            kind: .grantRevoked,
            source: .ui,
            secretId: secret?.id,
            vaultId: secret?.vaultId,
            success: false,
            sessionId: sessionId,
            payload: AuditEventPayload(
                agentName: request.agent,
                capability: AgentCapability(rawValue: request.capability),
                notes: "Activation request denied" + (reason.map { ": \($0)" } ?? ""),
                secretInternalNameFrozen: secret?.internalName ?? request.secretInternalName,
                secretKindFrozen: secret?.kind
            )
        ))
    }

    public func validateAndConsumeAgentToken(
        _ token: String,
        secretInternalName: String? = nil,
        sessionId: String? = nil
    ) throws -> AgentGrantRecord {
        guard let grants else { throw AgentTokenError.unknownToken }
        let resolved: AgentGrantRecord
        do {
            resolved = try grants.resolve(token: token)
        } catch let err as AgentTokenError {
            try? auditFailedTokenUse(error: err, sessionId: sessionId)
            throw err
        }
        if let expected = secretInternalName,
           let secret = try store.fetchSecret(id: resolved.secretId),
           secret.internalName != expected {
            try? auditFailedTokenUse(error: .scopeMismatch, sessionId: sessionId)
            throw AgentTokenError.scopeMismatch
        }
        try grants.bumpUsage(grantId: resolved.id)
        try audit?.append(NewAuditEvent(
            kind: .grantUsed,
            source: .proxy,
            secretId: resolved.secretId,
            vaultId: nil,
            success: true,
            sessionId: sessionId,
            payload: AuditEventPayload(
                agentName: resolved.agent,
                capability: resolved.capability,
                agentGrantId: resolved.id,
                notes: "Token consumed for '\(resolved.capability.rawValue)'"
            )
        ))
        return resolved
    }

    public func revokeGrant(id: EntityID, sessionId: String? = nil) throws -> AgentGrantRecord? {
        guard let grants else { throw AgentTokenError.unknownToken }
        guard let revoked = try grants.revoke(id: id) else { return nil }
        try audit?.append(NewAuditEvent(
            kind: .grantRevoked,
            source: .ui,
            secretId: revoked.secretId,
            vaultId: nil,
            success: true,
            sessionId: sessionId,
            payload: AuditEventPayload(
                agentName: revoked.agent,
                capability: revoked.capability,
                agentGrantId: revoked.id,
                notes: "Grant manually revoked"
            )
        ))
        return revoked
    }

    public func handleListGrants() throws -> [DescribedGrant] {
        guard let grants else { return [] }
        let active = try grants.listAll(limit: 200)
        return try active.map { try describe(grant: $0) }
    }

    private func describe(grant: AgentGrantRecord) throws -> DescribedGrant {
        let secret = try store.fetchSecret(id: grant.secretId)
        let scope = grants?.decodeScope(grant.scopeJson) ?? [:]
        return DescribedGrant(
            grantId: grant.id.uuidString.uppercased(),
            agent: grant.agent,
            capability: grant.capability.rawValue,
            secretInternalName: secret?.internalName ?? "(deleted)",
            reason: grant.reason,
            createdAt: grant.createdAt,
            expiresAt: grant.expiresAt,
            revokedAt: grant.revokedAt,
            usedCount: grant.usedCount,
            lastUsedAt: grant.lastUsedAt,
            scope: scope
        )
    }

    public func sweepAndAuditExpiredGrants() throws -> Int {
        guard let grants else { return 0 }
        let expired = try grants.sweepExpired()
        for grant in expired {
            try audit?.append(NewAuditEvent(
                kind: .grantExpired,
                source: .system,
                secretId: grant.secretId,
                vaultId: nil,
                success: true,
                payload: AuditEventPayload(
                    agentName: grant.agent,
                    capability: grant.capability,
                    agentGrantId: grant.id,
                    notes: "Grant expired"
                )
            ))
        }
        return expired.count
    }

    private func auditFailedTokenUse(error: AgentTokenError, sessionId: String?) throws {
        try audit?.append(NewAuditEvent(
            kind: .grantExpired,
            source: .proxy,
            success: false,
            sessionId: sessionId,
            payload: AuditEventPayload(
                notes: "Token rejected: \(error)"
            )
        ))
    }

    // MARK: audit

    public func recordAuditCall(_ call: ProxyAuditCallSummary, secretInternalNames: [String]) throws {
        guard let audit else { return }
        let resolvedKind = AuditEventKind(rawValue: call.kind) ?? .proxyRequest
        let primarySecret = try secretInternalNames.first.flatMap { name -> SecretRecord? in
            try store.fetchSecret(byInternalName: name)
        }
        let payload = AuditEventPayload(
            agentName: nil,
            host: call.host,
            httpMethod: call.method,
            redactedRequest: call.redactedRequest,
            responseSize: call.responseSize,
            latencyMs: call.latencyMs,
            errorCode: call.errorCode,
            notes: secretInternalNames.isEmpty
                ? nil
                : "Resolved: \(secretInternalNames.joined(separator: ", "))",
            secretInternalNameFrozen: primarySecret?.internalName,
            secretKindFrozen: primarySecret?.kind
        )
        try audit.append(NewAuditEvent(
            kind: resolvedKind,
            source: .proxy,
            secretId: primarySecret?.id,
            vaultId: primarySecret?.vaultId,
            success: call.success,
            sessionId: call.sessionId,
            payload: payload
        ))
    }

    // MARK: doctor

    public func handleDoctor(symlinkPresent: Bool, helperPath: String?) throws -> DoctorReport {
        let totalSecrets = try store.listSecrets(includeTrashed: false).count
        let chainReport = try audit?.verifyIntegrity()
        return DoctorReport(
            vaultExists: true,
            vaultLocked: false,
            totalSecrets: totalSecrets,
            totalAuditEvents: chainReport?.totalEvents,
            auditChainIntact: chainReport?.isIntact,
            symlinkInstalled: symlinkPresent,
            deviceId: audit?.deviceId,
            helperPath: helperPath
        )
    }
}
