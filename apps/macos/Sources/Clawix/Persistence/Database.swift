import Foundation
import GRDB

// SQLite-backed local store. Owns the DatabaseQueue and the schema
// migrator. Lives at:
//   ~/Library/Application Support/Clawix/clawix.sqlite
//
// Override path with CLAWIX_DATABASE_FILE for tests; ":memory:" creates
// an in-memory queue.
@MainActor
final class Database {
    static let shared = Database()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let queue = try Self.makeQueue()
            try Self.migrator.migrate(queue)
            self.dbQueue = queue
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private static func makeQueue() throws -> DatabaseQueue {
        if let override = ProcessInfo.processInfo.environment["CLAWIX_DATABASE_FILE"], !override.isEmpty {
            if override == ":memory:" {
                return try DatabaseQueue()
            }
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            var config = Configuration()
            config.foreignKeysEnabled = true
            return try DatabaseQueue(path: url.path, configuration: config)
        }
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawix", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let url = supportDir.appendingPathComponent("clawix.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try DatabaseQueue(path: url.path, configuration: config)
    }

    struct LocalOverrideCounts {
        let pins: Int
        let projects: Int
        let chatProjectOverrides: Int
        let projectlessThreads: Int
        let archives: Int
        let titles: Int
        let hiddenRoots: Int
        var total: Int { pins + projects + chatProjectOverrides + projectlessThreads + archives + titles + hiddenRoots }
    }

    /// Wipe every user-curated table in a single transaction. Schema
    /// stays intact (CREATE TABLEs from migrations are not touched).
    /// Also clears the meta flags that gate one-shot behaviors so the
    /// next refresh re-seeds from the runtime as if first launch.
    func resetLocalOverrides() {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pinned_threads")
            try db.execute(sql: "DELETE FROM projects")
            try db.execute(sql: "DELETE FROM chat_project_overrides")
            try db.execute(sql: "DELETE FROM projectless_threads")
            try db.execute(sql: "DELETE FROM local_archives")
            try db.execute(sql: "DELETE FROM session_titles")
            try db.execute(sql: "DELETE FROM hidden_codex_roots")
            try db.execute(sql: "DELETE FROM meta WHERE key IN ('has_local_pins','archives_seeded')")
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: """
                CREATE TABLE projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    path TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX projects_path_idx ON projects(path) WHERE path <> ''
            """)
            try db.execute(sql: """
                CREATE TABLE pinned_threads (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    sort_order INTEGER NOT NULL,
                    pinned_at INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX pinned_threads_order_idx ON pinned_threads(sort_order)
            """)
            try db.execute(sql: """
                CREATE TABLE chat_project_overrides (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    project_path TEXT NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE projectless_threads (
                    thread_id TEXT PRIMARY KEY NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE session_titles (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    source TEXT NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE meta (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                )
            """)
        }

        migrator.registerMigration("v2_local_archives") { db in
            try db.execute(sql: """
                CREATE TABLE local_archives (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    archived_at INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX local_archives_archived_at_idx ON local_archives(archived_at)
            """)
        }

        migrator.registerMigration("v3_hidden_codex_roots") { db in
            try db.execute(sql: """
                CREATE TABLE hidden_codex_roots (
                    path TEXT PRIMARY KEY NOT NULL,
                    hidden_at INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX hidden_codex_roots_hidden_at_idx ON hidden_codex_roots(hidden_at)
            """)
        }

        return migrator
    }
}
