import Foundation

enum PersistentSurfaceKind: String, Codable {
    case root
    case database
    case table
    case column
    case index
    case folder
    case file
    case socket
    case statusFile
    case preferenceKey
    case appStorageKey
    case cache
    case persistentTemp
    case externalReadOnlySource
}

struct PersistentSurfaceNode: Codable, Equatable {
    var id: String
    var kind: PersistentSurfaceKind
    var owner: String
    var repo: String
    var project: String
    var language: String
    var name: String
    var path: String?
    var key: String?
    var storageClass: String
    var canonicality: String
    var privacy: String
    var lifecycle: String
    var parentId: String?
    var databaseId: String?
    var dataType: String?
    var nullable: Bool?
    var notes: String?
    var warnings: [String]?
}

struct PersistentSurfaceManifest: Codable, Equatable {
    var version: Int
    var nodes: [PersistentSurfaceNode]
}

enum ClawixPersistentSurface {
    static func root(id: String, name: String, path: String, storageClass: String = "nativeAppData") -> PersistentSurfaceNode {
        node(id: id, kind: .root, name: name, path: path, storageClass: storageClass)
    }

    static func database(id: String, name: String, path: String, parentId: String? = nil) -> PersistentSurfaceNode {
        node(id: id, kind: .database, name: name, path: path, storageClass: "nativeAppData", parentId: parentId)
    }

    static func table(_ name: String, databaseId: String) -> PersistentSurfaceNode {
        node(
            id: "\(databaseId).table.\(name)",
            kind: .table,
            name: name,
            storageClass: "nativeAppData",
            parentId: databaseId,
            databaseId: databaseId
        )
    }

    static func column(_ name: String, tableId: String, databaseId: String, dataType: String, nullable: Bool = false) -> PersistentSurfaceNode {
        node(
            id: "\(tableId).column.\(name)",
            kind: .column,
            name: name,
            storageClass: "nativeAppData",
            parentId: tableId,
            databaseId: databaseId,
            dataType: dataType,
            nullable: nullable
        )
    }

    static func index(_ name: String, tableId: String, databaseId: String) -> PersistentSurfaceNode {
        node(
            id: "\(tableId).index.\(name)",
            kind: .index,
            name: name,
            storageClass: "nativeAppData",
            parentId: tableId,
            databaseId: databaseId
        )
    }

    static func folder(id: String, name: String, path: String, parentId: String? = nil, storageClass: String = "nativeAppData") -> PersistentSurfaceNode {
        node(id: id, kind: .folder, name: name, path: path, storageClass: storageClass, parentId: parentId)
    }

    static func preference(id: String, name: String, key: String, kind: PersistentSurfaceKind = .preferenceKey, notes: String? = nil) -> PersistentSurfaceNode {
        node(id: id, kind: kind, name: name, key: key, storageClass: "nativeAppData", notes: notes)
    }

    private static func node(
        id: String,
        kind: PersistentSurfaceKind,
        name: String,
        path: String? = nil,
        key: String? = nil,
        storageClass: String,
        canonicality: String = "hostOnly",
        privacy: String = "userData",
        lifecycle: String = "durable",
        parentId: String? = nil,
        databaseId: String? = nil,
        dataType: String? = nil,
        nullable: Bool? = nil,
        notes: String? = nil,
        warnings: [String]? = nil
    ) -> PersistentSurfaceNode {
        PersistentSurfaceNode(
            id: id,
            kind: kind,
            owner: "clawix",
            repo: "Clawix",
            project: "macos",
            language: "swift",
            name: name,
            path: path,
            key: key,
            storageClass: storageClass,
            canonicality: canonicality,
            privacy: privacy,
            lifecycle: lifecycle,
            parentId: parentId,
            databaseId: databaseId,
            dataType: dataType,
            nullable: nullable,
            notes: notes,
            warnings: warnings
        )
    }
}

enum ClawixPersistentSurfaceRegistry {
    static let version = 1
    static let localDatabaseId = "clawix.database.local"

    static var manifest: PersistentSurfaceManifest {
        PersistentSurfaceManifest(version: version, nodes: nodes)
    }

