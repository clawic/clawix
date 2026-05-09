import Foundation
import GRDB

@MainActor
final class ChatProjectsRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func overridesCount() -> Int {
        (try? db.read { try ChatProjectOverrideRow.fetchCount($0) }) ?? 0
    }

    func projectlessCount() -> Int {
        (try? db.read { try ProjectlessThreadRow.fetchCount($0) }) ?? 0
    }

    func allOverrides() -> [String: String] {
        let rows = (try? db.read { try ChatProjectOverrideRow.fetchAll($0) }) ?? []
        var dict: [String: String] = [:]
        for row in rows { dict[row.threadId] = row.projectPath }
        return dict
    }

    func overridePath(for threadId: String) -> String? {
        try? db.read { try ChatProjectOverrideRow.fetchOne($0, key: threadId)?.projectPath }
    }

    func setOverride(threadId: String, projectPath: String) {
        try? db.write { db in
            let row = ChatProjectOverrideRow(threadId: threadId, projectPath: projectPath)
            try row.upsert(db)
            _ = try ProjectlessThreadRow.deleteOne(db, key: threadId)
        }
    }

    func clearOverride(threadId: String) {
        try? db.write { _ = try ChatProjectOverrideRow.deleteOne($0, key: threadId) }
    }

    func allProjectless() -> Set<String> {
        let rows = (try? db.read { try ProjectlessThreadRow.fetchAll($0) }) ?? []
        return Set(rows.map(\.threadId))
    }

    func isProjectless(_ threadId: String) -> Bool {
        (try? db.read { try ProjectlessThreadRow.fetchOne($0, key: threadId) }) != nil
    }

    func markProjectless(_ threadId: String) {
        try? db.write { db in
            try ProjectlessThreadRow(threadId: threadId).upsert(db)
            _ = try ChatProjectOverrideRow.deleteOne(db, key: threadId)
        }
    }

    func unmarkProjectless(_ threadId: String) {
        try? db.write { _ = try ProjectlessThreadRow.deleteOne($0, key: threadId) }
    }
}
