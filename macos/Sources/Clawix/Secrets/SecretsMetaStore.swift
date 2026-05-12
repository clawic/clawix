import Foundation
import GRDB
import SecretsCrypto
import SecretsPersistence

enum SecretsMetaStore {

    private static let snapshotKey = "snapshot"

    static func read(from db: SecretsDatabase) throws -> VaultMetaSnapshot? {
        let row = try db.read { database -> VaultMetaRow? in
            try VaultMetaRow.fetchOne(database, key: snapshotKey)
        }
        guard let row else { return nil }
        return try JSONDecoder().decode(VaultMetaSnapshot.self, from: row.value)
    }

    static func write(_ snapshot: VaultMetaSnapshot, to db: SecretsDatabase) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        try db.write { database in
            try VaultMetaRow(key: snapshotKey, value: data).insert(database, onConflict: .replace)
        }
    }
}
