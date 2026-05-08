import Foundation
import Combine

/// Single source of truth for the MCP page. Reads `~/.codex/config.toml`
/// at init, watches the file so external edits show up live, and writes
/// back through `CodexConfigToml`.
@MainActor
final class MCPServersStore: ObservableObject {
    static let shared = MCPServersStore()

    @Published private(set) var servers: [MCPServerConfig] = []
    @Published private(set) var lastError: String? = nil

    private var fileSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var suppressReloadUntil: Date = .distantPast

    private init() {
        reload()
        startWatching()
    }

    deinit {
        fileSource?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    // MARK: - Mutations

    func reload() {
        servers = CodexConfigToml.loadServers()
        lastError = nil
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
            // Suppress the file-watcher reload that our own write will
            // trigger so we don't fight ourselves with an inflight save.
            suppressReloadUntil = Date().addingTimeInterval(0.5)
            try CodexConfigToml.saveServers(servers)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - File watching

    private func startWatching() {
        let url = CodexConfigToml.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // Nothing to watch yet. Codex creates the file on first run;
            // we'll restart watching at next reload().
            return
        }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd
        let queue = DispatchQueue.main
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if Date() < self.suppressReloadUntil { return }
            self.reload()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        source.resume()
        fileSource = source
    }
}
