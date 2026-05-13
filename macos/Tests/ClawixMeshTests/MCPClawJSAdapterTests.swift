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
