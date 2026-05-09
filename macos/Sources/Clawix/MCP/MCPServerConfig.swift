import Foundation

/// Transport supported by Codex MCP servers. Codex picks one at session
/// startup based on whether `command` (stdio) or `url` (HTTP) is present.
enum MCPTransportKind: String, Hashable, Codable {
    case stdio
    case http
}

/// Single key / value pair as it appears in the editor UI. We keep the
/// id stable across edits so SwiftUI's ForEach doesn't re-create rows on
/// every keystroke and lose focus.
struct MCPKeyValueEntry: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// Single value entry (used for arguments and env passthrough).
struct MCPSingleEntry: Identifiable, Hashable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String = "") {
        self.id = id
        self.value = value
    }
}

/// Full editable representation of one `[mcp_servers.<name>]` block.
/// Stored as flat fields rather than a tagged-enum so the editor UI can
/// preserve the user's input when toggling between transports.
struct MCPServerConfig: Identifiable, Hashable {
    let id: UUID
    var name: String
    var transport: MCPTransportKind
    var enabled: Bool

    // STDIO
    var command: String
    var arguments: [MCPSingleEntry]
    var env: [MCPKeyValueEntry]
    var envPassthrough: [MCPSingleEntry]
    var workingDirectory: String

    // HTTP
    var url: String
    var bearerTokenEnvVar: String
    var headers: [MCPKeyValueEntry]
    var headersFromEnv: [MCPKeyValueEntry]

    init(
        id: UUID = UUID(),
        name: String = "",
        transport: MCPTransportKind = .stdio,
        enabled: Bool = true,
        command: String = "",
        arguments: [MCPSingleEntry] = [],
        env: [MCPKeyValueEntry] = [],
        envPassthrough: [MCPSingleEntry] = [],
        workingDirectory: String = "",
        url: String = "",
        bearerTokenEnvVar: String = "",
        headers: [MCPKeyValueEntry] = [],
        headersFromEnv: [MCPKeyValueEntry] = []
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.enabled = enabled
        self.command = command
        self.arguments = arguments
        self.env = env
        self.envPassthrough = envPassthrough
        self.workingDirectory = workingDirectory
        self.url = url
        self.bearerTokenEnvVar = bearerTokenEnvVar
        self.headers = headers
        self.headersFromEnv = headersFromEnv
    }

    /// Trimmed copy ready to be persisted. Drops empty rows that the
    /// user left around in the form.
    func sanitised() -> MCPServerConfig {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bearerTokenEnvVar = bearerTokenEnvVar.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.workingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.arguments = arguments
            .map { MCPSingleEntry(id: $0.id, value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.value.isEmpty }
        copy.envPassthrough = envPassthrough
            .map { MCPSingleEntry(id: $0.id, value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.value.isEmpty }
        copy.env = env
            .map { MCPKeyValueEntry(id: $0.id,
                                    key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                                    value: $0.value) }
            .filter { !$0.key.isEmpty }
        copy.headers = headers
            .map { MCPKeyValueEntry(id: $0.id,
                                    key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                                    value: $0.value) }
            .filter { !$0.key.isEmpty }
        copy.headersFromEnv = headersFromEnv
            .map { MCPKeyValueEntry(id: $0.id,
                                    key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                                    value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
        return copy
    }

    /// Lower-cased identifier used as the TOML table name. Codex requires
    /// `[mcp_servers.<id>]` where id matches `[a-zA-Z0-9_-]+`.
    var tomlIdentifier: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        let mapped = String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        let collapsed = mapped.replacingOccurrences(of: "__", with: "_", options: .regularExpression)
        let cleaned = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? "server" : cleaned
    }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Untitled" : n
    }
}
