import Foundation
import GRDB

// Persistent cache of the sidebar's last applied state, used to paint
// Pinned + chat list instantly on the next launch instead of waiting for
// the runtime to bootstrap and paginate threads.
//
// This is presentation cache, not source of truth: every successful
// `applyThreads` / `mergeThreads` rewrites it from the just-applied
// `chats[]`. Reads are cheap (one indexed query). Writes happen off
// the main thread via GRDB's serialized queue, so the repository is
// nonisolated and Sendable on purpose.
final class SnapshotRepository: @unchecked Sendable {
    private let db: DatabaseQueue

    @MainActor
    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func count() -> Int {
        (try? db.read { try SidebarSnapshotRow.fetchCount($0) }) ?? 0
    }

    /// Top N rows for the first paint, ordered so pinned chats land first
    /// and the rest follow by recency.
    func loadTop(limit: Int) -> [SidebarSnapshotRow] {
        (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
                LIMIT ?
            """, arguments: [limit])
        }) ?? []
    }

    func loadAll() -> [SidebarSnapshotRow] {
        (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
            """)
        }) ?? []
    }

    /// Replace the whole snapshot in a single transaction. Called after
    /// every successful applyThreads/mergeThreads with the canonical
    /// in-memory chats list.
    func replaceAll(_ rows: [SidebarSnapshotRow]) {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM sidebar_snapshot")
            for row in rows {
                try row.insert(db)
            }
        }
    }
}