    static var nodes: [PersistentSurfaceNode] {
        [
            ClawixPersistentSurface.root(
                id: "clawix.applicationSupport",
                name: "Clawix Application Support",
                path: "~/Library/Application Support/Clawix"
            ),
            ClawixPersistentSurface.root(
                id: "clawix.home",
                name: "Clawix home",
                path: "~/.clawix",
                storageClass: "hostOperational"
            ),
            ClawixPersistentSurface.database(
                id: localDatabaseId,
                name: "Clawix local database",
                path: "~/Library/Application Support/Clawix/clawix.sqlite",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.dictationAudio",
                name: "Dictation audio",
                path: "~/Library/Application Support/Clawix/dictation-audio",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.dictationAudioDebug",
                name: "Dictation audio debug",
                path: "~/Library/Application Support/Clawix/dictation-audio-debug",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.bridgeState",
                name: "Bridge state",
                path: "~/.clawix/state",
                parentId: "clawix.home",
                storageClass: "hostOperational"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.bridgeBin",
                name: "Bridge binaries",
                path: "~/.clawix/bin",
                parentId: "clawix.home",
                storageClass: "hostOperational"
            ),
            ClawixPersistentSurface.preference(
                id: "clawix.prefs.sidebar.viewMode",
                name: "Sidebar view mode",
                key: "SidebarViewMode",
                kind: .appStorageKey
            ),
            ClawixPersistentSurface.preference(
                id: "clawix.prefs.sidebar.projectSortMode",
                name: "Sidebar project sort mode",
                key: "ProjectSortMode",
                kind: .appStorageKey
            ),
            ClawixPersistentSurface.preference(
                id: "clawix.prefs.feed.displayMode",
                name: "Feed display mode",
                key: "clawix.feed.displayMode",
                kind: .appStorageKey
            ),
        ] + databaseSurfaceNodes
    }

    private static var databaseSurfaceNodes: [PersistentSurfaceNode] {
        let tables: [(String, [(String, String, Bool)], [String])] = [
            ("projects", [("id", "TEXT", false), ("name", "TEXT", false), ("path", "TEXT", false), ("created_at", "INTEGER", false)], ["projects_path_idx"]),
            ("pinned_threads", [("thread_id", "TEXT", false), ("sort_order", "INTEGER", false), ("pinned_at", "INTEGER", false)], ["pinned_threads_order_idx"]),
            ("chat_project_overrides", [("thread_id", "TEXT", false), ("project_path", "TEXT", false)], []),
            ("projectless_threads", [("thread_id", "TEXT", false)], []),
            ("session_titles", [("thread_id", "TEXT", false), ("title", "TEXT", false), ("updated_at", "INTEGER", false), ("source", "TEXT", false)], []),
            ("meta", [("key", "TEXT", false), ("value", "TEXT", false)], []),
            ("local_archives", [("thread_id", "TEXT", false), ("archived_at", "INTEGER", false)], ["local_archives_archived_at_idx"]),
            ("hidden_codex_roots", [("path", "TEXT", false), ("hidden_at", "INTEGER", false)], ["hidden_codex_roots_hidden_at_idx"]),
            ("sidebar_snapshot", [("thread_id", "TEXT", false), ("chat_uuid", "TEXT", false), ("title", "TEXT", false), ("cwd", "TEXT", true), ("project_path", "TEXT", true), ("updated_at", "INTEGER", false), ("archived", "INTEGER", false), ("pinned", "INTEGER", false), ("captured_at", "INTEGER", false)], ["sidebar_snapshot_order_idx"]),
            ("sidebar_snapshot_project", [("thread_id", "TEXT", false), ("chat_uuid", "TEXT", false), ("title", "TEXT", false), ("cwd", "TEXT", true), ("project_path", "TEXT", false), ("updated_at", "INTEGER", false), ("archived", "INTEGER", false), ("pinned", "INTEGER", false), ("captured_at", "INTEGER", false)], ["sidebar_snapshot_project_path_idx"]),
            ("project_sort_order", [("project_id", "TEXT", false), ("sort_order", "INTEGER", false)], ["project_sort_order_idx"]),
            ("dictation_transcript", [("id", "TEXT", false), ("timestamp", "INTEGER", false), ("original_text", "TEXT", false), ("enhanced_text", "TEXT", true), ("model_used", "TEXT", true), ("language", "TEXT", true), ("duration_seconds", "REAL", false), ("audio_file_path", "TEXT", true), ("power_mode_id", "TEXT", true), ("word_count", "INTEGER", false), ("transcription_ms", "INTEGER", false), ("enhancement_ms", "INTEGER", false), ("enhancement_provider", "TEXT", true), ("cost_usd", "REAL", false)], ["dictation_transcript_timestamp_idx"]),
            ("terminal_tabs", [("id", "TEXT", false), ("chat_id", "TEXT", false), ("label", "TEXT", false), ("initial_cwd", "TEXT", false), ("layout_json", "TEXT", false), ("focused_leaf", "TEXT", true), ("position", "INTEGER", false), ("created_at", "INTEGER", false)], ["terminal_tabs_chat_position_idx"]),
        ]

        return tables.flatMap { tableName, columns, indexes in
            let table = ClawixPersistentSurface.table(tableName, databaseId: localDatabaseId)
            return [table]
                + columns.map { name, type, nullable in
                    ClawixPersistentSurface.column(name, tableId: table.id, databaseId: localDatabaseId, dataType: type, nullable: nullable)
                }
                + indexes.map { ClawixPersistentSurface.index($0, tableId: table.id, databaseId: localDatabaseId) }
        }
    }
}
