import Foundation

@MainActor
protocol MCPServersPersistence {
    func loadServers() throws -> [MCPServerConfig]
    func saveServers(_ servers: [MCPServerConfig]) throws
}

struct ClawJSMCPClient: MCPServersPersistence {
    struct CommandRunner {
        var run: ([String]) throws -> Data
    }

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try Self.runClawJS(args: args)
        }
    }

    func loadServers() throws -> [MCPServerConfig] {
        let data = try runner.run(["mcp", "list", "--json"])
        let response = try JSONDecoder().decode(MCPListResponse.self, from: data)
        return response.items.map(\.config)
    }

    func saveServers(_ servers: [MCPServerConfig]) throws {
        let existing = try loadServers()
        let desiredIds = Set(servers.map(\.tomlIdentifier))
        for server in existing where !desiredIds.contains(server.tomlIdentifier) {
            _ = try runner.run(["mcp", "delete", server.tomlIdentifier, "--json"])
        }
        for server in servers.map({ $0.sanitised() }) {
            var args = ["mcp", "upsert", server.tomlIdentifier, "--json"]
            switch server.transport {
            case .stdio:
                args += ["--command", server.command]
                if !server.arguments.isEmpty {
                    args += ["--args", try jsonArray(server.arguments.map(\.value))]
                }
                if !server.envPassthrough.isEmpty {
                    args += ["--env-passthrough", try jsonArray(server.envPassthrough.map(\.value))]
                }
                if !server.workingDirectory.isEmpty {
                    args += ["--cwd", server.workingDirectory]
                }
                if !server.env.isEmpty {
                    args += ["--env", try jsonObject(server.env)]
                }
            case .http:
                args += ["--url", server.url]
                if !server.bearerTokenEnvVar.isEmpty {
                    args += ["--bearer-token-env-var", server.bearerTokenEnvVar]
                }
                if !server.headers.isEmpty {
                    args += ["--headers", try jsonObject(server.headers)]
                }
                if !server.headersFromEnv.isEmpty {
                    args += ["--headers-from-env", try jsonObject(server.headersFromEnv)]
                }
            }
            args += ["--enabled", server.enabled ? "true" : "false"]
            _ = try runner.run(args)
        }
    }

    func configPath(scope: String, projectPath: String?) throws -> MCPConfigPath {
        var args = ["mcp", "config-path", "--scope", scope, "--json"]
        if let projectPath, !projectPath.isEmpty {
            args += ["--project", projectPath]
        }
        let data = try runner.run(args)
        return try JSONDecoder().decode(MCPConfigPath.self, from: data)
    }

    @MainActor
    private static func runClawJS(args: [String]) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSMCPClient", code: 1, userInfo: [
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
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw mcp failed"
            throw NSError(domain: "ClawJSMCPClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }

    private func jsonArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonObject(_ values: [MCPKeyValueEntry]) throws -> String {
        let object = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value) })
        let data = try JSONEncoder().encode(object)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct MCPListResponse: Decodable {
    let items: [MCPServerDTO]
}

struct MCPConfigPath: Decodable {
    let configPath: String
    let exists: Bool
}

private struct MCPServerDTO: Decodable {
    let id: String
    let command: String?
    let url: String?
    let args: [String]?
    let env: [String: String]?
    let envPassthrough: [String]?
    let cwd: String?
    let bearerTokenEnvVar: String?
    let headers: [String: String]?
    let headersFromEnv: [String: String]?
    let enabled: Bool?
    let disabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case command
        case url
        case args
        case env
        case envPassthrough = "env_passthrough"
        case cwd
        case bearerTokenEnvVar = "bearer_token_env_var"
        case headers
        case headersFromEnv = "headers_from_env"
        case enabled
        case disabled
    }

    var config: MCPServerConfig {
        MCPServerConfig(
            name: id,
            transport: url == nil ? .stdio : .http,
            enabled: enabled ?? !(disabled ?? false),
            command: command ?? "",
            arguments: (args ?? []).map { MCPSingleEntry(value: $0) },
            env: (env ?? [:]).sorted { $0.key < $1.key }.map { MCPKeyValueEntry(key: $0.key, value: $0.value) },
            envPassthrough: (envPassthrough ?? []).map { MCPSingleEntry(value: $0) },
            workingDirectory: cwd ?? "",
            url: url ?? "",
            bearerTokenEnvVar: bearerTokenEnvVar ?? "",
            headers: (headers ?? [:]).sorted { $0.key < $1.key }.map { MCPKeyValueEntry(key: $0.key, value: $0.value) },
            headersFromEnv: (headersFromEnv ?? [:]).sorted { $0.key < $1.key }.map { MCPKeyValueEntry(key: $0.key, value: $0.value) }
        )
    }
}
