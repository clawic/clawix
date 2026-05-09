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
            try db.execute(sql: "DELETE FROM sidebar_snapshot")
            try db.execute(sql: "DELETE FROM sidebar_snapshot_project")
            try db.execute(sql: "DELETE FROM project_sort_order")
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

        // Cache of the sidebar's last applied state. Lets the next launch
        // paint Pinned + chat list instantly from local SQLite instead of
        // waiting for the runtime to bootstrap and paginate threads.
        // Persists Chat.id (UUID) so identities stay stable across runs
        // and pinnedOrder, ChatSidebars and currentRoute don't flicker
        // when the runtime data lands and applyThreads reconciles.
        migrator.registerMigration("v4_sidebar_snapshot") { db in
            try db.execute(sql: """
                CREATE TABLE sidebar_snapshot (
                    thread_id    TEXT PRIMARY KEY NOT NULL,
                    chat_uuid    TEXT NOT NULL,
                    title        TEXT NOT NULL,
                    cwd          TEXT,
                    project_path TEXT,
                    updated_at   INTEGER NOT NULL,
                    archived     INTEGER NOT NULL DEFAULT 0,
                    pinned       INTEGER NOT NULL DEFAULT 0,
                    captured_at  INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX sidebar_snapshot_order_idx
                    ON sidebar_snapshot(pinned DESC, updated_at DESC)
            """)
        }

        // Per-project sidebar index. The `sidebar_snapshot` table above
        // captures the top-N globally-recent chats for the first paint
        // of Pinned + Chronological. That set isn't enough to render
        // every project's accordion instantly: a chat that's old
        // globally can still be the freshest chat in its project and
        // must appear there without waiting for a per-project RPC.
        // This table stores up to ~200 recent chats per project, keyed
        // by thread id so it deduplicates against the global table on
        // hydration. `project_path` is NOT NULL on purpose: rows here
        // only exist for chats whose project is resolved.
        migrator.registerMigration("v5_sidebar_snapshot_project") { db in
            try db.execute(sql: """
                CREATE TABLE sidebar_snapshot_project (
                    thread_id    TEXT PRIMARY KEY NOT NULL,
                    chat_uuid    TEXT NOT NULL,
                    title        TEXT NOT NULL,
                    cwd          TEXT,
                    project_path TEXT NOT NULL,
                    updated_at   INTEGER NOT NULL,
                    archived     INTEGER NOT NULL DEFAULT 0,
                    pinned       INTEGER NOT NULL DEFAULT 0,
                    captured_at  INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX sidebar_snapshot_project_path_idx
                    ON sidebar_snapshot_project(project_path, updated_at DESC)
            """)
        }

        // Manual project ordering for the sidebar's "Custom" sort mode.
        // Keyed by stable Project UUID (path-derived, see StableProjectID)
        // so it works for both Codex-sourced and locally created projects.
        // Values use 1000-step gaps like pinned threads so single-row
        // moves don't have to renumber the table.
        migrator.registerMigration("v6_project_sort_order") { db in
            try db.execute(sql: """
                CREATE TABLE project_sort_order (
                    project_id TEXT PRIMARY KEY NOT NULL,
                    sort_order INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX project_sort_order_idx
                    ON project_sort_order(sort_order)
            """)
        }

        // Dictation transcript history (#24). One row per transcript;
        // the `audio_file_path` column is nullable so audio-only
        // cleanup (#25) can drop the WAV without losing the row.
        // FTS happens client-side on `original_text` because GRDB's
        // FTS module isn't enabled in this build.
        migrator.registerMigration("v7_dictation_transcripts") { db in
            try db.execute(sql: """
                CREATE TABLE dictation_transcript (
                    id                 TEXT PRIMARY KEY NOT NULL,
                    timestamp          INTEGER NOT NULL,
                    original_text      TEXT NOT NULL,
                    enhanced_text      TEXT,
                    model_used         TEXT,
                    language           TEXT,
                    duration_seconds   REAL NOT NULL,
                    audio_file_path    TEXT,
                    power_mode_id      TEXT,
                    word_count         INTEGER NOT NULL DEFAULT 0,
                    transcription_ms   INTEGER NOT NULL DEFAULT 0,
                    enhancement_ms     INTEGER NOT NULL DEFAULT 0,
                    enhancement_provider TEXT,
                    cost_usd           REAL NOT NULL DEFAULT 0
                )
            """)
            try db.execute(sql: """
                CREATE INDEX dictation_transcript_timestamp_idx
                    ON dictation_transcript(timestamp DESC)
            """)
        }

        return migrator
    }
}
