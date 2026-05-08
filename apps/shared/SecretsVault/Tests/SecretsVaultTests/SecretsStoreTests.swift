import XCTest
import GRDB
import SecretsCrypto
import SecretsModels
import SecretsPersistence
@testable import SecretsVault
import ClawixArgon2

final class SecretsStoreTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func makeStore() throws -> (SecretsStore, VaultBootstrap) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let store = SecretsStore(database: database, masterKey: bootstrap.masterKey)
        return (store, bootstrap)
    }

    func testCreateAndListVault() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let listed = try store.listVaults()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, vault.id)
        XCTAssertEqual(listed.first?.name, "Personal")
    }

    func testCreateSecretWithFieldsAndReveal() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")

        let draft = DraftSecret(
            kind: .apiKey,
            internalName: "service_main",
            title: "Service · main",
            fields: [
                DraftField(name: "header", fieldKind: .text, placement: .header, isSecret: false, publicValue: "Authorization", sortOrder: 0),
                DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-test-deadbeef", sortOrder: 1)
            ],
            notes: "Backup token, do not share."
        )
        let secret = try store.createSecret(in: vault, draft: draft)
        XCTAssertEqual(secret.title, "Service · main")

        let listed = try store.listSecrets()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.internalName, "service_main")

        let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
        XCTAssertEqual(fields.count, 2)

        let revealedHeader = try store.revealField(fields[0])
        XCTAssertEqual(revealedHeader.value, "Authorization")
        XCTAssertEqual(revealedHeader.fieldKind, .text)

        let revealedToken = try store.revealField(fields[1])
        XCTAssertEqual(revealedToken.value, "sk-test-deadbeef")
        XCTAssertEqual(revealedToken.fieldKind, .password)

        let notes = try store.revealNotes(secret: secret)
        XCTAssertEqual(notes, "Backup token, do not share.")
    }

    func testRevealFailsWithDifferentMasterKey() throws {
        let (store, bootstrap) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let draft = DraftSecret(
            kind: .apiKey,
            internalName: "service_main",
            title: "Service",
            fields: [
                DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-x", sortOrder: 0)
            ]
        )
        let secret = try store.createSecret(in: vault, draft: draft)

        let otherMaster = LockableSecret.random(byteCount: 32)
        let alienStore = SecretsStore(database: store.database, masterKey: otherMaster)
        _ = bootstrap

        let fields = try alienStore.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
        XCTAssertThrowsError(try alienStore.revealField(fields[0])) { err in
            XCTAssertEqual(err as? SecretsStoreError, .lockedItemKey)
        }
    }

    func testCannotReadFieldOfTrashedSecretListByDefault() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let draft = DraftSecret(
            kind: .secureNote,
            internalName: "n1",
            title: "Note",
            fields: [DraftField(name: "content", fieldKind: .note, isSecret: true, secretValue: "secret note", sortOrder: 0)]
        )
        let secret = try store.createSecret(in: vault, draft: draft)
        try store.trashSecret(id: secret.id)

        let visible = try store.listSecrets()
        XCTAssertTrue(visible.isEmpty)

        let withTrash = try store.listSecrets(includeTrashed: true)
        XCTAssertEqual(withTrash.count, 1)
        XCTAssertNotNil(withTrash.first?.trashedAt)
    }

    func testRestoreSecret() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let draft = DraftSecret(kind: .secureNote, internalName: "n1", title: "Note", fields: [])
        let secret = try store.createSecret(in: vault, draft: draft)
        try store.trashSecret(id: secret.id)
        try store.restoreSecret(id: secret.id)
        let visible = try store.listSecrets()
        XCTAssertEqual(visible.count, 1)
        XCTAssertNil(visible.first?.trashedAt)
    }

    func testDuplicateInternalNameRejected() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let first = DraftSecret(kind: .apiKey, internalName: "duplicated", title: "First", fields: [])
        let second = DraftSecret(kind: .apiKey, internalName: "duplicated", title: "Second", fields: [])
        _ = try store.createSecret(in: vault, draft: first)
        XCTAssertThrowsError(try store.createSecret(in: vault, draft: second)) { err in
            XCTAssertEqual(err as? SecretsStoreError, .duplicateInternalName("duplicated"))
        }
    }

    func testListSecretsScopedToVault() throws {
        let (store, _) = try makeStore()
        let personal = try store.createVault(name: "Personal", sortOrder: 0)
        let work = try store.createVault(name: "Work", sortOrder: 1)
        _ = try store.createSecret(in: personal, draft: DraftSecret(kind: .apiKey, internalName: "p1", title: "Personal one", fields: []))
        _ = try store.createSecret(in: work, draft: DraftSecret(kind: .apiKey, internalName: "w1", title: "Work one", fields: []))
        XCTAssertEqual(try store.listSecrets(in: personal).count, 1)
        XCTAssertEqual(try store.listSecrets(in: work).count, 1)
        XCTAssertEqual(try store.listSecrets().count, 2)
    }

    func testItemKeyAADBindsCiphertextToSecret() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        let secret = try store.createSecret(
            in: vault,
            draft: DraftSecret(
                kind: .apiKey,
                internalName: "a1",
                title: "A",
                fields: [DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-a", sortOrder: 0)]
            )
        )

        // Move the wrappedItemKey of secret A to a different secret B's row (swap attack).
        // Reveal must fail because AAD encodes the secret id.
        let other = try store.createSecret(
            in: vault,
            draft: DraftSecret(
                kind: .apiKey,
                internalName: "b1",
                title: "B",
                fields: [DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-b", sortOrder: 0)]
            )
        )

        try store.database.write { db in
            // Swap the wrappedItemKey blob between rows.
            try db.execute(
                sql: "UPDATE secrets SET wrappedItemKey = ? WHERE id = ?",
                arguments: [other.wrappedItemKey, secret.id.uuidString.uppercased()]
            )
        }

        let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
        XCTAssertThrowsError(try store.revealField(fields[0])) { err in
            XCTAssertEqual(err as? SecretsStoreError, .lockedItemKey)
        }
    }

    func testRenameVault() throws {
        let (store, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        try store.renameVault(id: vault.id, to: "Personal stuff")
        let listed = try store.listVaults()
        XCTAssertEqual(listed.first?.name, "Personal stuff")
    }
}
