import Foundation

/// Imperative API the chat agent (or any caller: keyboard shortcut, MCP
/// adapter, AppleScript) invokes to operate on the Drive. The same
/// surface is exposed both to the LLM (as tool calls dispatched via the
/// agent backend) and to the UI (as menu actions). Destructive operations
/// require an explicit `confirm: true`; read-only and additive operations
/// run without a prompt by design.
@MainActor
enum DriveTools {

    static var sharedManager: DriveManager?

    static func bind(_ manager: DriveManager) {
        sharedManager = manager
    }

    private static func require() throws -> DriveManager {
        guard let manager = sharedManager else {
            throw NSError(domain: "DriveTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "Drive manager is not bound."])
        }
        return manager
    }

    // MARK: - Tools

    static func upload(fileURL: URL, parentId: String? = nil, projectSlug: String? = nil) async throws -> ClawJSDriveClient.DriveItemDetail {
        let manager = try require()
        let resolvedParent: String?
        if let projectSlug = projectSlug {
            resolvedParent = try await manager.client.ensureProjectFolder(slug: projectSlug)
        } else {
            resolvedParent = parentId
        }
        let result = await manager.upload(fileURL: fileURL, parentId: resolvedParent)
        switch result {
        case .success(let detail): return detail
        case .failure(let error):
            if case .duplicateExists(let existing) = error {
                throw NSError(domain: "DriveTools", code: 409, userInfo: [
                    NSLocalizedDescriptionKey: "Already exists",
                    "existingItemId": existing.id,
                ])
            }
            throw error
        }
    }

    static func find(_ query: String, semantic: Bool = false, limit: Int = 20) async throws -> [ClawJSDriveClient.DriveItem] {
        let manager = try require()
        if semantic {
            let results = try await manager.client.searchSemantic(query, limit: limit)
            return results.map { $0.item }
        }
        return try await manager.client.searchText(query)
    }

    static func read(itemId: String) async throws -> Data {
        let manager = try require()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(itemId)-\(UUID().uuidString)")
        try await manager.client.downloadItem(itemId, to: temp)
        try await manager.client.markViewed(itemId)
        defer { try? FileManager.default.removeItem(at: temp) }
        return try Data(contentsOf: temp)
    }

    static func share(_ itemId: String, mode: ShareMode, ttlMinutes: Int = 10, agentName: String = "agent") async throws -> ShareDescriptor {
        let manager = try require()
        switch mode {
        case .read(let label):
            let r = try await manager.client.createReadShare(itemId, label: label)
            return ShareDescriptor(mode: "read", id: r.share.id, payload: ["url": r.url, "token": r.token])
        case .tailnet:
            let r = try await manager.client.createTailnetShare(itemId)
            return ShareDescriptor(mode: "tailnet", id: r.id, payload: ["magicdnsName": r.magicdnsName])
        case .publicTunnel:
            let r = try await manager.client.createTunnelShare(itemId)
            return ShareDescriptor(mode: "public_tunnel", id: r.id, payload: ["url": r.tunnelUrl, "status": r.status])
        case .agent(let capabilityKind, let reason):
            let r = try await manager.client.createAgentShare(itemId, capabilityKind: capabilityKind, ttlMinutes: ttlMinutes, reason: reason, agentName: agentName)
            return ShareDescriptor(mode: "agent", id: r.record.id, payload: ["token": r.token, "expiresAt": r.record.expiresAt])
        }
    }

    static func organize(itemId: String, newParentId: String? = nil, newName: String? = nil) async throws -> ClawJSDriveClient.DriveItemDetail {
        let manager = try require()
        if let newName = newName {
            _ = try await manager.client.updateItem(itemId, name: newName)
        }
        if let newParentId = newParentId {
            return try await manager.client.moveItem(itemId, parentId: newParentId)
        }
        return try await manager.client.getItem(itemId)
    }

    /// Destructive: the caller must pass `confirm: true`. The agent SHOULD
    /// surface a confirmation prompt to the user before invoking with
    /// confirm=true.
    @discardableResult
    static func delete(itemId: String, confirm: Bool) async throws -> Bool {
        guard confirm else {
            throw NSError(domain: "DriveTools", code: 412, userInfo: [
                NSLocalizedDescriptionKey: "Drive delete requires explicit confirmation.",
            ])
        }
        let manager = try require()
        return try await manager.client.deleteItem(itemId)
    }

    enum ShareMode {
        case read(label: String)
        case tailnet
        case publicTunnel
        case agent(capabilityKind: String, reason: String?)
    }

    struct ShareDescriptor {
        let mode: String
        let id: String
        let payload: [String: String]
    }
}
