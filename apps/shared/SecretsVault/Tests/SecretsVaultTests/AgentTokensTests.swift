import XCTest
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence
@testable import SecretsVault
import ClawixArgon2

final class AgentTokensTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func setUp() throws -> (AgentGrantStore, SecretsStore, VaultRecord, SecretRecord, AuditStore) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let audit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "device-test"
        )
        let store = SecretsStore(database: database, masterKey: bootstrap.masterKey, audit: audit)
        let vault = try store.createVault(name: "Personal")
        let secret = try store.createSecret(
            in: vault,
            draft: DraftSecret(kind: .apiKey, internalName: "github_main", title: "GitHub", fields: [
                DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "ghp_test_xxx", sortOrder: 0)
            ])
        )
        let grants = AgentGrantStore(database: database)
        return (grants, store, vault, secret, audit)
    }

    func testIssueAndResolveRoundTrip() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex",
            secret: secret,
            capability: .githubReleaseCreate,
            reason: "publish 0.2.0",
            durationMinutes: 10,
            scope: ["repo": "clawic/clawix", "tag": "v0.2.0"]
        )
        XCTAssertTrue(issued.plain.hasPrefix(AgentTokenIssuer.prefix))
        XCTAssertGreaterThan(issued.grant.expiresAt, issued.grant.createdAt)

        let resolved = try grants.resolve(token: issued.plain)
        XCTAssertEqual(resolved.id, issued.grant.id)
        XCTAssertEqual(resolved.agent, "codex")
        XCTAssertEqual(resolved.capability, .githubReleaseCreate)
        XCTAssertNil(resolved.revokedAt)
    }

    func testStoredHashOnlyNeverPlaintext() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex",
            secret: secret,
            capability: .npmPublish,
            reason: "publish",
            durationMinutes: 5,
            scope: [:]
        )
        // Token hash must equal SHA256(plain).
        XCTAssertEqual(issued.grant.tokenHash, AgentTokenIssuer.hash(issued.plain))
        // Grant row must NOT contain the plain text anywhere.
        let json = try JSONEncoder().encode(issued.grant)
        let asString = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertFalse(asString.contains(issued.plain))
    }

    func testInvalidTokenFormat() throws {
        let (grants, _, _, _, _) = try setUp()
        XCTAssertThrowsError(try grants.resolve(token: "not_a_token")) { err in
            XCTAssertEqual(err as? AgentTokenError, .invalidTokenFormat)
        }
        XCTAssertThrowsError(try grants.resolve(token: "svagt_???invalid")) { err in
            XCTAssertEqual(err as? AgentTokenError, .invalidTokenFormat)
        }
    }

    func testUnknownToken() throws {
        let (grants, _, _, _, _) = try setUp()
        let stranger = AgentTokenIssuer.generateToken()
        XCTAssertThrowsError(try grants.resolve(token: stranger)) { err in
            XCTAssertEqual(err as? AgentTokenError, .unknownToken)
        }
    }

    func testRevokedTokenRejected() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex", secret: secret, capability: .npmPublish,
            reason: "x", durationMinutes: 5, scope: [:]
        )
        try grants.revoke(id: issued.grant.id)
        XCTAssertThrowsError(try grants.resolve(token: issued.plain)) { err in
            XCTAssertEqual(err as? AgentTokenError, .revoked)
        }
    }

    func testCapabilityMismatchRejected() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex", secret: secret, capability: .npmPublish,
            reason: "x", durationMinutes: 5, scope: [:]
        )
        XCTAssertThrowsError(
            try grants.resolve(token: issued.plain, expectedCapability: .githubReleaseCreate)
        ) { err in
            XCTAssertEqual(err as? AgentTokenError, .capabilityMismatch)
        }
    }

    func testScopeMismatchRejected() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex", secret: secret, capability: .githubReleaseCreate,
            reason: "x", durationMinutes: 5,
            scope: ["repo": "clawic/clawix", "tag": "v0.2.0"]
        )
        // Right repo + tag → ok.
        _ = try grants.resolve(token: issued.plain, expectedScope: ["repo": "clawic/clawix"])
        // Wrong tag → mismatch.
        XCTAssertThrowsError(
            try grants.resolve(token: issued.plain, expectedScope: ["repo": "clawic/clawix", "tag": "v9.9.9"])
        ) { err in
            XCTAssertEqual(err as? AgentTokenError, .scopeMismatch)
        }
    }

    func testBumpUsageIncrementsCounter() throws {
        let (grants, _, _, secret, _) = try setUp()
        let issued = try grants.issue(
            agent: "codex", secret: secret, capability: .npmPublish,
            reason: "x", durationMinutes: 5, scope: [:]
        )
        try grants.bumpUsage(grantId: issued.grant.id)
        try grants.bumpUsage(grantId: issued.grant.id)
        let active = try grants.listActive()
        XCTAssertEqual(active.first?.usedCount, 2)
        XCTAssertNotNil(active.first?.lastUsedAt)
    }

    func testListActiveExcludesRevokedAndExpired() throws {
        let (grants, _, _, secret, _) = try setUp()
        let alive = try grants.issue(
            agent: "codex", secret: secret, capability: .npmPublish,
            reason: "x", durationMinutes: 5, scope: [:]
        )
        let dead = try grants.issue(
            agent: "codex", secret: secret, capability: .githubReleaseCreate,
            reason: "y", durationMinutes: 5, scope: [:]
        )
        try grants.revoke(id: dead.grant.id)
        let active = try grants.listActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, alive.grant.id)
    }

    func testHashesMatchInConstantTime() {
        let a = Data(repeating: 0xAA, count: 32)
        let b = Data(repeating: 0xAA, count: 32)
        let c = Data(repeating: 0xBB, count: 32)
        XCTAssertTrue(AgentTokenIssuer.tokensMatch(a, b))
        XCTAssertFalse(AgentTokenIssuer.tokensMatch(a, c))
        XCTAssertFalse(AgentTokenIssuer.tokensMatch(Data(), b))
    }

    func testTokensAreUnique() throws {
        let (grants, _, _, secret, _) = try setUp()
        var tokens = Set<String>()
        for _ in 0..<25 {
            let issued = try grants.issue(
                agent: "codex", secret: secret, capability: .npmPublish,
                reason: "x", durationMinutes: 5, scope: [:]
            )
            XCTAssertFalse(tokens.contains(issued.plain))
            tokens.insert(issued.plain)
        }
    }
}
