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
    case browserStorageKey
    case envOverride
    case cache
    case fixture
    case persistentTemp
    case legacyPath
    case externalReadOnlySource
    case apiRoute
    case apiMethod
    case apiParameter
    case webhook
    case webhookEvent
    case eventTopic
    case queueTopic
    case jsonSchema
    case jsonField
    case enumValue
    case errorCode
    case cliCommand
    case cliFlag
    case cliOutputField
    case `protocol`
    case protocolFrame
    case protocolField
    case idNamespace
    case idPrefix
    case deepLink
    case hostname
    case port
    case externalDependency
    case externalMapping
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
    var surfaceClass: String?
    var stability: String?
    var direction: String?
    var version: String?
    var value: String?
    var method: String?
    var route: String?
    var schemaId: String?
    var fieldPath: String?
    var enumType: String?
    var idPattern: String?
    var externalProvider: String?
    var replacement: String?
    var introducedIn: String?
    var deprecatedIn: String?
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

    static func legacyPath(id: String, name: String, path: String, warnings: [String]) -> PersistentSurfaceNode {
        node(id: id, kind: .legacyPath, name: name, path: path, storageClass: "workspace", canonicality: "legacyReadOnly", lifecycle: "legacy", warnings: warnings)
    }

    static func contract(
        id: String,
        kind: PersistentSurfaceKind,
        name: String,
        parentId: String? = nil,
        project: String = "core",
        surfaceClass: String,
        value: String? = nil,
        method: String? = nil,
        route: String? = nil,
        key: String? = nil,
        fieldPath: String? = nil,
        schemaId: String? = nil,
        enumType: String? = nil,
        version: String? = nil,
        direction: String = "bidirectional",
        notes: String? = nil
    ) -> PersistentSurfaceNode {
        node(
            id: id,
            kind: kind,
            name: name,
            key: key,
            storageClass: "external",
            canonicality: "hostOnly",
            privacy: "public",
            lifecycle: "durable",
            parentId: parentId,
            project: project,
            surfaceClass: surfaceClass,
            stability: "v1",
            direction: direction,
            version: version,
            value: value,
            method: method,
            route: route,
            schemaId: schemaId,
            fieldPath: fieldPath,
            enumType: enumType,
            notes: notes
        )
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
        project: String = "macos",
        databaseId: String? = nil,
        surfaceClass: String? = nil,
        stability: String? = nil,
        direction: String? = nil,
        version: String? = nil,
        value: String? = nil,
        method: String? = nil,
        route: String? = nil,
        schemaId: String? = nil,
        fieldPath: String? = nil,
        enumType: String? = nil,
        idPattern: String? = nil,
        externalProvider: String? = nil,
        replacement: String? = nil,
        introducedIn: String? = nil,
        deprecatedIn: String? = nil,
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
            project: project,
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
            surfaceClass: surfaceClass,
            stability: stability,
            direction: direction,
            version: version,
            value: value,
            method: method,
            route: route,
            schemaId: schemaId,
            fieldPath: fieldPath,
            enumType: enumType,
            idPattern: idPattern,
            externalProvider: externalProvider,
            replacement: replacement,
            introducedIn: introducedIn,
            deprecatedIn: deprecatedIn,
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
            ClawixPersistentSurface.legacyPath(
                id: "clawix.legacy.workspace.clawjs",
                name: "Legacy ClawJS workspace root",
                path: ClawixPersistentSurfacePaths.components.legacyClawWorkspace,
                warnings: ["Read only for stale token cleanup and compatibility checks."]
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
                id: "clawix.audioCatalog",
                name: "Audio catalog files",
                path: "~/Library/Application Support/Clawix/audio",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.file(
                id: "clawix.audioCatalogMetadata",
                name: "Audio catalog metadata",
                path: "~/Library/Application Support/Clawix/audio-meta.json",
                parentId: "clawix.applicationSupport"
            ),
            ClawixPersistentSurface.folder(
                id: "clawix.meshHome",
                name: "Remote mesh home",
                path: "~/.clawix/mesh",
                parentId: "clawix.home"
            ),
            ClawixPersistentSurface.database(
                id: "clawix.secretsTemporaryVaultPattern",
                name: "Temporary secrets vault database pattern",
                path: "<tmp>/clawix-vault-<uuid>.sqlite",
                parentId: nil
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
        ] + contractSurfaceNodes + preferenceSurfaceNodes + databaseSurfaceNodes
    }

    private static var contractSurfaceNodes: [PersistentSurfaceNode] {
        let bridgeProtocol = ClawixPersistentSurface.contract(
            id: "clawix.protocol.bridge",
            kind: .`protocol`,
            name: "Clawix bridge protocol",
            parentId: "claw.contracts.protocol",
            project: "core",
            surfaceClass: "protocol",
            value: "clawix-bridge",
            version: "8",
            direction: "bidirectional",
            notes: "Shared JSON frame protocol consumed by macOS, iOS, Android, Linux, Windows and web clients."
        )
        let bridgeFields = ["schemaVersion", "type", "clientKind", "platform", "sessionId", "threadId", "requestId"].map { field in
            ClawixPersistentSurface.contract(
                id: "clawix.protocol.bridge.field.\(field)",
                kind: .protocolField,
                name: field,
                parentId: bridgeProtocol.id,
                project: "core",
                surfaceClass: "protocol",
                key: field,
                fieldPath: field,
                schemaId: "clawix-bridge",
                direction: "bidirectional"
            )
        }
        let frameTypes = [
            "versionMismatch",
            "sessionsSnapshot",
            "openSession",
            "sendMessage",
            "sessionDelta",
            "skillsSnapshot",
            "remoteJobSnapshot",
        ].map { type in
            ClawixPersistentSurface.contract(
                id: "clawix.protocol.bridge.frame.\(type)",
                kind: .protocolFrame,
                name: type,
                parentId: bridgeProtocol.id,
                project: "core",
                surfaceClass: "protocol",
                value: type,
                schemaId: "clawix-bridge",
                direction: "bidirectional"
            )
        }
        let apiRoutes: [(String, String, String, String)] = [
            ("mesh", "GET", "/v1/mesh/identity", "Mesh identity"),
            ("mesh", "GET", "/v1/mesh/peers", "Mesh peers"),
            ("mesh", "GET", "/v1/mesh/workspaces", "Mesh workspaces"),
            ("mesh", "GET", "/v1/mesh/jobs/{jobId}", "Mesh job output"),
            ("mesh", "POST", "/v1/mesh/workspaces", "Create mesh workspace"),
            ("mesh", "POST", "/v1/mesh/peers", "Register mesh peer"),
            ("mesh", "POST", "/v1/mesh/link", "Link mesh peer"),
            ("mesh", "POST", "/v1/mesh/pair", "Pair mesh peer"),
            ("mesh", "POST", "/v1/mesh/jobs", "Start mesh job"),
            ("mesh", "POST", "/v1/mesh/jobs/cancel", "Cancel mesh job"),
            ("mesh", "POST", "/v1/mesh/jobs/events", "Read mesh job events"),
            ("audio", "GET", "/v1/audio", "List audio catalog"),
            ("audio", "GET", "/v1/audio/{audioId}", "Read audio catalog item"),
            ("audio", "GET", "/v1/audio/{audioId}/bytes", "Read audio bytes"),
            ("audio", "POST", "/v1/audio", "Register audio"),
            ("audio", "POST", "/v1/audio/{audioId}/transcripts", "Attach audio transcript"),
            ("audio", "DELETE", "/v1/audio/{audioId}", "Delete audio catalog item"),
        ]
        let routeNodes = apiRoutes.map { domain, method, route, name in
            let routeId = String(route.dropFirst(4))
                .replacingOccurrences(of: "/", with: ".")
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
            return ClawixPersistentSurface.contract(
                id: "clawix.api.\(domain).\(method.lowercased()).\(routeId)",
                kind: .apiRoute,
                name: name,
                parentId: "claw.contracts.api",
                project: "core",
                surfaceClass: "api",
                value: "\(method) \(route)",
                method: method,
                route: route,
                direction: "inbound"
            )
        }
        let remoteJobEvents = ["accepted", "threadStarted", "turnStarted", "delta", "completed", "failed", "cancelled"].map { event in
            ClawixPersistentSurface.contract(
                id: "clawix.event.remoteJob.\(event)",
                kind: .eventTopic,
                name: event,
                parentId: "claw.contracts.events",
                project: "core",
                surfaceClass: "event",
                value: event,
                direction: "generated"
            )
        }
        let webStorage = ClawixPersistentSurface.contract(
            id: "clawix.web.storage.currentRoute",
            kind: .browserStorageKey,
            name: "Current web route",
            parentId: "claw.contracts.schemas",
            project: "web",
            surfaceClass: "persistent",
            value: "ui.route",
            key: "ui.route",
            direction: "local"
        )
        let deepLinks = ["clawix://auth/callback/{provider}", "clawix://pair/{token}", "clawix://session/{sessionId}", "clawix://settings/{section}"].map { link in
            ClawixPersistentSurface.contract(
                id: "clawix.deeplink.\(link.replacingOccurrences(of: "://", with: ".").replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))",
                kind: .deepLink,
                name: link,
                parentId: "claw.contracts.api",
                project: "core",
                surfaceClass: "config",
                value: link,
                direction: "inbound"
            )
        }
        return [bridgeProtocol] + bridgeFields + frameTypes + routeNodes + remoteJobEvents + [webStorage] + deepLinks
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
            ("clawix.prefs.dictation.activeModel", "Dictation active model", ClawixPersistentSurfaceKeys.dictationActiveModel, PersistentSurfaceKind.preferenceKey),
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
            ("clawix.prefs.publishing.workspace", "Publishing workspace", PublishingManager.workspaceKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.git.commitInstructions", "Git commit instructions", ClawixPersistentSurfaceKeys.gitCommitInstructions, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.featureFlags.beta", "Beta feature flag", ClawixPersistentSurfaceKeys.featureFlagsBeta, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.featureFlags.experimental", "Experimental feature flag", ClawixPersistentSurfaceKeys.featureFlagsExperimental, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.life.enabledVerticals", "Life enabled verticals", ClawixPersistentSurfaceKeys.lifeEnabledVerticals, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.life.hiddenVerticals", "Life hidden verticals", ClawixPersistentSurfaceKeys.lifeHiddenVerticals, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.relay.refresh", "Relay refresh token pattern", ClawixPersistentSurfaceKeys.relayRefreshPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.browser.websiteApproval", "Browser website approval", BrowserPermissionPolicy.approvalStorageKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.browser.blockedDomains", "Browser blocked domains", BrowserPermissionPolicy.blockedDomainsStorageKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.browser.allowedDomains", "Browser allowed domains", BrowserPermissionPolicy.allowedDomainsStorageKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.mesh.httpPort", "Mesh HTTP port override", MeshClient.httpPortDefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.mesh.remoteWorkspaces", "Mesh remote workspaces", MeshStore.workspacesDefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.localModels.defaultModel", "Local models default model", LocalModelsService.defaultModelKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.localModels.keepAlive", "Local models keep alive", LocalModelsService.keepAliveKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.localModels.contextLength", "Local models context length", LocalModelsService.contextLengthKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.updater.pendingBuild", "Pending update build", UpdaterController.pendingBuildKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.updater.pendingDisplay", "Pending update display", UpdaterController.pendingDisplayKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.quickAsk.slashCommands", "Quick Ask custom slash commands", QuickAskSlashCommandsStore.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.quickAsk.mentionPrompts", "Quick Ask custom mention prompts", QuickAskMentionsStore.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.quickAsk.hotkey", "Quick Ask hotkey", QuickAskHotkeyManager.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.quickAsk.clipboardLastSeen", "Quick Ask clipboard last seen", QuickAskClipboardSniffer.lastSeenKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.quickAsk.clipboardLastSeenAt", "Quick Ask clipboard last seen at", QuickAskClipboardSniffer.lastSeenAtKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.skills.activeByScope", "Active skills by scope", SkillsStore.activeKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.skills.userCatalog", "User skills catalog", SkillsStore.userCatalogKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.provider.featureAccount", "Provider account selection pattern", ClawixPersistentSurfaceKeys.featureProviderAccountPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.provider.featureModel", "Provider model selection pattern", ClawixPersistentSurfaceKeys.featureProviderModelPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.provider.enabled", "Provider enabled pattern", ClawixPersistentSurfaceKeys.providerEnabledPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.secrets.deviceId", "Secrets device id", SecretsPaths.deviceIdKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.customBaseUrl", "Custom transcription base URL", ClawixPersistentSurfaceKeys.dictationCustomBaseURL, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.customModel", "Custom transcription model", ClawixPersistentSurfaceKeys.dictationCustomModel, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.injectText", "Dictation inject text", DictationCoordinator.injectDefaultsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.restoreClipboard", "Dictation restore clipboard", DictationCoordinator.restoreClipboardDefaultsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.autoEnter", "Dictation auto enter", DictationCoordinator.autoEnterDefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.autoSendKey", "Dictation auto send key", DictationCoordinator.autoSendKeyDefaultsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.language", "Dictation language", DictationCoordinator.languageDefaultsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.restoreClipboardDelayMs", "Dictation restore clipboard delay", DictationCoordinator.restoreClipboardDelayMsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.addSpaceBeforePaste", "Dictation add space before paste", DictationCoordinator.addSpaceBeforeKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.autoFormatParagraphs", "Dictation auto-format paragraphs", DictationCoordinator.autoFormatParagraphsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.prewarmOnLaunch", "Dictation prewarm on launch", DictationCoordinator.prewarmOnLaunchKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.vadEnabled", "Dictation VAD enabled", DictationCoordinator.vadEnabledKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.backend", "Dictation transcription backend", DictationCoordinator.backendKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.livePreview", "Dictation live preview", DictationCoordinator.livePreviewEnabledKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.soundFeedback", "Dictation sound feedback", SoundManager.defaultsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.playStartSound", "Dictation play start sound", SoundManager.playStartKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.playStopSound", "Dictation play stop sound", SoundManager.playStopKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.customStartSound", "Dictation custom start sound", SoundManager.customStartURLKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.customStopSound", "Dictation custom stop sound", SoundManager.customStopURLKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.muteAudio", "Dictation mute audio", MediaController.enabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.muteResumeDelay", "Dictation mute resume delay", MediaController.resumeDelayKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.pauseMedia", "Dictation pause media", PlaybackController.enabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.pauseResumeDelay", "Dictation pause resume delay", PlaybackController.resumeDelayKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.fillerWordsEnabled", "Dictation filler words enabled", FillerWordsManager.enabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.fillerWordsList", "Dictation filler words list", FillerWordsManager.listKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.cleanupTranscriptsEnabled", "Dictation cleanup transcripts enabled", CleanupScheduler.transcriptsEnabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.cleanupTranscriptsTTL", "Dictation cleanup transcripts TTL", CleanupScheduler.transcriptsTTLKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.cleanupAudioFilesEnabled", "Dictation cleanup audio files enabled", CleanupScheduler.audioFilesEnabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.cleanupAudioFilesTTL", "Dictation cleanup audio files TTL", CleanupScheduler.audioFilesTTLKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.hotkeyMode", "Dictation hotkey mode", HotkeyManager.modeDefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.hotkeyTrigger", "Dictation hotkey trigger", HotkeyManager.triggerDefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.hotkey2Mode", "Dictation second hotkey mode", HotkeyManager.mode2DefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.hotkey2Trigger", "Dictation second hotkey trigger", HotkeyManager.trigger2DefaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.vocabulary", "Dictation vocabulary", VocabularyManager.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.whisperPrompts", "Dictation Whisper prompts", WhisperPromptStore.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.powerModeEnabled", "Dictation power mode enabled", PowerModeManager.enabledKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.powerModeConfigs", "Dictation power mode configs", PowerModeManager.configsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.microphoneMode", "Dictation microphone mode", MicrophonePreferences.modeKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.microphonePreferred", "Dictation preferred microphones", MicrophonePreferences.preferredKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.onboardingCompleted", "Dictation onboarding completed", DictationOnboardingTrigger.completedKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.recorderStyle", "Dictation recorder style", DictationOverlay.styleKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.accessibilityRequested", "Dictation accessibility requested", DictationPermissions.hasRequestedAccessibilityKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.replacements", "Dictation replacements", DictationReplacementStore.defaultsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.enhancement.enabled", "Enhancement enabled", EnhancementSettings.enabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.provider", "Enhancement provider", EnhancementSettings.providerKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.activePrompt", "Enhancement active prompt", EnhancementSettings.activePromptKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.enhancement.skipShortEnabled", "Enhancement skip short enabled", EnhancementSettings.skipShortEnabledKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.skipShortMinWords", "Enhancement skip short minimum words", EnhancementSettings.skipShortMinWordsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.timeoutSeconds", "Enhancement timeout seconds", EnhancementSettings.timeoutSecondsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.timeoutPolicy", "Enhancement timeout policy", EnhancementSettings.timeoutPolicyKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.clipboardContext", "Enhancement clipboard context", EnhancementSettings.clipboardContextKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.screenContext", "Enhancement screen context", EnhancementSettings.screenContextKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.dictation.enhancement.customPrompts", "Enhancement custom prompts", PromptLibrary.customPromptsKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.enhancement.model", "Enhancement model pattern", ClawixPersistentSurfaceKeys.enhancementModelPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.enhancement.baseUrl", "Enhancement base URL pattern", ClawixPersistentSurfaceKeys.enhancementBaseURLPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.cloudModel", "Cloud transcription model pattern", ClawixPersistentSurfaceKeys.cloudTranscriptionModelPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.cloudBaseUrl", "Cloud transcription base URL pattern", ClawixPersistentSurfaceKeys.cloudTranscriptionBaseURLPattern, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.screenTools.exportDirectory", "Screen tools export directory", ScreenToolSettings.exportDirectoryKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.afterCaptureAction", "Screen tools after capture action", ScreenToolSettings.afterCaptureActionKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.imageFormat", "Screen tools image format", ScreenToolSettings.imageFormatKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.selfTimerSeconds", "Screen tools self timer", ScreenToolSettings.selfTimerSecondsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.playSounds", "Screen tools play sounds", ScreenToolSettings.playSoundsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.includeCursor", "Screen tools include cursor", ScreenToolSettings.includeCursorKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.captureWindowShadow", "Screen tools capture window shadow", ScreenToolSettings.captureWindowShadowKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.scaleRetinaScreenshots", "Screen tools scale retina screenshots", ScreenToolSettings.scaleRetinaScreenshotsTo1xKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.convertScreenshotsToSRGB", "Screen tools convert screenshots to sRGB", ScreenToolSettings.convertScreenshotsToSRGBKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.addOnePixelBorder", "Screen tools one-pixel border", ScreenToolSettings.addOnePixelBorderKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.freezeScreenOnCapture", "Screen tools freeze screen", ScreenToolSettings.freezeScreenOnCaptureKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.backgroundPreset", "Screen tools background preset", ScreenToolSettings.backgroundPresetKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.crosshairMode", "Screen tools crosshair mode", ScreenToolSettings.crosshairModeKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.showCrosshairMagnifier", "Screen tools crosshair magnifier", ScreenToolSettings.showCrosshairMagnifierKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.showRecordingCursor", "Screen tools recording cursor", ScreenToolSettings.showRecordingCursorKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.showRecordingControls", "Screen tools recording controls", ScreenToolSettings.showRecordingControlsKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.highlightRecordingClicks", "Screen tools recording click highlights", ScreenToolSettings.highlightRecordingClicksKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.recordRecordingAudio", "Screen tools record audio", ScreenToolSettings.recordRecordingAudioKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.displayRecordingTime", "Screen tools display recording time", ScreenToolSettings.displayRecordingTimeKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.showRecordingCountdown", "Screen tools recording countdown", ScreenToolSettings.showRecordingCountdownKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.recordingMaxResolution", "Screen tools recording max resolution", ScreenToolSettings.recordingMaxResolutionKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.recordingVideoFPS", "Screen tools recording FPS", ScreenToolSettings.recordingVideoFPSKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.scaleRetinaRecordings", "Screen tools scale retina recordings", ScreenToolSettings.scaleRetinaRecordingsTo1xKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.recordRecordingAudioInMono", "Screen tools mono recording audio", ScreenToolSettings.recordRecordingAudioInMonoKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.openRecordingEditor", "Screen tools open recording editor", ScreenToolSettings.openRecordingEditorAfterRecordingKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.keepTextLineBreaks", "Screen tools keep text line breaks", ScreenToolSettings.keepTextLineBreaksKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.autoDetectTextLanguage", "Screen tools auto detect text language", ScreenToolSettings.autoDetectTextLanguageKey, PersistentSurfaceKind.appStorageKey),
            ("clawix.prefs.screenTools.previousAreaRect", "Screen tools previous area rect", ScreenToolSettings.previousAreaRectKey, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.useAppleScriptPaste", "AppleScript paste preference", ClawixPersistentSurfaceKeys.useAppleScriptPaste, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.useAppleScriptPasteLegacy", "Legacy AppleScript paste preference", ClawixPersistentSurfaceKeys.useAppleScriptPasteLegacy, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.bearer", "Bridge bearer token reference", ClawixPersistentSurfaceKeys.bridgeBearer, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.shortCode", "Bridge short code", ClawixPersistentSurfaceKeys.bridgeShortCode, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.coordinatorURL", "Bridge coordinator URL", ClawixPersistentSurfaceKeys.bridgeCoordinatorURL, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.irohNodeID", "Bridge Iroh node id", ClawixPersistentSurfaceKeys.bridgeIrohNodeID, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.bridge.host", "Bridge host override", ClawixPersistentSurfaceKeys.bridgeHost, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.binary.path", "Clawix binary path", ClawixPersistentSurfaceKeys.binaryPath, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.backgroundBridge.wasEnabled", "Background bridge was enabled", ClawixPersistentSurfaceKeys.backgroundBridgeWasEnabled, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.appleLanguages", "Apple languages", ClawixPersistentSurfaceKeys.appleLanguages, PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.legacyKeychainPurged", "Legacy keychain purge gate", "clawix.legacyKeychainPurged.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.database.filterStates", "Database filter states", "clawix.database.filterStates.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationInputPath", "Database workbench operation input path", "clawix.databaseWorkbench.operationInputPath.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationOutputPath", "Database workbench operation output path", "clawix.databaseWorkbench.operationOutputPath.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationObjectName", "Database workbench operation object name", "clawix.databaseWorkbench.operationObjectName.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationSearchTerm", "Database workbench operation search term", "clawix.databaseWorkbench.operationSearchTerm.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationPluginScript", "Database workbench operation plugin script", "clawix.databaseWorkbench.operationPluginScript.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.operationRecords", "Database workbench operation records", "clawix.databaseWorkbench.operationRecords.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.activeSQL", "Database workbench active SQL", "clawix.databaseWorkbench.activeSQL.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.selectedProfile", "Database workbench selected profile", "clawix.databaseWorkbench.selectedProfile.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.queryDrafts", "Database workbench query drafts", "clawix.databaseWorkbench.queryDrafts.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.history", "Database workbench history", "clawix.databaseWorkbench.history.v1", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.databaseWorkbench.completeKey", "Database workbench completion key", "clawix.databaseWorkbench.completeKey", PersistentSurfaceKind.preferenceKey),
            ("clawix.prefs.dictation.hotkeyMigratedV2", "Dictation hotkey migrated v2", HotkeyManager.migratedV2Key, PersistentSurfaceKind.preferenceKey),
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
    static let publicApiPrefix = "/v1"
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
    static let gitCommitInstructions = "clawix.git.commitInstructions"
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
    static let bridgeShortCode = "ClawixBridge.ShortCode.v1"
    static let bridgeCoordinatorURL = "ClawixBridge.Coordinator.URL.v1"
    static let bridgeIrohNodeID = "ClawixBridge.Iroh.NodeID.v1"
    static let bridgeHost = "ClawixBridge.Host.v1"
    static let dictationActiveModel = "dictation.activeModel"
    static let featureProviderAccountPattern = "feature.<feature>.providerAccountId"
    static let featureProviderModelPattern = "feature.<feature>.modelId"
    static let providerEnabledPattern = "provider.<provider>.enabled"
    static let enhancementModelPattern = "dictation.enhancement.model.<provider>"
    static let enhancementBaseURLPattern = "dictation.enhancement.baseURL.<provider>"
    static let cloudTranscriptionModelPattern = "dictation.transcription.model.<provider>"
    static let cloudTranscriptionBaseURLPattern = "dictation.transcription.baseURL.<provider>"
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
        static let legacyClawWorkspace = ".clawjs"
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
