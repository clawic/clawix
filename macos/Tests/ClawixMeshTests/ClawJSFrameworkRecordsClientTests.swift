import XCTest
@testable import Clawix

@MainActor
final class ClawJSFrameworkRecordsClientTests: XCTestCase {
    func testSnippetCommandsMapToClawJSRecordsCli() throws {
        var calls: [[String]] = []
        let client = ClawJSFrameworkRecordsClient(runner: .init { args in
            calls.append(args)
            if args == ["snippets", "list", "--kind", "quickask_slash", "--json"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "items": [
                      {
                        "id": "11111111-1111-1111-1111-111111111111",
                        "slug": "quickask-slash-11111111-1111-1111-1111-111111111111",
                        "kind": "quickask_slash",
                        "title": "/ship",
                        "body": "Ship it",
                        "shortcut": "/ship",
                        "metadata": { "trigger": "/ship", "description": "Ship current work", "hasExpansion": "true" }
                      }
                    ]
                  }
                }
                """.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })

        let snippets = try client.listSnippets(kind: "quickask_slash")
        XCTAssertEqual(snippets.first?.metadata?["trigger"], "/ship")

        try client.upsertSnippet(
            id: "11111111-1111-1111-1111-111111111111",
            slug: "quickask-slash-11111111-1111-1111-1111-111111111111",
            kind: "quickask_slash",
            title: "/ship",
            body: "Ship it",
            shortcut: "/ship",
            metadata: ["trigger": "/ship"]
        )
        try client.deleteSnippet(slug: "quickask-slash-11111111-1111-1111-1111-111111111111")

        XCTAssertTrue(calls.contains(["snippets", "list", "--kind", "quickask_slash", "--json"]))
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["snippets", "upsert", "quickask-slash-11111111-1111-1111-1111-111111111111"])
                && call.contains("--kind")
                && call.contains("quickask_slash")
                && call.contains("--metadata")
        })
        XCTAssertTrue(calls.contains(["snippets", "delete", "quickask-slash-11111111-1111-1111-1111-111111111111", "--json"]))
    }

    func testProviderRoutingCommandsMapToClawJSRecordsCli() throws {
        var calls: [[String]] = []
        let client = ClawJSFrameworkRecordsClient(runner: .init { args in
            calls.append(args)
            if args == ["providers", "routing", "list", "--json"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "items": [
                      {
                        "id": "enhancement:chat",
                        "feature": "enhancement",
                        "capability": "chat",
                        "provider": "openai",
                        "model": "gpt-4o-mini",
                        "accountRef": "vault://providers/openai/11111111-1111-1111-1111-111111111111"
                      }
                    ]
                  }
                }
                """.utf8)
            }
            if args == ["providers", "settings", "list", "--json"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "items": [
                      { "id": "provider:openai", "provider": "openai", "enabled": 0 }
                    ]
                  }
                }
                """.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })

        XCTAssertEqual(try client.listProviderRoutes().first?.accountRef, "vault://providers/openai/11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(try client.listProviderSettings().first?.enabled, false)

        try client.setProviderRoute(
            feature: "enhancement",
            capability: "chat",
            provider: "openai",
            model: "gpt-4o-mini",
            accountRef: "vault://providers/openai/11111111-1111-1111-1111-111111111111"
        )
        try client.deleteProviderRoute(feature: "enhancement", capability: "chat")
        try client.setProviderEnabled("openai", enabled: false)

        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["providers", "routing", "set", "enhancement"])
                && call.contains("--account-ref")
        })
        XCTAssertTrue(calls.contains(["providers", "routing", "delete", "enhancement", "--capability", "chat", "--json"]))
        XCTAssertTrue(calls.contains(["providers", "settings", "set", "openai", "--enabled", "false", "--json"]))
    }
}
