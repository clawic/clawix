import Combine
import Foundation

/// @MainActor orchestrator for the Profile / Feed / Chats / Marketplace
/// surfaces. Owns the HTTP client, publishes state for SwiftUI views, and
/// schedules background refreshes.
@MainActor
final class ProfileManager: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var me: ClawJSProfileClient.Profile?
    @Published private(set) var ownBlocks: [ClawJSProfileClient.Block] = []
    @Published private(set) var groups: [ClawJSProfileClient.Group] = []
    @Published private(set) var peers: [ClawJSProfileClient.PeerDirectoryEntry] = []
    @Published private(set) var feedEntries: [ClawJSProfileClient.FeedEntry] = []
    @Published private(set) var chatThreads: [ClawJSProfileClient.ChatThread] = []
    @Published private(set) var marketplaceIntents: [ClawJSProfileClient.DiscoveredIntent] = []

    @Published var selectedVertical: String?
    @Published var selectedGroupId: String?
    @Published var feedKeywords: String = ""

    private var client: ClawJSProfileClient

    init() {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
        let index = ClawJSIndexClient(bearerToken: token)
        self.client = ClawJSProfileClient(indexClient: index)
    }

    func ensureToken() {
        if client.indexClient.bearerToken == nil {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
            client.indexClient.bearerToken = token
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        ensureToken()
        loadState = .loading
        do {
            async let me = client.me()
            async let groups = client.listGroups()
            async let blocks = client.listBlocks()
            async let peers = client.listPeers()
            async let feed = client.listFeed(limit: 100)
            async let chats = client.listChats()
            async let intents = client.discoveredIntents(limit: 100)
            self.me = try await me
            self.groups = try await groups
            self.ownBlocks = try await blocks
            self.peers = try await peers
            self.feedEntries = try await feed
            self.chatThreads = try await chats
            self.marketplaceIntents = try await intents
            loadState = .ready
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    func refreshFeed() async {
        ensureToken()
        do {
            self.feedEntries = try await client.listFeed(
                vertical: selectedVertical,
                groupId: selectedGroupId,
                keywords: feedKeywords.isEmpty ? nil : feedKeywords,
                limit: 100,
            )
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    func refreshChats() async {
        ensureToken()
        do { self.chatThreads = try await client.listChats() }
        catch { loadState = .error(error.localizedDescription) }
    }

    func refreshMarketplace() async {
        ensureToken()
        do {
            self.marketplaceIntents = try await client.discoveredIntents(
                vertical: selectedVertical, limit: 100,
            )
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Mutations

    func initProfile(alias: String, mnemonic: String?) async throws -> ClawJSProfileClient.InitResponse {
        ensureToken()
        let resp = try await client.initProfile(alias: alias, mnemonic: mnemonic)
        self.me = resp.profile
        return resp
    }

    func renameHandle(to alias: String) async throws {
        ensureToken()
        let updated = try await client.setHandle(alias: alias)
        self.me = updated
    }

    func createBlock(_ input: ClawJSProfileClient.CreateBlockInput) async throws {
        ensureToken()
        let block = try await client.createBlock(input)
        self.ownBlocks.insert(block, at: 0)
    }

    func deleteBlock(_ blockId: String) async throws {
        ensureToken()
        try await client.deleteBlock(blockId)
        self.ownBlocks.removeAll { $0.blockId == blockId }
    }

    func createGroup(id: String, label: String? = nil) async throws {
        ensureToken()
        let g = try await client.createGroup(id: id, label: label)
        self.groups.append(g)
    }

    func addMember(groupId: String, rootPubkeyHex: String) async throws {
        ensureToken()
        let updated = try await client.addMember(groupId: groupId, rootPubkeyHex: rootPubkeyHex)
        if let idx = groups.firstIndex(where: { $0.id == updated.id }) {
            groups[idx] = updated
        }
    }

    func pair(link: String) async throws -> ClawJSProfileClient.Handle {
        ensureToken()
        let handle = try await client.pairByFingerprint(pairingLink: link)
        // Refresh the directory so the new peer is visible immediately.
        self.peers = (try? await client.listPeers()) ?? self.peers
        return handle
    }

    func issueCapability(blockId: String, level: String, ttlSeconds: Int? = nil) async throws -> ClawJSProfileClient.Capability {
        ensureToken()
        return try await client.issueCapability(blockId: blockId, level: level, ttlSeconds: ttlSeconds)
    }

    func sendMessage(peer: String, body: String) async throws -> ClawJSProfileClient.ChatMessage {
        ensureToken()
        return try await client.sendMessage(peer: peer, body: body)
    }

    func loadMessages(peer: String) async throws -> [ClawJSProfileClient.ChatMessage] {
        ensureToken()
        return try await client.listMessages(peer: peer, limit: 100)
    }

    func expressInterest(intentId: String) async throws -> ClawJSProfileClient.ExpressInterestResult {
        ensureToken()
        return try await client.expressInterest(intentId: intentId)
    }
}
