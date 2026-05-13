import Foundation
import Combine

/// Single source of truth for the MCP page. The UI talks to ClawJS over
/// the stable `claw mcp ... --json` adapter; Clawix never parses or
/// mutates Codex-owned TOML directly.
@MainActor
final class MCPServersStore: ObservableObject {
    static let shared = MCPServersStore()

    @Published private(set) var servers: [MCPServerConfig] = []
    @Published private(set) var lastError: String? = nil

    private let persistence: MCPServersPersistence

    convenience init() {
        self.init(persistence: ClawJSMCPClient())
    }

    init(persistence: MCPServersPersistence) {
        self.persistence = persistence
        reload()
    }

    // MARK: - Mutations

    func reload() {
        do {
            servers = try persistence.loadServers()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleEnabled(_ server: MCPServerConfig, isOn: Bool) {
        guard let idx = servers.firstIndex(of: server) else { return }
        servers[idx].enabled = isOn
        persist()
    }

    /// Inserts a new server or updates an existing one identified by
    /// `id`. Returns the canonical `tomlIdentifier` that ended up on
    /// disk, useful when callers need to navigate to it afterwards.
    @discardableResult
    func upsert(_ server: MCPServerConfig) -> String {
        let trimmed = server.sanitised()
        if let idx = servers.firstIndex(where: { $0.id == trimmed.id }) {
            servers[idx] = trimmed
        } else {
            servers.append(trimmed)
        }
        persist()
        return trimmed.tomlIdentifier
    }

    func delete(_ server: MCPServerConfig) {
        servers.removeAll { $0.id == server.id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try persistence.saveServers(servers)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
