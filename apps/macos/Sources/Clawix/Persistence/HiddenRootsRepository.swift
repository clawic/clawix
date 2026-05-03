import Foundation
import GRDB

@MainActor
final class HiddenRootsRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func isHidden(_ path: String) -> Bool {
        (try? db.read { try HiddenRootRecord.fetchOne($0, key: path) }) != nil
    }

    func allHidden() -> [String] {
        let rows = (try? db.read {
            try HiddenRootRecord.order(Column("hidden_at").desc).fetchAll($0)
        }) ?? []
        return rows.map(\.path)
    }

    func count() -> Int {
        (try? db.read { try HiddenRootRecord.fetchCount($0) }) ?? 0
    }

    func hide(_ path: String) {
        let now = Int64(Date().timeIntervalSince1970)
        try? db.write { db in
            if try HiddenRootRecord.fetchOne(db, key: path) != nil { return }
            try HiddenRootRecord(path: path, hiddenAt: now).insert(db)
        }
    }

    func show(_ path: String) {
        try? db.write { _ = try HiddenRootRecord.deleteOne($0, key: path) }
    }
}
