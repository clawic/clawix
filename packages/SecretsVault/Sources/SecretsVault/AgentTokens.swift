import Foundation
import CryptoKit
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence

public enum AgentTokenError: Swift.Error, Equatable, CustomStringConvertible {
    case invalidTokenFormat
    case unknownToken
    case revoked
    case expired
    case capabilityMismatch
    case scopeMismatch

    public var description: String {
        switch self {
        case .invalidTokenFormat: return "Agent token format is invalid"
        case .unknownToken: return "Agent token not recognized"
        case .revoked: return "Agent token was revoked"
        case .expired: return "Agent token has expired"
        case .capabilityMismatch: return "Agent token does not cover the requested capability"
        case .scopeMismatch: return "Agent token scope does not cover this request"
        }
    }
}

public struct IssuedAgentToken: Sendable, Hashable {
    public let plain: String          // returned to the caller ONCE
    public let grant: AgentGrantRecord

    public init(plain: String, grant: AgentGrantRecord) {
        self.plain = plain
        self.grant = grant
    }
}

/// Generates and verifies the `svagt_` token strings handed to agents on
/// activation approval. The plain token is returned exactly once to the
/// approver (and printed by the helper); only the SHA-256 hash is stored.
public enum AgentTokenIssuer {

    public static let prefix = "svagt_"
    public static let entropyByteCount = 32

    public static func generateToken() -> String {
        let bytes = SecureRandom.bytes(entropyByteCount)
        let suffix = base64URL(bytes)
        return prefix + suffix
    }

    public static func hash(_ token: String) -> Data {
        let digest = SHA256.hash(data: Data(token.utf8))
        return Data(digest)
    }

    public static func validate(format token: String) -> Bool {
        guard token.hasPrefix(prefix) else { return false }
        let suffix = token.dropFirst(prefix.count)
        guard !suffix.isEmpty else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return suffix.allSatisfy { allowed.contains($0) }
    }

    public static func tokensMatch(_ candidateHash: Data, _ storedHash: Data) -> Bool {
        guard candidateHash.count == storedHash.count, !candidateHash.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<candidateHash.count {
            diff |= candidateHash[candidateHash.startIndex + i] ^ storedHash[storedHash.startIndex + i]
        }
        return diff == 0
    }

