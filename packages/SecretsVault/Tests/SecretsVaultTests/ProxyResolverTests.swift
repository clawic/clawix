import XCTest
import SecretsCrypto
import SecretsModels
import SecretsPersistence
import SecretsProxyCore
@testable import SecretsVault
import ClawixArgon2

final class ProxyResolverTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func setUp() throws -> (ProxyResolver, SecretsStore, AuditStore, VaultRecord) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let audit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "test-device"
        )
        let store = SecretsStore(database: database, masterKey: bootstrap.masterKey, audit: audit)
        let vault = try store.createVault(name: "Personal")
        let resolver = ProxyResolver(store: store, audit: audit)
        return (resolver, store, audit, vault)
    }

    private func openAISecret(in store: SecretsStore, vault: VaultRecord) throws -> SecretRecord {
        var draft = DraftSecret(
            kind: .apiKey,
            internalName: "service_main",
            title: "Service · main",
            fields: [
                DraftField(name: "header", fieldKind: .text, placement: .header, isSecret: false, publicValue: "Authorization", sortOrder: 0),
                DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-deadbeef-1234", sortOrder: 1)
            ]
        )
        draft.tags = []
        var secret = try store.createSecret(in: vault, draft: draft)
        var governance = secret.governance
        governance.allowedHosts = ["api.example.com"]
        governance.allowedHeaders = ["Authorization"]
        secret.governance = governance
        try store.database.write { db in
            try secret.update(db)
        }
        return try XCTUnwrap(store.fetchSecret(id: secret.id))
    }

    func testListSecretsReturnsMetadataOnly() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let listed = try resolver.handleListSecrets(search: nil, vaultName: nil, kindRaw: nil)
        XCTAssertEqual(listed.count, 1)
        let entry = try XCTUnwrap(listed.first)
        XCTAssertEqual(entry.internalName, "service_main")
        XCTAssertEqual(entry.kind, "api_key")
        XCTAssertEqual(entry.allowedHosts, ["api.example.com"])
        XCTAssertTrue(entry.fields.isEmpty, "list should not include field metadata")
    }

    func testDescribeSecretIncludesFieldsButNotValues() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let described = try resolver.handleDescribeSecret(name: "service_main")
        XCTAssertEqual(described.fields.count, 2)
        XCTAssertEqual(described.fields.map { $0.name }, ["header", "token"])
        XCTAssertEqual(described.fields.first { $0.name == "token" }?.isSecret, true)
        XCTAssertEqual(described.fields.first { $0.name == "header" }?.isSecret, false)
    }

    func testResolveBareNamePicksFirstSecretField() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let token = PlaceholderToken(raw: "{{service_main}}", secretInternalName: "service_main", fieldName: nil)
        let context = ResolveContext(host: "api.example.com", method: "GET", headerNames: ["Authorization"], inEnv: false)
        let result = try resolver.handleResolve(placeholders: [token], context: context)
        XCTAssertEqual(result.values["{{service_main}}"], "sk-deadbeef-1234")
        XCTAssertEqual(result.sensitiveValues, ["sk-deadbeef-1234"])
        XCTAssertEqual(result.redactionLabels["{{service_main}}"], "[REDACTED:service_main]")
    }

    func testResolveExplicitFieldName() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let token = PlaceholderToken(raw: "{{service_main.header}}", secretInternalName: "service_main", fieldName: "header")
        let context = ResolveContext(host: "api.example.com", headerNames: ["Authorization"])
        let result = try resolver.handleResolve(placeholders: [token], context: context)
        XCTAssertEqual(result.values["{{service_main.header}}"], "Authorization")
        XCTAssertTrue(result.sensitiveValues.isEmpty, "public field is not sensitive")
    }

    func testResolveRejectsHostNotInAllowList() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let token = PlaceholderToken(raw: "{{service_main}}", secretInternalName: "service_main", fieldName: nil)
        let context = ResolveContext(host: "evil.example.com", headerNames: ["Authorization"])
        XCTAssertThrowsError(try resolver.handleResolve(placeholders: [token], context: context)) { err in
            guard case ProxyResolver.ResolveError.hostNotAllowed(let host, _) = err else {
                XCTFail("expected hostNotAllowed, got \(err)"); return
            }
            XCTAssertEqual(host, "evil.example.com")
        }
    }

    func testResolveRejectsHeaderNotInAllowList() throws {
        let (resolver, store, _, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let token = PlaceholderToken(raw: "{{service_main}}", secretInternalName: "service_main", fieldName: nil)
        let context = ResolveContext(host: "api.example.com", headerNames: ["X-Custom"])
        XCTAssertThrowsError(try resolver.handleResolve(placeholders: [token], context: context))
    }

    func testWildcardHostMatch() {
        XCTAssertTrue(ProxyResolver.hostMatches("api.github.com", allowList: ["*.github.com"]))
        XCTAssertTrue(ProxyResolver.hostMatches("API.GitHub.com", allowList: ["*.github.com"]))
        XCTAssertFalse(ProxyResolver.hostMatches("github.com.evil.com", allowList: ["*.github.com"]))
        XCTAssertTrue(ProxyResolver.hostMatches("api.example.com", allowList: ["api.example.com"]))
    }

    func testCompromisedSecretRejected() throws {
        let (resolver, store, _, vault) = try setUp()
        let secret = try openAISecret(in: store, vault: vault)
        try store.setCompromised(id: secret.id, flag: true)
        let token = PlaceholderToken(raw: "{{service_main}}", secretInternalName: "service_main", fieldName: nil)
        let context = ResolveContext(host: "api.example.com", headerNames: ["Authorization"])
        XCTAssertThrowsError(try resolver.handleResolve(placeholders: [token], context: context)) { err in
            guard case ProxyResolver.ResolveError.secretLocked = err else {
                // Compromised marks the secret as locked; both errors are acceptable here.
                if case ProxyResolver.ResolveError.secretCompromised = err { return }
                XCTFail("expected secretLocked or secretCompromised, got \(err)"); return
            }
        }
    }

    func testRecordAuditCallEmitsEncryptedEvent() throws {
        let (resolver, store, audit, vault) = try setUp()
        _ = try openAISecret(in: store, vault: vault)
        let summary = ProxyAuditCallSummary(
            kind: AuditEventKind.proxyRequest.rawValue,
            success: true,
            host: "api.example.com",
            method: "GET",
            redactedRequest: "{\"url\":\"https://api.example.com\",\"headers\":{\"Authorization\":\"Bearer [REDACTED:service_main]\"}}",
            responseSize: 4096,
            latencyMs: 312,
            sessionId: "session-A",
            secretInternalNames: ["service_main"]
        )
        try resolver.recordAuditCall(summary, secretInternalNames: ["service_main"])
        let events = try audit.recentEvents()
        let proxyEvent = try XCTUnwrap(events.first { $0.kind == .proxyRequest })
        XCTAssertEqual(proxyEvent.payload.host, "api.example.com")
        XCTAssertEqual(proxyEvent.payload.responseSize, 4096)
        XCTAssertEqual(proxyEvent.payload.latencyMs, 312)
        XCTAssertEqual(proxyEvent.payload.secretInternalNameFrozen, "service_main")
        XCTAssertEqual(proxyEvent.sessionId, "session-A")
        let report = try audit.verifyIntegrity()
        XCTAssertTrue(report.isIntact)
    }

    func testResolveBumpsUseCount() throws {
        let (resolver, store, _, vault) = try setUp()
        let secret = try openAISecret(in: store, vault: vault)
        XCTAssertEqual(secret.useCount, 0)

        let token = PlaceholderToken(raw: "{{service_main}}", secretInternalName: "service_main", fieldName: nil)
        let context = ResolveContext(host: "api.example.com", headerNames: ["Authorization"])
        _ = try resolver.handleResolve(placeholders: [token], context: context)
        _ = try resolver.handleResolve(placeholders: [token], context: context)

        let updated = try XCTUnwrap(store.fetchSecret(id: secret.id))
        XCTAssertEqual(updated.useCount, 2)
        XCTAssertNotNil(updated.lastUsedAt)
    }
}
