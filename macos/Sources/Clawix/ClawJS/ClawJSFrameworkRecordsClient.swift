import Foundation

@MainActor
struct ClawJSFrameworkRecordsClient {
    struct CommandRunner {
        var run: ([String]) throws -> Data
    }

    struct SnippetRecord: Decodable, Equatable {
        let id: String
        let slug: String
        let kind: String
        let title: String
        let body: String
        let shortcut: String?
        let metadata: [String: String]?
    }

    struct ProviderRoute: Decodable, Equatable {
        let id: String
        let feature: String
        let capability: String
        let provider: String
        let model: String?
        let accountRef: String?
    }

    struct ProviderSetting: Decodable, Equatable {
        let id: String
        let provider: String
        let enabled: Bool

        private enum CodingKeys: String, CodingKey {
            case id
            case provider
            case enabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            provider = try container.decode(String.self, forKey: .provider)
            if let bool = try? container.decode(Bool.self, forKey: .enabled) {
                enabled = bool
            } else {
                let intValue = (try? container.decode(Int.self, forKey: .enabled)) ?? 1
                enabled = intValue != 0
            }
        }
    }

    private struct ListResponse<T: Decodable>: Decodable {
        let items: [T]
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    static let shared = ClawJSFrameworkRecordsClient()

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try Self.runClawJS(args: args)
        }
    }

    func listSnippets(kind: String) throws -> [SnippetRecord] {
        let data = try runner.run(["snippets", "list", "--kind", kind, "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<SnippetRecord>>.self, from: data).data.items
    }

    func upsertSnippet(
        id: String,
        slug: String,
        kind: String,
        title: String,
        body: String,
        shortcut: String? = nil,
        metadata: [String: String] = [:]
    ) throws {
        var args = [
            "snippets", "upsert", slug,
            "--id", id,
            "--kind", kind,
            "--title", title,
            "--body", body,
            "--json",
        ]
        if let shortcut, !shortcut.isEmpty {
            args += ["--shortcut", shortcut]
        }
        if !metadata.isEmpty,
           let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            args += ["--metadata", json]
        }
        _ = try runner.run(args)
    }

    func deleteSnippet(slug: String) throws {
        _ = try runner.run(["snippets", "delete", slug, "--json"])
    }

    func listProviderRoutes() throws -> [ProviderRoute] {
        let data = try runner.run(["providers", "routing", "list", "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<ProviderRoute>>.self, from: data).data.items
    }

    func setProviderRoute(
        feature: String,
        capability: String,
        provider: String,
        model: String,
        accountRef: String
    ) throws {
        _ = try runner.run([
            "providers", "routing", "set", feature,
            "--capability", capability,
            "--provider", provider,
            "--model", model,
            "--account-ref", accountRef,
            "--json",
        ])
    }

    func deleteProviderRoute(feature: String, capability: String) throws {
        _ = try runner.run([
            "providers", "routing", "delete", feature,
            "--capability", capability,
            "--json",
        ])
    }

    func listProviderSettings() throws -> [ProviderSetting] {
        let data = try runner.run(["providers", "settings", "list", "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<ProviderSetting>>.self, from: data).data.items
    }

    func setProviderEnabled(_ provider: String, enabled: Bool) throws {
        _ = try runner.run([
            "providers", "settings", "set", provider,
            "--enabled", enabled ? "true" : "false",
            "--json",
        ])
    }

    @MainActor
    private static func runClawJS(args: [String]) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
            ])
        }
        let process = Process()
        process.executableURL = ClawJSRuntime.nodeBinaryURL
        process.arguments = [ClawJSRuntime.cliScriptURL.path] + args
        process.currentDirectoryURL = ClawJSServiceManager.workspaceURL
        process.environment = ClawJSServiceManager.cliEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw framework records failed"
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }
}