    private static func base64URL(_ data: Data) -> String {
        let raw = data.base64EncodedString()
        return raw
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct ActivationRequestSummary: Sendable, Hashable, Codable {
    public var agent: String
    public var secretInternalName: String
    public var capability: String
    public var reason: String
    public var durationMinutes: Int
    public var scope: [String: String]

    public init(agent: String, secretInternalName: String, capability: String, reason: String, durationMinutes: Int, scope: [String: String]) {
        self.agent = agent
        self.secretInternalName = secretInternalName
        self.capability = capability
        self.reason = reason
        self.durationMinutes = durationMinutes
        self.scope = scope
    }
}

public final class AgentGrantStore {

    public let database: SecretsDatabase

    public init(database: SecretsDatabase) {
        self.database = database
    }

    @discardableResult
    public func issue(
        agent: String,
        secret: SecretRecord,
        capability: AgentCapability,
        reason: String,
        durationMinutes: Int,
        scope: [String: String]
    ) throws -> IssuedAgentToken {
        precondition(durationMinutes >= 1 && durationMinutes <= 60, "agent grant duration must be 1..60 minutes")
        let plain = AgentTokenIssuer.generateToken()
        let hash = AgentTokenIssuer.hash(plain)
        let scopeData = try? JSONEncoder().encode(scope)
        let scopeJson = scopeData.flatMap { String(data: $0, encoding: .utf8) }
        let now = Clock.now()
        let expiresAt = now + Int64(durationMinutes) * 60 * 1000
        var grant = AgentGrantRecord(
            id: EntityID.newID(),
            accountId: secret.accountId,
            agent: agent,
            secretId: secret.id,
            capability: capability,
            scopeJson: scopeJson,
            reason: reason,
            tokenHash: hash,
            createdAt: now,
            expiresAt: expiresAt,
            revokedAt: nil,
            usedCount: 0,
            lastUsedAt: nil
        )
        try database.write { db in try grant.insert(db) }
        return IssuedAgentToken(plain: plain, grant: grant)
    }

    public func resolve(token: String, expectedCapability: AgentCapability? = nil, expectedScope: [String: String] = [:]) throws -> AgentGrantRecord {
        guard AgentTokenIssuer.validate(format: token) else {
            throw AgentTokenError.invalidTokenFormat
        }
        let hash = AgentTokenIssuer.hash(token)
        guard let grant = try fetchByHash(hash) else {
            throw AgentTokenError.unknownToken
        }
        if grant.revokedAt != nil { throw AgentTokenError.revoked }
        if grant.expiresAt <= Clock.now() { throw AgentTokenError.expired }
        if let expectedCapability, grant.capability != expectedCapability {
            throw AgentTokenError.capabilityMismatch
        }
        if !expectedScope.isEmpty {
            let stored = decodeScope(grant.scopeJson)
            for (k, v) in expectedScope {
                guard let candidate = stored[k] else { throw AgentTokenError.scopeMismatch }
                if candidate != v { throw AgentTokenError.scopeMismatch }
            }
        }
        return grant
    }

    public func bumpUsage(grantId: EntityID) throws {
        try database.write { db in
            guard var grant = try AgentGrantRecord.fetchOne(db, key: grantId.uuidString.uppercased()) else {
                return
            }
            grant.usedCount += 1
            grant.lastUsedAt = Clock.now()
            try grant.update(db)
        }
    }

    @discardableResult
    public func revoke(id: EntityID) throws -> AgentGrantRecord? {
        try database.write { db -> AgentGrantRecord? in
            guard var grant = try AgentGrantRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                return nil
            }
            if grant.revokedAt == nil {
                grant.revokedAt = Clock.now()
                try grant.update(db)
            }
            return grant
        }
    }

    public func listActive() throws -> [AgentGrantRecord] {
        try database.read { db in
            try AgentGrantRecord
                .filter(Column("revokedAt") == nil)
                .filter(Column("expiresAt") > Clock.now())
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func listAll(limit: Int = 100) throws -> [AgentGrantRecord] {
        try database.read { db in
            try AgentGrantRecord
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func sweepExpired() throws -> [AgentGrantRecord] {
        let now = Clock.now()
        return try database.read { db in
            try AgentGrantRecord
                .filter(Column("revokedAt") == nil)
                .filter(Column("expiresAt") <= now)
                .fetchAll(db)
        }
    }

    private func fetchByHash(_ hash: Data) throws -> AgentGrantRecord? {
        try database.read { db in
            try AgentGrantRecord
                .filter(Column("tokenHash") == hash)
                .fetchOne(db)
        }
    }

    public func decodeScope(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    // MARK: Fixture seeding (DEV ONLY)
    //
    // Creates a grant record with explicit timestamps so dummy-mode
    // fixtures can paint the Grants tab with a mix of ACTIVE / EXPIRED /
    // REVOKED entries spread over time. Gated by `CLAWIX_FIXTURE_SEEDING=1`;
    // no-op in production. The synthesized `tokenHash` is random (the seed
    // never needs to resolve a real token), and the duration precondition
    // of `issue()` is intentionally bypassed because seeded grants model
    // historical grants whose original duration is irrelevant.
    @discardableResult
    public func _fixtureSeedGrant(
        accountId: Int64 = 0,
        agent: String,
        secretId: EntityID,
        capability: AgentCapability,
        reason: String,
        scope: [String: String],
        createdAt: Timestamp,
        expiresAt: Timestamp,
        revokedAt: Timestamp? = nil,
        usedCount: Int = 0,
        lastUsedAt: Timestamp? = nil
    ) throws -> AgentGrantRecord? {
        guard ProcessInfo.processInfo.environment[SecretsVaultEnv.fixtureSeeding] == "1" else { return nil }
        let scopeData = try? JSONEncoder().encode(scope)
        let scopeJson = scopeData.flatMap { String(data: $0, encoding: .utf8) }
        let tokenHash = AgentTokenIssuer.hash(AgentTokenIssuer.generateToken())
        var grant = AgentGrantRecord(
            id: EntityID.newID(),
            accountId: accountId,
            agent: agent,
            secretId: secretId,
            capability: capability,
            scopeJson: scopeJson,
            reason: reason,
            tokenHash: tokenHash,
            createdAt: createdAt,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            usedCount: usedCount,
            lastUsedAt: lastUsedAt
        )
        try database.write { db in try grant.insert(db) }
        return grant
    }
}
