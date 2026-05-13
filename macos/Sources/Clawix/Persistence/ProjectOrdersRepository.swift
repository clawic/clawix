import Foundation
import GRDB

@MainActor
final class ProjectOrdersRepository {
    private let db: DatabaseQueue
    private static let orderGap: Int64 = 1000

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func orderedIds() -> [UUID] {
        let rows = (try? db.read {
            try ProjectSortOrderRow.order(Column("sort_order")).fetchAll($0)
        }) ?? []
        return rows.compactMap { UUID(uuidString: $0.projectId) }
    }

    func setOrder(_ projectIds: [UUID]) {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM project_sort_order")
            for (idx, id) in projectIds.enumerated() {
                let row = ProjectSortOrderRow(projectId: id.uuidString,
                                              sortOrder: Int64(idx + 1) * Self.orderGap)
                try row.insert(db)
            }
        }
        ClawJSAppStateClient.setProjectOrder(projectIds.map(\.uuidString))
    }
}
