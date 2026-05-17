import XCTest
@testable import Clawix

@MainActor
final class MCPClawJSAdapterTests: XCTestCase {
    func testStoreLoadsAndPersistsThroughInjectedClawJSPersistence() throws {
        let persistence = FakeMCPPersistence(servers: [
            MCPServerConfig(name: "browser", command: "npx")
        ])
        let store = MCPServersStore(persistence: persistence)

        XCTAssertEqual(store.servers.map(\.name), ["browser"])

        store.upsert(MCPServerConfig(name: "notes", command: "node"))
        XCTAssertEqual(persistence.savedServers.map(\.tomlIdentifier), ["browser", "notes"])
    }

    func testClawJSMCPClientMapsListAndSaveToJsonCommands() throws {
        var calls: [[String]] = []
        let client = ClawJSMCPClient(runner: .init { args in
            calls.append(args)
            if args == ["mcp", "list", "--json"] {
                return Data("""
                {
                  "items": [
                    {
                      "id": "browser",
                      "command": "npx",
                      "args": ["@modelcontextprotocol/server-browser"],
                      "enabled": true
                    }
                  ]
                }
                """.utf8)
            }
            if args == ["mcp", "config-path", "--scope", "user", "--json"] {
                return Data(#"{"configPath":"/tmp/config.toml","exists":true}"#.utf8)
            }
            return Data("{}".utf8)
        })

        let loaded = try client.loadServers()
        XCTAssertEqual(loaded.first?.tomlIdentifier, "browser")
        XCTAssertEqual(loaded.first?.arguments.map(\.value), ["@modelcontextprotocol/server-browser"])

        try client.saveServers([
            MCPServerConfig(
                name: "api",
                transport: .http,
                enabled: false,
                url: "https://example.invalid/mcp",
                bearerTokenEnvVar: "API_TOKEN",
                headers: [MCPKeyValueEntry(key: "X-Test", value: "1")]
            )
        ])

        XCTAssertTrue(calls.contains(["mcp", "delete", "browser", "--json"]))
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["mcp", "upsert", "api", "--json"])
                && call.contains("--url")
                && call.contains("https://example.invalid/mcp")
                && call.contains("--bearer-token-env-var")
                && call.contains("API_TOKEN")
                && call.contains("--enabled")
                && call.contains("false")
        })

        let configPath = try client.configPath(scope: "user", projectPath: nil)
        XCTAssertEqual(configPath.configPath, "/tmp/config.toml")
        XCTAssertEqual(configPath.exists, true)
        XCTAssertTrue(calls.contains(["mcp", "config-path", "--scope", "user", "--json"]))
        assertClawJSMCPCommandsOnly(calls)
    }

    private func assertClawJSMCPCommandsOnly(_ calls: [[String]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(calls.isEmpty, file: file, line: line)
        for call in calls {
            XCTAssertEqual(call.first, "mcp", file: file, line: line)
            XCTAssertTrue(call.contains("--json"), file: file, line: line)

            let commandLine = call.joined(separator: " ")
            for forbidden in [".codex", "config.toml", "mcp_servers", "[mcp_servers"] {
                XCTAssertFalse(commandLine.contains(forbidden), file: file, line: line)
            }
        }
    }
}

private final class FakeMCPPersistence: MCPServersPersistence {
    private var current: [MCPServerConfig]
    private(set) var savedServers: [MCPServerConfig] = []

    init(servers: [MCPServerConfig]) {
        current = servers
    }

    func loadServers() throws -> [MCPServerConfig] {
        current
    }

    func saveServers(_ servers: [MCPServerConfig]) throws {
        savedServers = servers
        current = servers
    }
}
