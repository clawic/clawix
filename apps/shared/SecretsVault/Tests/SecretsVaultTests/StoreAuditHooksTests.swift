import XCTest
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence
@testable import SecretsVault
import ClawixArgon2

final class StoreAuditHooksTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func makeStoreWithAudit() throws -> (SecretsStore, AuditStore, VaultBootstrap) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let audit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "device-test"
        )
        let store = SecretsStore(database: database, masterKey: bootstrap.masterKey, audit: audit)
        return (store, audit, bootstrap)
    }

    func testCreateVaultEmitsAuditEvent() throws {
        let (store, audit, _) = try makeStoreWithAudit()
        let vault = try store.createVault(name: "Personal")
        let events = try audit.recentEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .adminCreate)
        XCTAssertEqual(events.first?.vaultId, vault.id)
        XCTAssertEqual(events.first?.source, .admin)
    }

    func testCreateSecretAndRevealEmitChainOfEvents() throws {
        let (store, audit, _) = try makeStoreWithAudit()
        let vault = try store.createVault(name: "Personal")
        let draft = DraftSecret(
            kind: .apiKey,
            internalName: "service_main",
            title: "Service",
            fields: [DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-test")]
        )
        let secret = try store.createSecret(in: vault, draft: draft)
        let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
        _ = try store.revealField(fields[0], purpose: .reveal)
        _ = try store.revealField(fields[0], purpose: .copy)
        try store.trashSecret(id: secret.id)
        try store.restoreSecret(id: secret.id)

        let events = try audit.recentEvents()
        // 1 vault create + 1 secret create + 1 reveal + 1 copy + 1 trash + 1 restore.
        XCTAssertEqual(events.count, 6)
        let kinds = events.map { $0.kind }.reversed()
        XCTAssertEqual(Array(kinds), [
            .adminCreate, .adminCreate, .uiReveal, .uiCopy, .adminTrash, .adminRestoreVersion
        ])

        let report = try audit.verifyIntegrity()
        XCTAssertTrue(report.isIntact)
    }

    func testFrozenInternalNameSurvivesPurge() throws {
        let (store, audit, _) = try makeStoreWithAudit()
        let vault = try store.createVault(name: "Personal")
        let secret = try store.createSecret(
            in: vault,
            draft: DraftSecret(kind: .apiKey, internalName: "ephemeral", title: "Ephemeral", fields: [])
        )
        try store.trashSecret(id: secret.id)
        let trashed = try store.fetchSecret(id: secret.id)
        XCTAssertNotNil(trashed?.trashedAt)

        let purged = try store.purgeTrashed(olderThan: Clock.now() + 1)
        XCTAssertEqual(purged, 1)
        XCTAssertNil(try store.fetchSecret(id: secret.id))

        let events = try audit.recentEvents()
        let purgeEvent = events.first { $0.kind == .adminPurge }
        XCTAssertNotNil(purgeEvent)
        XCTAssertEqual(purgeEvent?.payload.secretInternalNameFrozen, "ephemeral")
        XCTAssertEqual(purgeEvent?.payload.secretKindFrozen, .apiKey)
        XCTAssertEqual(purgeEvent?.source, .system)

        let report = try audit.verifyIntegrity()
        XCTAssertTrue(report.isIntact)
    }
}
