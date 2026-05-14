import XCTest
@testable import Clawix

final class SecretsSecurityBoundaryTests: XCTestCase {
    func testSecretsServiceDoesNotUseDiskAdminTokenFallback() throws {
        let source = try readSource("ClawJS/ClawJSServiceManager.swift")

        XCTAssertFalse(
            source.contains("adminTokenFromDataDir(for: .secrets)"),
            "Secrets clients must not recover bearer/admin tokens from disk."
        )
        XCTAssertTrue(
            source.contains("if let adminToken, service != .secrets"),
            "The supervisor must not write a Secrets .admin-token file."
        )
        XCTAssertTrue(
            source.contains("for tokenURL in staleSecretsAdminTokenURLs()"),
            "Launching Secrets must remove every known stale .admin-token file."
        )
        XCTAssertTrue(
            source.contains(".appendingPathComponent(ClawixPersistentSurfacePaths.components.legacyClawWorkspace, isDirectory: true)"),
            "Secrets launch cleanup must include legacy .clawjs sidecar token paths."
        )
        XCTAssertTrue(
            source.contains("if service == .secrets { return false }"),
            "Secrets must not adopt an existing local sidecar through a disk bearer token."
        )
    }

    func testConnectionAuthReadDoesNotReturnPlaintext() throws {
        let source = try readSource("Agents/AgentStore.swift")
        let body = try extractFunctionBody(
            named: "func readConnectionAuth(connectionId: String) -> String?",
            from: source,
            until: "    func hasConnectionAuth"
        )

        XCTAssertTrue(
            body.contains("migrateLegacyConnectionAuth"),
            "Legacy auth may be consumed only for one-way migration into Secrets."
        )
        XCTAssertTrue(
            body.contains("return nil"),
            "Connection auth reads must not hand plaintext back to UI, agents, or integrations."
        )
        XCTAssertFalse(body.contains("revealField"))
        XCTAssertFalse(body.contains("return legacy"))
        XCTAssertFalse(body.contains("return (try?"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    private func extractFunctionBody(named name: String, from source: String, until marker: String) throws -> String {
        guard let start = source.range(of: name)?.lowerBound else {
            XCTFail("Could not find \(name)")
            return ""
        }
        guard let end = source.range(of: marker, range: start..<source.endIndex)?.lowerBound else {
            XCTFail("Could not find marker \(marker)")
            return ""
        }
        return String(source[start..<end])
    }
}
