import Foundation

/// Targeted manipulator for the `[mcp_servers.*]` blocks inside
/// `~/.codex/config.toml`. We do NOT parse the whole TOML grammar:
/// instead we walk the file as a sequence of "blocks", where a block
/// starts at a `[header]` line and runs until the next header. Anything
/// outside `[mcp_servers.*]` headers is preserved verbatim, comments
/// and blank lines included.
///
/// This is enough for our use case (the macOS Settings page only edits
/// MCP servers) and avoids dragging in a full TOML parser.
enum CodexConfigToml {

    // MARK: - Public API

    /// Path to the active `config.toml`. In real mode this is
    /// `~/.codex/config.toml`; in dummy mode `dummy.sh` exports
    /// `CLAWIX_BACKEND_HOME=<workspace>/dummy/.codex` and we follow it
    /// so dummy sessions don't accidentally edit the real config (the
    /// symlink dance in dummy.sh aside, callers asking the app for the
    /// "current" config should always go through the same env-aware
    /// resolver the rest of the app uses).
    static var configURL: URL {
        if let home = ProcessInfo.processInfo.environment["CLAWIX_BACKEND_HOME"],
           !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("config.toml", isDirectory: false)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    /// Read every `[mcp_servers.<name>]` from disk. Servers that fail
    /// validation (missing both `command` and `url`) are still surfaced
    /// so the user can fix them in the editor.
    static func loadServers() -> [MCPServerConfig] {
        guard let raw = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
        let blocks = parseBlocks(raw)
        return assembleServers(from: blocks)
    }

    /// Persist the canonical `mcp_servers` list back to disk. Existing
    /// blocks for those servers are removed and the new ones appended
    /// in the same order they appear in `servers`. The non-MCP rest of
    /// the file is preserved verbatim.
    static func saveServers(_ servers: [MCPServerConfig]) throws {
        let url = configURL
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var blocks = parseBlocks(raw)

        // Drop every existing mcp_servers block. We rewrite them all.
        blocks.removeAll { isMCPBlock($0) }

        // Trim trailing empty preamble lines so we don't accumulate
        // blank lines on every save.
        if let last = blocks.last,
           last.header == nil,
           last.body.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            blocks.removeLast()
        }

        // Append a single blank-line spacer if the previous content
        // doesn't already end with one. Keeps the file readable.
        let separator = TomlBlock(header: nil, body: [""])

        var appended: [TomlBlock] = []
        for server in servers {
            appended.append(contentsOf: render(server: server))
        }

        if !appended.isEmpty {
            if blocks.isEmpty == false { blocks.append(separator) }
            blocks.append(contentsOf: appended)
        }

        let serialised = serialise(blocks)
        try ensureDirectoryExists(for: url)
        try serialised.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Convenience: replace a single server (matched by `tomlIdentifier`).
    static func upsertServer(_ server: MCPServerConfig) throws {
        var current = loadServers()
        let target = server.tomlIdentifier
        if let idx = current.firstIndex(where: { $0.tomlIdentifier == target }) {
            current[idx] = server
        } else {
            current.append(server)
        }
        try saveServers(current)
    }

    /// Remove the `[mcp_servers.<name>]` block (and any nested
    /// `[mcp_servers.<name>.foo]` sub-tables).
    static func deleteServer(named identifier: String) throws {
        let current = loadServers().filter { $0.tomlIdentifier != identifier }
        try saveServers(current)
    }

    // MARK: - Block model

    /// A "block" is either a single `[header]` table plus its body
    /// lines, or a leading preamble (`header == nil`) that captures
    /// everything before the first table header.
    fileprivate struct TomlBlock {
        var header: String?            // raw text inside the `[...]`
        var body: [String]             // lines that follow the header
    }

    private static func parseBlocks(_ raw: String) -> [TomlBlock] {
        var blocks: [TomlBlock] = []
        var current = TomlBlock(header: nil, body: [])

        // Use raw newlines so we can roundtrip the file faithfully.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            if let header = tableHeader(in: line) {
                blocks.append(current)
                current = TomlBlock(header: header, body: [])
            } else {
                current.body.append(line)
            }
        }
        blocks.append(current)
        return blocks
    }

    /// Returns the inner text of a `[header]` line, ignoring strings
    /// where the brackets appear inside a quoted value.
    private static func tableHeader(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        guard !trimmed.hasPrefix("[[") else { return nil } // array-of-tables
        guard let end = trimmed.firstIndex(of: "]") else { return nil }
        let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        return inner.trimmingCharacters(in: .whitespaces)
    }

    private static func isMCPBlock(_ block: TomlBlock) -> Bool {
        guard let header = block.header else { return false }
        return header == "mcp_servers"
            || header.hasPrefix("mcp_servers.")
    }

    private static func serialise(_ blocks: [TomlBlock]) -> String {
        var output: [String] = []
        for (idx, block) in blocks.enumerated() {
            if let header = block.header {
                output.append("[\(header)]")
            } else if idx > 0 {
                // Ensure the header is on its own line.
            }
            output.append(contentsOf: block.body)
        }
        // Guarantee a trailing newline on the file.
        var joined = output.joined(separator: "\n")
        if !joined.hasSuffix("\n") { joined.append("\n") }
        return joined
    }

    // MARK: - Server -> blocks

    private static func render(server raw: MCPServerConfig) -> [TomlBlock] {
        let server = raw.sanitised()
        let id = server.tomlIdentifier
        guard !id.isEmpty else { return [] }

        var rootBody: [String] = []
        var subBlocks: [TomlBlock] = []

        switch server.transport {
        case .stdio:
            if !server.command.isEmpty {
                rootBody.append("command = \(quoteString(server.command))")
            }
            if !server.arguments.isEmpty {
                let arr = server.arguments.map { quoteString($0.value) }
                rootBody.append("args = [\(arr.joined(separator: ", "))]")
            }
            if !server.envPassthrough.isEmpty {
                let arr = server.envPassthrough.map { quoteString($0.value) }
                rootBody.append("env_passthrough = [\(arr.joined(separator: ", "))]")
            }
            if !server.workingDirectory.isEmpty {
                rootBody.append("cwd = \(quoteString(server.workingDirectory))")
            }
            if !server.env.isEmpty {
                let envBody = server.env.map { "\(quoteKey($0.key)) = \(quoteString($0.value))" }
                subBlocks.append(TomlBlock(header: "mcp_servers.\(id).env", body: envBody))
            }
        case .http:
            if !server.url.isEmpty {
                rootBody.append("url = \(quoteString(server.url))")
            }
            if !server.bearerTokenEnvVar.isEmpty {
                rootBody.append("bearer_token_env_var = \(quoteString(server.bearerTokenEnvVar))")
            }
            if !server.headers.isEmpty {
                let body = server.headers.map { "\(quoteKey($0.key)) = \(quoteString($0.value))" }
                subBlocks.append(TomlBlock(header: "mcp_servers.\(id).headers", body: body))
            }
            if !server.headersFromEnv.isEmpty {
                let body = server.headersFromEnv.map { "\(quoteKey($0.key)) = \(quoteString($0.value))" }
                subBlocks.append(TomlBlock(header: "mcp_servers.\(id).headers_from_env", body: body))
            }
        }

        if !server.enabled {
            rootBody.append("enabled = false")
        }

        let root = TomlBlock(header: "mcp_servers.\(id)", body: rootBody)
        return [root] + subBlocks
    }

    // MARK: - Blocks -> servers

    private static func assembleServers(from blocks: [TomlBlock]) -> [MCPServerConfig] {
        var ordered: [String] = []
        var roots: [String: TomlBlock] = [:]
        var subs: [String: [String: TomlBlock]] = [:] // [name: [subKey: block]]

        for block in blocks where block.header != nil {
            let header = block.header!
            guard header == "mcp_servers" || header.hasPrefix("mcp_servers.") else { continue }
            // Skip the bare `[mcp_servers]` header (it's not a server).
            if header == "mcp_servers" { continue }

            let suffix = header.dropFirst("mcp_servers.".count)
            // Header path can be `<name>` or `<name>.<sub>`. We don't
            // expect deeper nesting in MCP configs.
            let parts = suffix.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            guard let firstPart = parts.first else { continue }
            let name = String(firstPart)
            if roots[name] == nil { ordered.append(name) }
            if parts.count == 1 {
                roots[name] = block
            } else {
                let subKey = String(parts[1])
                subs[name, default: [:]][subKey] = block
            }
        }

        return ordered.compactMap { name -> MCPServerConfig? in
            guard let root = roots[name] else { return nil }
            return parse(name: name, root: root, subs: subs[name] ?? [:])
        }
    }

    private static func parse(name: String,
                              root: TomlBlock,
                              subs: [String: TomlBlock]) -> MCPServerConfig {
        var server = MCPServerConfig(name: name)
        let kv = parseKeyValues(root.body)

        if case let .string(s)? = kv["url"] { server.url = s }
        if case let .string(s)? = kv["bearer_token_env_var"] { server.bearerTokenEnvVar = s }
        if case let .string(s)? = kv["command"] { server.command = s }
        if case let .string(s)? = kv["cwd"] { server.workingDirectory = s }
        if case let .bool(b)? = kv["enabled"] { server.enabled = b }
        if case let .array(values)? = kv["args"] {
            server.arguments = values.map { MCPSingleEntry(value: $0) }
        }
        if case let .array(values)? = kv["env_passthrough"] {
            server.envPassthrough = values.map { MCPSingleEntry(value: $0) }
        }

        // Heuristic: HTTP if any HTTP-only key is present, otherwise STDIO.
        if !server.url.isEmpty || !server.bearerTokenEnvVar.isEmpty
            || subs["headers"] != nil || subs["headers_from_env"] != nil {
            server.transport = .http
        } else {
            server.transport = .stdio
        }

        if let envBlock = subs["env"] {
            server.env = parseKeyValues(envBlock.body).compactMap { k, v in
                guard case let .string(s) = v else { return nil }
                return MCPKeyValueEntry(key: k, value: s)
            }
        }
        if let h = subs["headers"] {
            server.headers = parseKeyValues(h.body).compactMap { k, v in
                guard case let .string(s) = v else { return nil }
                return MCPKeyValueEntry(key: k, value: s)
            }
        }
        if let h = subs["headers_from_env"] {
            server.headersFromEnv = parseKeyValues(h.body).compactMap { k, v in
                guard case let .string(s) = v else { return nil }
                return MCPKeyValueEntry(key: k, value: s)
            }
        }
        return server
    }

    // MARK: - Tiny TOML scalar parser

    fileprivate enum TomlValue {
        case string(String)
        case bool(Bool)
        case array([String])
        case unsupported
    }

    private static func parseKeyValues(_ lines: [String]) -> [String: TomlValue] {
        var out: [String: TomlValue] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let rawKey = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            let key = unquoteKey(rawKey)
            out[key] = parseScalar(rawValue)
        }
        return out
    }

    private static func parseScalar(_ raw: String) -> TomlValue {
        var s = raw
        // Strip trailing comments outside strings: cheap heuristic that
        // works because we control the writer side too.
        if !s.hasPrefix("\"") && !s.hasPrefix("'") && !s.hasPrefix("[") {
            if let hash = s.firstIndex(of: "#") {
                s = String(s[..<hash]).trimmingCharacters(in: .whitespaces)
            }
        }
        if s == "true"  { return .bool(true) }
        if s == "false" { return .bool(false) }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            return .string(unescape(String(s.dropFirst().dropLast())))
        }
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            return .string(String(s.dropFirst().dropLast()))
        }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast())
            return .array(splitArrayItems(inner).compactMap { item in
                let t = item.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
                    return unescape(String(t.dropFirst().dropLast()))
                }
                if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 {
                    return String(t.dropFirst().dropLast())
                }
                return nil
            })
        }
        return .unsupported
    }

    /// Splits an inline TOML array body on commas, ignoring commas
    /// inside double or single-quoted strings.
    private static func splitArrayItems(_ raw: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false
        var escape = false
        for ch in raw {
            if escape {
                current.append(ch); escape = false; continue
            }
            if ch == "\\" && inDouble {
                current.append(ch); escape = true; continue
            }
            if ch == "\"" && !inSingle { inDouble.toggle(); current.append(ch); continue }
            if ch == "'"  && !inDouble { inSingle.toggle(); current.append(ch); continue }
            if ch == "," && !inDouble && !inSingle {
                out.append(current); current = ""; continue
            }
            current.append(ch)
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { out.append(current) }
        return out
    }

    private static func unquoteKey(_ raw: String) -> String {
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            return unescape(String(raw.dropFirst().dropLast()))
        }
        if raw.hasPrefix("'") && raw.hasSuffix("'") && raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    // MARK: - Quoting helpers

    private static let bareKeyChars: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "_-")
        return cs
    }()

    private static func quoteKey(_ raw: String) -> String {
        guard !raw.isEmpty else { return "\"\"" }
        let needsQuote = raw.unicodeScalars.contains { !bareKeyChars.contains($0) }
        return needsQuote ? "\"\(escape(raw))\"" : raw
    }

    private static func quoteString(_ raw: String) -> String {
        return "\"\(escape(raw))\""
    }

    private static func escape(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            switch ch {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            default:   out.append(ch)
            }
        }
        return out
    }

    private static func unescape(_ raw: String) -> String {
        var out = ""
        var iter = raw.makeIterator()
        while let ch = iter.next() {
            if ch == "\\", let next = iter.next() {
                switch next {
                case "n":  out.append("\n")
                case "r":  out.append("\r")
                case "t":  out.append("\t")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default:   out.append(next)
                }
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func ensureDirectoryExists(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
