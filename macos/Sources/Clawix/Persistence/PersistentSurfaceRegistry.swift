import Foundation
import GRDB

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

    static func file(id: String, name: String, path: String, parentId: String? = nil, storageClass: String = "nativeAppData") -> PersistentSurfaceNode {
        node(id: id, kind: .file, name: name, path: path, storageClass: storageClass, parentId: parentId)
    }

    static func cache(id: String, name: String, path: String, parentId: String? = nil) -> PersistentSurfaceNode {
        node(id: id, kind: .cache, name: name, path: path, storageClass: "cache", canonicality: "cache", lifecycle: "rebuildable", parentId: parentId)
    }

    static func persistentTemp(id: String, name: String, path: String, parentId: String? = nil) -> PersistentSurfaceNode {
        node(id: id, kind: .persistentTemp, name: name, path: path, storageClass: "nativeAppData", canonicality: "generated", parentId: parentId)
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
                id: "clawix.apps",
                name: "Apps",
                path: "~/Library/Application Support/Clawix/Apps",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.design",
                name: "Design",
                path: "~/Library/Application Support/Clawix/Design",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.clawjs",
                name: "Embedded ClawJS",
                path: "~/Library/Application Support/Clawix/clawjs",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.secrets",
                name: "Secrets",
                path: "~/Library/Application Support/Clawix/secrets",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.localModels",
                name: "Local models",
                path: "~/Library/Application Support/Clawix/local-models",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.dictationSounds",
                name: "Dictation sounds",
                path: "~/Library/Application Support/Clawix/dictation-sounds",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.cache(
                id: "clawix.captures",
                name: "Quick Ask captures",
                path: "~/Library/Caches/Clawix-Captures"
            ),
            ClawixPersistentSurface.cache(
                id: "clawix.favicons",
                name: "Browser favicons",
                path: "~/Library/Caches/Clawix/Favicons"
            ),
            ClawixPersistentSurface.cache(
                id: "clawix.localModelsCache",
                name: "Local models cache",
                path: "~/Library/Caches/Clawix/local-models"
            ),
            ClawixPersistentSurface.cache(
                id: "clawix.devCache",
                name: "Development cache",
                path: "~/Library/Caches/Clawix-Dev"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.logs",
                name: "Logs",
                path: "~/Library/Logs/Clawix",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.bridgeState",
                name: "Bridge state",
                path: "~/.clawix/state",
                parentId: "clawix.home",
                storageClass: "hostOperational"
            ),
            ClawixPersistentSurface.file(
                id: "clawix.bridgeStatus",
                name: "Bridge status",
                path: "~/.clawix/state/bridge-status.json",
                parentId: "clawix.bridgeState",
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
                key: ClawixPersistentSurfaceKeys.sidebarViewMode,
                kind: .appStorageKey
            ),
            ClawixPersistentSurface.preference(
                id: "clawix.prefs.sidebar.projectSortMode",
                name: "Sidebar project sort mode",
                key: ClawixPersistentSurfaceKeys.projectSortMode,
                kind: .appStorageKey
            ),
            ClawixPersistentSurface.preference(
                id: "clawix.prefs.feed.displayMode",
                name: "Feed display mode",
                key: ClawixPersistentSurfaceKeys.feedDisplayMode,
                kind: .appStorageKey
            ),
        ] + preferenceSurfaceNodes + databaseSurfaceNodes
    }

    private static var preferenceSurfaceNodes: [PersistentSurfaceNode] {
        [
            ("clawix.prefs.sidebar.pinnedExpanded", "Pinned section expanded", ClawixPersistentSurfaceKeys.sidebarPinnedExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.chronoExpanded", "Chronological section expanded", ClawixPersistentSurfaceKeys.sidebarChronoExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.noProjectExpanded", "No project section expanded", ClawixPersistentSurfaceKeys.sidebarNoProjectExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.projectsExpanded", "Projects section expanded", ClawixPersistentSurfaceKeys.sidebarProjectsExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.archivedExpanded", "Archived section expanded", ClawixPersistentSurfaceKeys.sidebarArchivedExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.toolsExpanded", "Tools section expanded", ClawixPersistentSurfaceKeys.sidebarToolsExpanded, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.sidebar.pinnedFilterDisabled", "Sidebar pinned filter disabled", ClawixPersistentSurfaceKeys.sidebarPinnedFilterDisabled, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.sidebar.chronoFilterDisabled", "Sidebar chrono filter disabled", ClawixPersistentSurfaceKeys.sidebarChronoFilterDisabled, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.sidebar.appsFeatureEnabled", "Apps feature enabled", ClawixPersistentSurfaceKeys.appsFeatureEnabled, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.sidebar.toolsOrder", "Sidebar tools order", ClawixPersistentSurfaceKeys.sidebarToolsOrder, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.sidebar.toolsHidden", "Sidebar tools hidden", ClawixPersistentSurfaceKeys.sidebarToolsHidden, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.terminal.panelOpen", "Terminal panel open", ClawixPersistentSurfaceKeys.terminalPanelOpen, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.terminal.panelHeight", "Terminal panel height", ClawixPersistentSurfaceKeys.terminalPanelHeight, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.apps.expanded", "Apps sidebar expanded", ClawixPersistentSurfaceKeys.sidebarAppsExpanded, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.apps.defaultInternetAllowed", "Apps default internet allowed", ClawixPersistentSurfaceKeys.appsDefaultInternetAllowed, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.apps.defaultCallAgent", "Apps default call agent", ClawixPersistentSurfaceKeys.appsDefaultCallAgent, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.design.expanded", "Design sidebar expanded", ClawixPersistentSurfaceKeys.sidebarDesignExpanded, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.life.expanded", "Life sidebar expanded", ClawixPersistentSurfaceKeys.sidebarLifeExpanded, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.content.leftSidebarWidth", "Left sidebar width", ClawixPersistentSurfaceKeys.leftSidebarWidth, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.content.rightSidebarWidth", "Right sidebar width", ClawixPersistentSurfaceKeys.rightSidebarWidth, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.secrets.advancedExpanded", "Secrets advanced expanded", ClawixPersistentSurfaceKeys.secretsAdvancedExpanded, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.advancedExpanded", "Dictation advanced expanded", ClawixPersistentSurfaceKeys.dictationAdvancedExpanded, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.remote.coordinatorUrl", "Remote coordinator URL", ClawixPersistentSurfaceKeys.remoteCoordinatorUrl, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.remote.email", "Remote email", ClawixPersistentSurfaceKeys.remoteEmail, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.remote.deviceId", "Remote device id", ClawixPersistentSurfaceKeys.remoteDeviceId, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.remote.tenantId", "Remote tenant id", ClawixPersistentSurfaceKeys.remoteTenantId, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.browser.historyApproval", "Browser history approval", ClawixPersistentSurfaceKeys.browserHistoryApproval, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.settings.usageDisplayMode", "Usage display mode", ClawixPersistentSurfaceKeys.usageDisplayMode, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.skills.autoImport", "Skills auto import", ClawixPersistentSurfaceKeys.skillsAutoImport, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.index.catalogDisplayMode", "Index catalog display mode", ClawixPersistentSurfaceKeys.indexCatalogDisplayMode, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.iot.tab", "IoT tab", ClawixPersistentSurfaceKeys.iotTab, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.publishing.calendarMode", "Publishing calendar mode", ClawixPersistentSurfaceKeys.publishingCalendarMode, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.publishing.homeTab", "Publishing home tab", ClawixPersistentSurfaceKeys.publishingHomeTab, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.featureFlags.beta", "Beta feature flag", ClawixPersistentSurfaceKeys.featureFlagsBeta, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.featureFlags.experimental", "Experimental feature flag", ClawixPersistentSurfaceKeys.featureFlagsExperimental, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.life.enabledVerticals", "Life enabled verticals", ClawixPersistentSurfaceKeys.lifeEnabledVerticals, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.life.hiddenVerticals", "Life hidden verticals", ClawixPersistentSurfaceKeys.lifeHiddenVerticals, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.relay.refresh", "Relay refresh token pattern", ClawixPersistentSurfaceKeys.relayRefreshPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.customBaseUrl", "Custom transcription base URL", ClawixPersistentSurfaceKeys.dictationCustomBaseURL, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.customModel", "Custom transcription model", ClawixPersistentSurfaceKeys.dictationCustomModel, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.useAppleScriptPaste", "AppleScript paste preference", ClawixPersistentSurfaceKeys.useAppleScriptPaste, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.useAppleScriptPasteLegacy", "Legacy AppleScript paste preference", ClawixPersistentSurfaceKeys.useAppleScriptPasteLegacy, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.bearer", "Bridge bearer token reference", ClawixPersistentSurfaceKeys.bridgeBearer, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.binary.path", "Clawix binary path", ClawixPersistentSurfaceKeys.binaryPath, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.backgroundBridge.wasEnabled", "Background bridge was enabled", ClawixPersistentSurfaceKeys.backgroundBridgeWasEnabled, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.appleLanguages", "Apple languages", ClawixPersistentSurfaceKeys.appleLanguages, PersistentSurfaceKind.preferenceKey),
        ].map { id, name, key, kind in
            ClawixPersistentSurface.preference(id: id, name: name, key: key, kind: kind)
        }
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

enum ClawixPersistentSurfaceKeys {
    static let sidebarViewMode = "SidebarViewMode"
    static let projectSortMode = "ProjectSortMode"
    static let sidebarPinnedExpanded = "SidebarPinnedExpanded"
    static let sidebarChronoExpanded = "SidebarChronoExpanded"
    static let sidebarNoProjectExpanded = "SidebarNoProjectExpanded"
    static let sidebarProjectsExpanded = "SidebarProjectsExpanded"
    static let sidebarArchivedExpanded = "SidebarArchivedExpanded"
    static let sidebarToolsExpanded = "SidebarToolsExpanded"
    static let sidebarPinnedFilterDisabled = "SidebarPinnedFilterDisabled"
    static let sidebarChronoFilterDisabled = "SidebarChronoFilterDisabled"
    static let appsFeatureEnabled = "AppsFeatureEnabled"
    static let sidebarToolsOrder = "SidebarToolsOrder"
    static let sidebarToolsHidden = "SidebarToolsHidden"
    static let terminalPanelOpen = "TerminalPanelOpen"
    static let terminalPanelHeight = "TerminalPanelHeight"
    static let sidebarAppsExpanded = "SidebarAppsExpanded"
    static let appsDefaultInternetAllowed = "AppsDefaultInternetAllowed"
    static let appsDefaultCallAgent = "AppsDefaultCallAgent"
    static let sidebarDesignExpanded = "SidebarDesignExpanded"
    static let sidebarLifeExpanded = "SidebarLifeExpanded"
    static let leftSidebarWidth = "LeftSidebarWidth"
    static let rightSidebarWidth = "RightSidebarWidth"
    static let secretsAdvancedExpanded = "secrets.advancedExpanded"
    static let dictationAdvancedExpanded = "dictation.advancedExpanded"
    static let remoteCoordinatorUrl = "clawix.remote.coordinatorUrl"
    static let remoteEmail = "clawix.remote.email"
    static let remoteDeviceId = "clawix.remote.deviceId"
    static let remoteTenantId = "clawix.remote.tenantId"
    static let browserHistoryApproval = "clawix.browser.historyApproval"
    static let usageDisplayMode = "clawix.settings.usage.displayMode"
    static let skillsAutoImport = "ClawixSkillsAutoImport"
    static let indexCatalogDisplayMode = "clawix.index.catalog.displayMode"
    static let iotTab = "clawix.iot.tab"
    static let publishingCalendarMode = "clawix.publishing.calendarMode.v1"
    static let publishingHomeTab = "clawix.publishing.homeTab.v1"
    static let feedDisplayMode = "clawix.feed.displayMode"
    static let featureFlagsBeta = "FeatureFlags.beta"
    static let featureFlagsExperimental = "FeatureFlags.experimental"
    static let lifeEnabledVerticals = "LifeEnabledVerticals"
    static let lifeHiddenVerticals = "LifeHiddenVerticals"
    static let relayRefreshPrefix = "clawix.relay.refresh"
    static let relayRefreshPattern = "clawix.relay.refresh.<deviceId>"
    static func relayRefreshKey(for deviceId: String) -> String { "\(relayRefreshPrefix).\(deviceId)" }
    static let dictationCustomBaseURL = "dictation.transcription.baseURL.custom"
    static let dictationCustomModel = "dictation.transcription.model.custom"
    static let useAppleScriptPaste = "useAppleScriptPaste"
    static let useAppleScriptPasteLegacy = "UseAppleScriptPaste"
    static let bridgeDefaultsSuite = "clawix.bridge"
    static let bridgeBearer = "ClawixBridge.Bearer.v1"
    static let binaryPath = "ClawixBinaryPath"
    static let backgroundBridgeWasEnabled = "clawix.backgroundBridge.wasEnabled"
    static let appleLanguages = "AppleLanguages"
}

enum ClawixPersistentSurfacePaths {
    static func applicationSupportRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.clawix, isDirectory: true)
    }

    static func applicationSupportChild(_ child: String, isDirectory: Bool = true) throws -> URL {
        try applicationSupportRoot().appendingPathComponent(child, isDirectory: isDirectory)
    }

    static func homeChild(_ child: String, isDirectory: Bool = true) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(components.clawixHome, isDirectory: true)
            .appendingPathComponent(child, isDirectory: isDirectory)
    }

    static func logsRoot() throws -> URL {
        try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.logs, isDirectory: true)
            .appendingPathComponent(components.clawix, isDirectory: true)
    }

    static func cacheRoot() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(components.devCache, isDirectory: true)
    }

    static func picturesChild(_ child: String, isDirectory: Bool = true) -> URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(child, isDirectory: isDirectory)
    }

    enum components {
        static let clawix = "Clawix"
        static let clawixHome = ".clawix"
        static let clawWorkspace = ".claw"
        static let bridgeState = "state"
        static let workspace = "workspace"
        static let logs = "Logs"
        static let devCache = "Clawix-Dev"
        static let apps = "Apps"
        static let design = "Design"
        static let clawjs = "clawjs"
        static let secrets = "secrets"
        static let localModels = "local-models"
        static let favicons = "Favicons"
        static let dictationAudio = "dictation-audio"
        static let dictationAudioDebug = "dictation-audio-debug"
        static let dictationSounds = "dictation-sounds"
        static let captures = "Clawix-Captures"
        static let appStorageFile = ".clawix-storage.json"
        static let bundleName = "Clawix_Clawix.bundle"
        static let bridgeStatusFile = "bridge-status.json"
        static let sqlite = "clawix.sqlite"
        static let sqliteExtension = "sqlite"
        static let clawjsDatabase = "clawjs.sqlite"
        static let sessionsDatabase = "sessions.sqlite"
        static let indexDatabase = "index.sqlite"
        static let secretsDatabase = "secrets.sqlite"
        static let iotDatabase = "iot.sqlite"
        static let files = "files"
        static let blobs = "blobs"
        static let status = "status"
        static let sources = "Sources"
        static let helpers = "Helpers"
        static let bridged = "Bridged"
    }
}

enum ClawixRegisteredDatabaseQueue {
    static func open(path: String, configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try DatabaseQueue(path: path, configuration: configuration)
    }

    static func open(url: URL, configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try open(path: url.path, configuration: configuration)
    }
}
