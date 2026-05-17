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
            if args == ["skills", "list", "--json", "--kind", "clawix"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "items": [
                      {
                        "id": "skill-review",
                        "slug": "review",
                        "kind": "clawix",
                        "name": "Review",
                        "body": "Review body",
                        "metadata": { "surface": "skills" }
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
        let skills = try client.listSkillRecords(kind: "clawix")
        XCTAssertEqual(skills.first?.metadata?["surface"], .string("skills"))
        try client.upsertSkillRecord(slug: "review", name: "Review", kind: "clawix", body: "Review body", metadata: ["surface": .string("skills")])
        try client.deleteSkillRecord(slug: "review")

        XCTAssertTrue(calls.contains(["snippets", "list", "--kind", "quickask_slash", "--json"]))
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["snippets", "upsert", "quickask-slash-11111111-1111-1111-1111-111111111111"])
                && call.contains("--kind")
                && call.contains("quickask_slash")
                && call.contains("--metadata")
        })
        XCTAssertTrue(calls.contains(["snippets", "delete", "quickask-slash-11111111-1111-1111-1111-111111111111", "--json"]))
        XCTAssertTrue(calls.contains(["skills", "list", "--json", "--kind", "clawix"]))
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["skills", "upsert", "review"])
                && call.contains("--metadata")
        })
        XCTAssertTrue(calls.contains(["skills", "delete", "review", "--json"]))
        assertFrameworkRecordCommandsOnly(calls)
    }

    private func assertFrameworkRecordCommandsOnly(_ calls: [[String]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(calls.isEmpty, file: file, line: line)
        for call in calls {
            XCTAssertTrue(["snippets", "skills"].contains(call.first), file: file, line: line)
            XCTAssertTrue(call.contains("--json"), file: file, line: line)

            let commandLine = call.joined(separator: " ")
            for forbidden in [
                "UserDefaults",
                "quickAsk.slashCommandsCustom",
                "quickAsk.mentionPromptsCustom",
            ] {
                XCTAssertFalse(commandLine.contains(forbidden), file: file, line: line)
            }
        }
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

    func testAgentEntityCommandsUseHostUnredactedMode() throws {
        var calls: [[String]] = []
        let client = ClawJSFrameworkRecordsClient(runner: .init { args in
            calls.append(args)
            if args == ["agents", "list", "--for-host", "true", "--json"] {
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "items": [
                      {
                        "id": "agent.ops",
                        "name": "Ops",
                        "role": "Operations",
                        "runtime": "codex",
                        "model": "gpt-5.1",
                        "avatar": { "kind": "logoTint", "tintHex": "#7C9CFF" },
                        "instructionsFreeText": "Watch deploys",
                        "personalityIds": [],
                        "skillAllowlist": [],
                        "skillCollectionIds": [],
                        "secretAllowlist": ["vault://agents/ops"],
                        "secretTags": [],
                        "projectIds": [],
                        "integrationBindings": [],
                        "autonomyLevel": "act_limited",
                        "autonomyOverrides": [],
                        "delegation": { "allowedSubagents": [], "scopeInherits": false },
                        "createdAt": "2026-05-15T10:00:00Z",
                        "updatedAt": "2026-05-15T10:00:00Z",
                        "isBuiltin": false
                      }
                    ]
                  }
                }
                """.utf8)
            }
            if args == ["personalities", "list", "--for-host", "true", "--json"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            if args == ["skill-collections", "list", "--for-host", "true", "--json"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            if args == ["connections", "list", "--for-host", "true", "--json"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })

        let agents = try client.listAgents()
        XCTAssertEqual(agents.first?.secretAllowlist, ["vault://agents/ops"])

        var connection = Connection.newDraft(service: .telegram)
        connection.id = "connection.telegram.ops"
        try client.upsertConnection(connection, secretRef: "vault://connections/connection.telegram.ops")

        XCTAssertTrue(calls.contains(["agents", "list", "--for-host", "true", "--json"]))
        let connectionCall = calls.first { $0.starts(with: ["connections", "upsert", "connection.telegram.ops", "--record"]) }
        XCTAssertNotNil(connectionCall)
        XCTAssertEqual(connectionCall?.contains("--for-host"), true)
        let recordIndex = connectionCall?.firstIndex(of: "--record")
        XCTAssertNotNil(recordIndex)
        let record = recordIndex.flatMap { connectionCall?[$0 + 1] } ?? "{}"
        let object = try JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any]
        XCTAssertEqual(object?["secretRef"] as? String, "vault://connections/connection.telegram.ops")
    }

    func testSkillsStorePersistsCatalogAndActiveStateThroughFrameworkRecords() throws {
        var calls: [[String]] = []
        let client = ClawJSFrameworkRecordsClient(runner: .init { args in
            calls.append(args)
            if args == ["skills", "list", "--json", "--kind", "clawix_skill"] ||
               args == ["skills", "list", "--json", "--kind", "clawix_state"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })
        let store = SkillsStore(seedBuiltins: true, frameworkClient: client)
        var skill = SkillsSeedCatalog.builtins[0]
        skill.slug = "custom-skill"
        skill.builtin = false

        store.upsert(skill)
        store.setActive(slug: "custom-skill", scopeTag: "global", active: true)

        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["skills", "upsert", "custom-skill"])
                && call.contains("clawix_skill")
                && call.contains("--metadata")
        })
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["skills", "upsert", "clawix-active-skills"])
                && call.contains("clawix_state")
        })
    }
}
