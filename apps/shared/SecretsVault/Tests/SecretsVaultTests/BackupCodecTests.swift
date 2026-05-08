import XCTest
import SecretsModels
import SecretsCrypto
import SecretsPersistence
@testable import SecretsVault
import ClawixArgon2

final class BackupCodecTests: XCTestCase {

    private let smallParams = Argon2.Params(memoryKB: 1024, iterations: 2, parallelism: 1)

    private func makeStore() throws -> (SecretsStore, AuditStore, VaultBootstrap) {
        let bootstrap = try VaultCrypto.setUp(masterPassword: "hunter2", kdfParams: smallParams)
        let database = try SecretsDatabase.openTemporary()
        let audit = AuditStore(
            database: database,
            auditMacKey: bootstrap.auditMacKey,
            chainGenesis: bootstrap.meta.auditChainGenesis,
            deviceId: "device-1"
        )
        let store = SecretsStore(database: database, masterKey: bootstrap.masterKey, audit: audit)
        return (store, audit, bootstrap)
    }

    func testPackUnpackRoundTrip() throws {
        let contents = BackupContents(
            version: 1,
            vaults: [BackupVault(name: "Personal")],
            secrets: [BackupSecret(
                vaultName: "Personal",
                internalName: "service_main",
                title: "Service",
                kind: "api_key",
                brandPreset: nil,
                tags: ["work"],
                notes: "primary token",
                fields: [
                    BackupField(name: "token", fieldKind: "password", placement: "header", isSecret: true, isConcealed: true, value: "sk-deadbeef"),
                    BackupField(name: "header", fieldKind: "text", placement: "header", isSecret: false, isConcealed: false, value: "Authorization")
                ]
            )]
        )
        let packed = try BackupCodec.pack(contents: contents, passphrase: "correct horse battery staple", kdfParams: smallParams)
        XCTAssertTrue(BackupCodec.verifyMagic(data: packed))
        let unpacked = try BackupCodec.unpack(data: packed, passphrase: "correct horse battery staple")
        XCTAssertEqual(unpacked, contents)
    }

    func testWrongPassphraseFailsToDecrypt() throws {
        let contents = BackupContents(
            version: 1,
            vaults: [BackupVault(name: "Personal")],
            secrets: []
        )
        let packed = try BackupCodec.pack(contents: contents, passphrase: "right", kdfParams: smallParams)
        XCTAssertThrowsError(try BackupCodec.unpack(data: packed, passphrase: "wrong")) { err in
            XCTAssertEqual(err as? BackupCodecError, .decryptionFailed)
        }
    }

    func testTamperedBodyFailsToDecrypt() throws {
        let contents = BackupContents(version: 1, vaults: [], secrets: [])
        var packed = try BackupCodec.pack(contents: contents, passphrase: "abc", kdfParams: smallParams)
        // Flip a byte in the ciphertext (after magic+version+lenfield+header).
        packed[packed.count - 1] ^= 0x80
        XCTAssertThrowsError(try BackupCodec.unpack(data: packed, passphrase: "abc")) { err in
            XCTAssertEqual(err as? BackupCodecError, .decryptionFailed)
        }
    }

    func testTamperedHeaderFailsBecauseOfAAD() throws {
        let contents = BackupContents(version: 1, vaults: [BackupVault(name: "X")], secrets: [])
        var packed = try BackupCodec.pack(contents: contents, passphrase: "abc", kdfParams: smallParams)
        // Find the header start: 8 magic + 1 version + 4 length.
        let headerStart = 8 + 1 + 4
        packed[headerStart] ^= 0x01
        XCTAssertThrowsError(try BackupCodec.unpack(data: packed, passphrase: "abc"))
    }

    func testStoreSnapshotAndRestoreRoundTrip() throws {
        let (store, _, _) = try makeStore()
        let vault = try store.createVault(name: "Personal")
        _ = try store.createSecret(in: vault, draft: DraftSecret(
            kind: .apiKey,
            internalName: "service_main",
            title: "Service",
            fields: [
                DraftField(name: "token", fieldKind: .password, placement: .header, isSecret: true, secretValue: "sk-x", sortOrder: 0),
                DraftField(name: "header", fieldKind: .text, placement: .header, isSecret: false, isConcealed: false, publicValue: "Authorization", sortOrder: 1)
            ],
            notes: "Some notes"
        ))

        let snapshot = try store.snapshotForBackup()
        XCTAssertEqual(snapshot.vaults.count, 1)
        XCTAssertEqual(snapshot.secrets.count, 1)
        XCTAssertEqual(snapshot.secrets.first?.fields.first { $0.name == "token" }?.value, "sk-x")
        XCTAssertEqual(snapshot.secrets.first?.notes, "Some notes")

        // Restore into a fresh database with a different master key.
        let (store2, _, _) = try makeStore()
        let report = try store2.restoreBackup(snapshot)
        XCTAssertEqual(report.created, 1)
        XCTAssertEqual(report.skipped, 0)
        let restored = try store2.listSecrets()
        XCTAssertEqual(restored.first?.internalName, "service_main")

        // Restoring the same snapshot a second time must skip duplicates.
        let again = try store2.restoreBackup(snapshot)
        XCTAssertEqual(again.created, 0)
        XCTAssertEqual(again.skipped, 1)
    }

    func testFileFormatVerifiesMagic() {
        XCTAssertTrue(BackupCodec.verifyMagic(data: Data("CLAWIXBK".utf8) + Data([0x01])))
        XCTAssertFalse(BackupCodec.verifyMagic(data: Data("hello".utf8)))
    }
}
