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
        XCTAssertTrue(nodes.contains { $0.id == "clawix.protocol.bridge.field.protocolVersion" && $0.fieldPath == "protocolVersion" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.api.mesh.post.mesh.jobs" && $0.route == "/v1/mesh/jobs" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.event.remoteJob.completed" && $0.value == "completed" })
        XCTAssertTrue(nodes.contains { $0.id == "clawix.web.storage.currentRoute" && $0.key == "ui.route" })

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
