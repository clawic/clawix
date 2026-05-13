import Foundation
import GRDB

@MainActor
final class PinsRepository {
    private let db: DatabaseQueue
    private static let orderGap: Int64 = 1000

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func count() -> Int {
        (try? db.read { try PinnedThreadRow.fetchCount($0) }) ?? 0
    }

    func orderedThreadIds() -> [String] {
        let rows = (try? db.read {
            try PinnedThreadRow.order(Column("sort_order")).fetchAll($0)
        }) ?? []
        return rows.map(\.threadId)
    }

    func isPinned(_ threadId: String) -> Bool {
        (try? db.read { try PinnedThreadRow.fetchOne($0, key: threadId) }) != nil
    }

    func setPinned(_ threadId: String, atEnd: Bool = true) {
        var mirroredOrder: Int64?
        try? db.write { db in
            if try PinnedThreadRow.fetchOne(db, key: threadId) != nil { return }
            let now = Int64(Date().timeIntervalSince1970)
            let lastOrder = try Int64.fetchOne(db,
                sql: "SELECT MAX(sort_order) FROM pinned_threads") ?? 0
            let firstOrder = try Int64.fetchOne(db,
                sql: "SELECT MIN(sort_order) FROM pinned_threads") ?? 0
            let newOrder = atEnd ? lastOrder + Self.orderGap : firstOrder - Self.orderGap
            let row = PinnedThreadRow(threadId: threadId,
                                      sortOrder: newOrder,
                                      pinnedAt: now)
            try row.upsert(db)
            mirroredOrder = newOrder
        }
        if let mirroredOrder {
            ClawJSAppStateClient.upsertPin(threadId: threadId, sortOrder: mirroredOrder)
        }
    }

    func unpin(_ threadId: String) {
        try? db.write { _ = try PinnedThreadRow.deleteOne($0, key: threadId) }
        ClawJSAppStateClient.deletePin(threadId: threadId)
    }

    /// Append every id in `threadIds` that is not already pinned, in the
    /// order received, after the current last pinned row. Returns the
    /// count of newly inserted rows.
    @discardableResult
    func addIfMissing(_ threadIds: [String]) -> Int {
        guard !threadIds.isEmpty else { return 0 }
        var mirroredOrder: [String] = []
        return (try? db.write { db in
            let existing = Set(try PinnedThreadRow.fetchAll(db).map(\.threadId))
            let toAdd = threadIds.filter { !existing.contains($0) }
            guard !toAdd.isEmpty else { return 0 }
            var lastOrder = try Int64.fetchOne(db,
                sql: "SELECT MAX(sort_order) FROM pinned_threads") ?? 0
            let now = Int64(Date().timeIntervalSince1970)
            for id in toAdd {
                lastOrder += Self.orderGap
                let row = PinnedThreadRow(threadId: id,
                                          sortOrder: lastOrder,
                                          pinnedAt: now)
                try row.insert(db)
            }
            mirroredOrder = try PinnedThreadRow
                .order(Column("sort_order"))
                .fetchAll(db)
                .map(\.threadId)
            return toAdd.count
        }).map { count in
            if !mirroredOrder.isEmpty {
                ClawJSAppStateClient.setPinOrder(mirroredOrder)
            }
            return count
        } ?? 0
    }

    /// Replace the full pinned order with the given list, preserving
    /// pinned_at timestamps when possible. Used after drag-reorder.
    func setOrder(_ threadIds: [String]) {
        try? db.write { db in
            let existing = try PinnedThreadRow.fetchAll(db)
            let pinnedAtById = Dictionary(uniqueKeysWithValues: existing.map { ($0.threadId, $0.pinnedAt) })
            let now = Int64(Date().timeIntervalSince1970)
            try db.execute(sql: "DELETE FROM pinned_threads")
            for (idx, id) in threadIds.enumerated() {
                let row = PinnedThreadRow(threadId: id,
                                          sortOrder: Int64(idx + 1) * Self.orderGap,
                                          pinnedAt: pinnedAtById[id] ?? now)
                try row.insert(db)
            }
        }
        ClawJSAppStateClient.setPinOrder(threadIds)
    }
}
