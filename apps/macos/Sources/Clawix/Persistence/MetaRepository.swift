import Foundation
import GRDB

@MainActor
final class MetaRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    var hasLocalPins: Bool {
        get { boolValue(forKey: "has_local_pins") }
        set { setBool(newValue, forKey: "has_local_pins") }
    }

    func string(forKey key: String) -> String? {
        try? db.read { try MetaRow.fetchOne($0, key: key)?.value }
    }

    func setString(_ value: String, forKey key: String) {
        try? db.write { try MetaRow(key: key, value: value).upsert($0) }
    }

    func boolValue(forKey key: String) -> Bool {
        string(forKey: key) == "true"
    }

    func setBool(_ value: Bool, forKey key: String) {
        setString(value ? "true" : "false", forKey: key)
    }
}
