import XCTest

final class ClawJSMainDatabaseBoundaryTests: XCTestCase {
    func testClawixDoesNotReferenceClawJSDataStoresOutsideSupervisor() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let macosRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            macosRoot.appendingPathComponent("Sources/Clawix", isDirectory: true),
            macosRoot.appendingPathComponent("Helpers/Bridged/Sources/clawix-bridged", isDirectory: true),
        ]

        let allowedSuffixes: Set<String> = [
            "ClawJS/ClawJSServiceManager.swift",
        ]
        let forbiddenTerms = [
            "clawjs.sqlite",
            "sessions.sqlite",
            "audio.sqlite",
            "drive.sqlite",
            "search.sqlite",
            "runtime.sqlite",
            "notify.sqlite",
            "monitor.sqlite",
            "infra.sqlite",
            "ops.sqlite",
            "CLAWJS_MAIN_DB_PATH",
            "CLAWJS_MAIN_DATA_DIR",
            "CLAWJS_MAIN_FILES_DIR",
            "CLAWIX_CLAWJS_DATA_DIR",
            "state_5.sqlite",
            ".codex/session_index.jsonl",
            ".codex/sessions",
            "archived_sessions",
            ".codex/.codex-global-state.json",
            "CodexConfigToml",
        ]

        var violations: [String] = []

        for sourcesRoot in sourceRoots {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: sourcesRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let relative = fileURL.path.replacingOccurrences(of: sourcesRoot.path + "/", with: "")
                guard !allowedSuffixes.contains(relative) else { continue }
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let body = try String(contentsOf: fileURL, encoding: .utf8)
                for term in forbiddenTerms where body.contains(term) {
                    violations.append("\(sourcesRoot.lastPathComponent)/\(relative): \(term)")
                }
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "Clawix must reach ClawJS main/sidecar data stores through ClawJSServiceManager/CLI JSON, not direct SQLite paths."
        )
    }
}
