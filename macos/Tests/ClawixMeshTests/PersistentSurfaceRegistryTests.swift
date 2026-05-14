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

        let manifest = ClawixPersistentSurfaceRegistry.manifest
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PersistentSurfaceManifest.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.nodes.count, manifest.nodes.count)
    }
}
