import XCTest
import GRDB
@testable import SecretsPersistence
import SecretsModels

final class SchemaV1Tests: XCTestCase {

    func testMigratorOpensAndCreatesAllTables() throws {
        let db = try SecretsDatabase.openTemporary()
        let tables = try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
        }
        XCTAssertEqual(Set(tables), [
            "accounts", "agentGrants", "attachments", "auditEvents", "secretFields",
            "secretNotes", "secretVersions", "secrets", "secretsSettings",
            "vaultMeta", "vaults"
        ])
    }

    func testDefaultAccountSeeded() throws {
        let db = try SecretsDatabase.openTemporary()
        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts WHERE id = 0")
        }
        XCTAssertEqual(count, 1)
    }

    func testForeignKeysEnforced() throws {
        let db = try SecretsDatabase.openTemporary()
        XCTAssertThrowsError(try db.write { db in
            try db.execute(sql: """
                INSERT INTO secrets (id, accountId, vaultId, kind, internalName, title, wrappedItemKey, currentVersionId, createdAt, updatedAt)
                VALUES ('s1', 0, 'nonexistent-vault', 'api_key', 'test', 'Test', X'00', 'v1', 0, 0)
                """)
        })
    }

    func testInsertVaultAndSecretFlow() throws {
        let db = try SecretsDatabase.openTemporary()
        let vaultId = EntityID.newID()
        let secretId = EntityID.newID()
        let versionId = EntityID.newID()

        try db.write { db in
            var vault = VaultRecord(id: vaultId, name: "Personal")
            try vault.insert(db)

            var secret = SecretRecord(
                id: secretId,
                vaultId: vaultId,
                kind: .apiKey,
                internalName: "service_main",
                title: "Service",
                wrappedItemKey: Data(repeating: 0xAA, count: 29),
                currentVersionId: versionId,
                allowedHostsJson: #"["api.example.com"]"#
            )
            try secret.insert(db)

            var version = SecretVersionRecord(
                id: versionId,
                secretId: secretId,
                versionNumber: 1,
                reason: .create
            )
            try version.insert(db)

            var field = SecretFieldRecord(
                secretId: secretId,
                versionId: versionId,
                fieldName: "token",
                fieldKind: .password,
                placement: .header,
                isSecret: true,
                valueCiphertext: Data(repeating: 0xBB, count: 64),
                sortOrder: 0
            )
            try field.insert(db)
        }

        try db.read { db in
            let vault = try VaultRecord.fetchOne(db, key: vaultId.uuidString.uppercased())
            XCTAssertEqual(vault?.name, "Personal")

            let secret = try SecretRecord.fetchOne(db, key: secretId.uuidString.uppercased())
            XCTAssertEqual(secret?.internalName, "service_main")
            XCTAssertEqual(secret?.kind, .apiKey)

            let fieldCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM secretFields WHERE secretId = ?", arguments: [secretId.uuidString.uppercased()])
            XCTAssertEqual(fieldCount, 1)
        }
    }

    func testVaultMetaRoundTrip() throws {
        let db = try SecretsDatabase.openTemporary()
        let salt = Data(repeating: 0x42, count: 32)

        try db.write { db in
            var row = VaultMetaRow(key: VaultMetaKey.kdfSalt, value: salt)
            try row.insert(db)
        }

        let loaded = try db.read { db -> VaultMetaRow? in
            try VaultMetaRow.fetchOne(db, key: VaultMetaKey.kdfSalt)
        }
        XCTAssertEqual(loaded?.value, salt)
    }

    func testUniqueInternalNamePerAccount() throws {
        let db = try SecretsDatabase.openTemporary()
        let vaultId = EntityID.newID()
        let id1 = EntityID.newID()
        let id2 = EntityID.newID()
        let ver1 = EntityID.newID()
        let ver2 = EntityID.newID()

        try db.write { db in
            try VaultRecord(id: vaultId, name: "Personal").insert(db)
            try SecretRecord(
                id: id1,
                vaultId: vaultId,
                kind: .apiKey,
                internalName: "duplicated_name",
                title: "First",
                wrappedItemKey: Data(),
                currentVersionId: ver1
            ).insert(db)
            try SecretVersionRecord(id: ver1, secretId: id1, versionNumber: 1, reason: .create).insert(db)
        }

        XCTAssertThrowsError(try db.write { db in
            try SecretRecord(
                id: id2,
                vaultId: vaultId,
                kind: .apiKey,
                internalName: "duplicated_name",
                title: "Second",
                wrappedItemKey: Data(),
                currentVersionId: ver2
            ).insert(db)
            try SecretVersionRecord(id: ver2, secretId: id2, versionNumber: 1, reason: .create).insert(db)
        })
    }

    func testAuditChainCheckEnforced() throws {
        let db = try SecretsDatabase.openTemporary()

        XCTAssertThrowsError(try db.write { db in
            try db.execute(sql: """
                INSERT INTO auditEvents (id, accountId, kind, timestamp, source, wrappedEventKey, payloadCiphertext, prevHash, selfHash)
                VALUES ('e1', 0, 'vault_setup', 0, 'system', X'00', X'00', X'AA', X'BB')
                """)
        })
    }
}
