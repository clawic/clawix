import XCTest
@testable import Clawix

final class PersistentSurfaceRegistryTests: XCTestCase {
    func testClawixPersistentSurfaceRegistryCoversLocalDatabaseAndPrefs() throws {
        let nodes = ClawixPersistentSurfaceRegistry.nodes

        XCTAssertTrue(nodes.contains { $0.id == "clawix.database.local" && $0.path == "~/Library/Application Support/Clawix/clawix.sqlite" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.database.local.table.projects" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.database.local.table.dictation_transcript.column.audio_file_path" && $0.nullable == true })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.database.local.table.terminal_tabs.index.terminal_tabs_chat_position_idx" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.prefs.sidebar.viewMode" && $0.key == "SidebarViewMode" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.protocol.bridge" && $0.surfaceClass == "protocol" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.protocol.bridge.field.schemaVersion" && $0.fieldPath == "schemaVersion" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.api.mesh.post.mesh.jobs" && $0.route == "/v1/mesh/jobs" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.event.remoteJob.completed" && $0.value == "completed" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.web.storage.currentRoute" && $0.key == "ui.route" })
        XCTAssertTrue(nodes.contains { $0.id == "claw.framework.apps" && $0.owner == "claw" && $0.path == "~/.claw/apps" })
        XCTAssertTrue(nodes.contains { $0.id == "claw.framework.design" && $0.owner == "claw" && $0.path == "~/.claw/design" })
        XCTAssertTrue(nodes.contains { $0.id == "claw.framework.audio" && $0.owner == "claw" && $0.path == "~/.claw/audio" })
        XCTAssertTrue(nodes.contains { $0.id == "claw.framework.snippets" && $0.owner == "claw" && $0.path == "~/.claw/core.sqlite#snippets" })
        XCTAssertTrue(nodes.contains { $0.id == "claw.framework.providerRouting" && $0.owner == "claw" && $0.path == "~/.claw/core.sqlite#provider_routing,provider_settings" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.dictationAudioDebug" && $0.path == "~/.clawix/tmp/dictation-audio-debug" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.database.local" && $0.notes?.contains("UI/cache/snapshot") == true })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.clawjs" && $0.storageClass == "hostOperational" && $0.notes?.contains("Not a framework data root") == true })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.secrets" && $0.storageClass == "hostOperational" && $0.notes?.contains("opaque secret ids only") == true })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.localModels" && $0.storageClass == "hostOperational" && $0.notes?.contains("model binaries") == true })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.dictationSounds" && $0.storageClass == "hostOperational" && $0.notes?.contains("framework audio surface") == true })
        XCTAssertFalse(nodes.contains {
            $0.id == "clawix.apps" ||
            $0.id == "clawix.design" ||
            $0.id == "clawix.audioCatalog" ||
            $0.id == "clawix.audioCatalogMetadata" ||
            $0.id == "clawix.dictationAudio" ||
            $0.id == "clawix.prefs.quickAsk.slashCommands" ||
            $0.id == "clawix.prefs.quickAsk.mentionPrompts" ||
            $0.id == "clawix.prefs.provider.featureAccount" ||
            $0.id == "clawix.prefs.provider.featureModel" ||
            $0.id == "clawix.prefs.provider.enabled" ||
            $0.id == "clawix.prefs.dictation.whisperPrompts" ||
            $0.id == "clawix.prefs.dictation.enhancement.customPrompts"
        })

        let manifest = ClawixPersistentSurfaceRegistry.manifest
        let data = try Self.manifestEncoder().encode(manifest)
        try writeManifestExportIfRequested(data)
        let decoded = try JSONDecoder().decode(PersistentSurfaceManifest.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.nodes.count, manifest.nodes.count)
    }

    func testCommittedClawixInspectManifestMatchesRegistry() throws {
        let manifestURL = Self.repoRoot()
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("persistent-surface-clawix.manifest.json")
        let fixtureData = try Data(contentsOf: manifestURL)
        let expected = try JSONDecoder().decode(PersistentSurfaceManifest.self, from: fixtureData)
        XCTAssertEqual(expected, ClawixPersistentSurfaceRegistry.manifest)
    }

    @MainActor
    func testAppsAndDesignDefaultStoresUseFrameworkRoot() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        XCTAssertEqual(AppsStore.defaultRootURL().standardizedFileURL.path, home.appendingPathComponent(".claw/apps", isDirectory: true).standardizedFileURL.path)
        XCTAssertEqual(DesignStore.defaultRootURL().standardizedFileURL.path, home.appendingPathComponent(".claw/design", isDirectory: true).standardizedFileURL.path)
        XCTAssertEqual(EditorStore.defaultRootURL().standardizedFileURL.path, home.appendingPathComponent(".claw/design/documents", isDirectory: true).standardizedFileURL.path)
    }

    private func writeManifestExportIfRequested(_ data: Data) throws {
        guard let rawPath = ProcessInfo.processInfo.environment["CLAWIX_PERSISTENT_SURFACE_MANIFEST_OUT"],
              !rawPath.isEmpty else { return }
        let outputURL = URL(fileURLWithPath: rawPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func manifestEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
