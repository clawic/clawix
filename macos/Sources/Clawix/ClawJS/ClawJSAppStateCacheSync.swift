import Foundation
import GRDB

@MainActor
enum ClawJSAppStateCacheSync {
    static func refreshFromCanonicalStore() async {
        guard let snapshot = try? await ClawJSAppStateClient.snapshot() else { return }
        let db = Database.shared.dbQueue
        try? await db.write { database in
            try replaceProjects(snapshot.projects, in: database)
            try replacePins(snapshot.pinnedThreads, in: database)
            try replaceTitles(snapshot.titles, in: database)
            try replaceArchives(snapshot.archives, in: database)
            try replaceSidebar(snapshot.sidebar, in: database)
            try replaceTerminalTabs(snapshot.terminalTabs, in: database)
        }
    }

    nonisolated private static func replaceProjects(
        _ projects: [ClawJSAppStateSnapshot.Project],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM projects")
        try db.execute(sql: "DELETE FROM project_sort_order")
        let now = Int64(Date().timeIntervalSince1970)
        for (index, project) in projects.enumerated() {
            try ProjectRecord(
                id: project.id,
                resourceId: project.resourceId,
                name: project.name,
                path: project.path,
                createdAt: now
            ).insert(db)
            try ProjectSortOrderRow(
                projectId: project.id,
                sortOrder: project.sortOrder ?? Int64(index + 1) * 1000
            ).insert(db)
        }
    }

    nonisolated private static func replacePins(
        _ pins: [ClawJSAppStateSnapshot.PinnedThread],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM pinned_threads")
        for pin in pins {
            try PinnedThreadRow(
                threadId: pin.threadId,
                sortOrder: pin.sortOrder,
                pinnedAt: epoch(pin.pinnedAt)
            ).insert(db)
        }
    }

    nonisolated private static func replaceTitles(
        _ titles: [ClawJSAppStateSnapshot.Title],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM session_titles")
        for title in titles {
            try SessionTitleRow(
                threadId: title.threadId,
                title: title.title,
                updatedAt: epoch(title.updatedAt),
                source: title.source
            ).insert(db)
        }
    }

    nonisolated private static func replaceArchives(
        _ archives: [ClawJSAppStateSnapshot.Archive],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM local_archives")
        for archive in archives {
            try LocalArchiveRecord(
                threadId: archive.threadId,
                archivedAt: epoch(archive.archivedAt)
            ).insert(db)
        }
    }

    nonisolated private static func replaceSidebar(
        _ rows: [ClawJSAppStateSnapshot.Sidebar],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM sidebar_snapshot")
        try db.execute(sql: "DELETE FROM sidebar_snapshot_project")
        var projectRows: [SidebarSnapshotProjectRow] = []
        for row in rows {
            let updatedAt = epoch(row.updatedAt)
            try SidebarSnapshotRow(
                threadId: row.threadId,
                chatUuid: row.chatUuid,
                title: row.title,
                cwd: row.cwd,
                projectPath: row.projectPath,
                updatedAt: updatedAt,
                archived: Int64(row.archived),
                pinned: Int64(row.pinned),
                capturedAt: Int64(Date().timeIntervalSince1970)
            ).insert(db)
            if row.archived == 0, let projectPath = row.projectPath, !projectPath.isEmpty {
                projectRows.append(SidebarSnapshotProjectRow(
                    threadId: row.threadId,
                    chatUuid: row.chatUuid,
                    title: row.title,
                    cwd: row.cwd,
                    projectPath: projectPath,
                    updatedAt: updatedAt,
                    archived: 0,
                    pinned: Int64(row.pinned),
                    capturedAt: Int64(Date().timeIntervalSince1970)
                ))
            }
        }
        for projectRow in projectRows.prefix(5000) {
            try projectRow.insert(db)
        }
    }

    nonisolated private static func replaceTerminalTabs(
        _ tabs: [ClawJSAppStateSnapshot.TerminalTab],
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: "DELETE FROM terminal_tabs")
        for tab in tabs {
            guard let chatId = tab.metadata?["chatId"],
                  let layoutJson = tab.metadata?["layoutJson"] else { continue }
            var record = TerminalTabRecord(
                id: tab.id,
                chatId: chatId,
                label: tab.title,
                initialCwd: tab.cwd ?? "",
                layoutJson: layoutJson,
                focusedLeaf: tab.metadata?["focusedLeaf"].flatMap { $0.isEmpty ? nil : $0 },
                position: tab.sortOrder,
                createdAt: epoch(tab.createdAt)
            )
            try record.insert(db)
        }
    }

    nonisolated private static func epoch(_ iso: String?) -> Int64 {
        guard let iso,
              let date = ISO8601DateFormatter().date(from: iso) else {
            return Int64(Date().timeIntervalSince1970)
        }
        return Int64(date.timeIntervalSince1970)
    }
}
