import Foundation
import GRDB

@MainActor
final class ProjectsRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func count() -> Int {
        (try? db.read { try ProjectRecord.fetchCount($0) }) ?? 0
    }

    func all() -> [Project] {
        let rows = (try? db.read { try ProjectRecord.order(Column("created_at")).fetchAll($0) }) ?? []
        return rows.map(Project.init(row:))
    }

    func upsert(_ project: Project) {
        let now = Int64(Date().timeIntervalSince1970)
        let existing = try? db.read { try ProjectRecord.fetchOne($0, key: project.id.uuidString) }
        let createdAt = existing?.createdAt ?? now
        let row = ProjectRecord(id: project.id.uuidString,
                                resourceId: project.resourceId,
                                name: project.name,
                                path: project.path,
                                createdAt: createdAt)
        try? db.write { try row.upsert($0) }
        ClawJSAppStateClient.upsertProject(
            id: project.id.uuidString,
            resourceId: project.resourceId,
            name: project.name,
            path: project.path
        )
        if let resourceId = project.resourceId {
            ClawJSAppStateClient.registerProjectResource(id: resourceId, path: project.path, label: project.name)
        }
    }

    func delete(id: UUID) {
        try? db.write { _ = try ProjectRecord.deleteOne($0, key: id.uuidString) }
        ClawJSAppStateClient.deleteProject(id: id.uuidString)
    }

    func rename(id: UUID, to name: String) {
        let record = try? db.read { try ProjectRecord.fetchOne($0, key: id.uuidString) }
        let path = record?.path ?? ""
        try? db.write { db in
            try db.execute(sql: "UPDATE projects SET name = ? WHERE id = ?",
                           arguments: [name, id.uuidString])
        }
        ClawJSAppStateClient.upsertProject(id: id.uuidString, resourceId: record?.resourceId, name: name, path: path)
        if let resourceId = record?.resourceId {
            ClawJSAppStateClient.registerProjectResource(id: resourceId, path: path, label: name)
        }
    }
}

extension Project {
    init(row: ProjectRecord) {
        self.init(id: UUID(uuidString: row.id) ?? UUID(),
                  resourceId: row.resourceId,
                  name: row.name,
                  path: row.path)
    }
}
