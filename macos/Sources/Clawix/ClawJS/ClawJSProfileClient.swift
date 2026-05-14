import Foundation

private struct ProfileEmptyResponse: Decodable {}

/// HTTP client for the marketplace/2.0.0 Profile surface exposed by `@clawjs/index`.
/// Wraps `/v1/profile/*`, `/v1/feed`, `/v1/chats/*`, `/v1/marketplace/*` and
/// `/v1/peers/*`. The daemon-side `@clawjs/profile` package owns all crypto;
/// this client only ferries already-serialised payloads.
struct ClawJSProfileClient {

    var indexClient: ClawJSIndexClient

    // MARK: - Profile

    struct Handle: Codable, Equatable, Hashable {
        let alias: String
        let fingerprint: String
        let rootPubkey: String
    }

    struct BlockRef: Codable, Equatable, Hashable {
        let blockId: String
        let vertical: String
        let archetype: String
        let updatedAt: Int
    }

    struct Group: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let label: String?
        let members: [String]
        let createdAt: Int
        let updatedAt: Int
        let inviteLink: InviteLink?

        struct InviteLink: Codable, Equatable, Hashable {
            let token: String
            let expiresAt: Int
            let usedCount: Int
        }
    }

    struct Profile: Codable, Equatable, Hashable {
        let rootPubkey: String
        let handle: Handle
        let blocks: [BlockRef]
        let groups: [Group]
        let version: Int
        let updatedAt: Int
    }

    struct InitResponse: Codable, Equatable {
        let profile: Profile
        let mnemonic: String
    }

    func initProfile(alias: String, mnemonic: String? = nil, passphrase: String? = nil) async throws -> InitResponse {
        var body: [String: AnyJSON] = ["alias": .string(alias)]
        if let mnemonic = mnemonic { body["mnemonic"] = .string(mnemonic) }
        if let passphrase = passphrase { body["passphrase"] = .string(passphrase) }
        return try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/init", method: "POST", body: body)
    }

    func me() async throws -> Profile? {
        struct R: Decodable { let profile: Profile? }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/me", method: "GET")
        return r.profile
    }

    @discardableResult
    func setHandle(alias: String) async throws -> Profile {
        struct R: Decodable { let profile: Profile }
        let body: [String: AnyJSON] = ["alias": .string(alias)]
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/handle", method: "POST", body: body)
        return r.profile
    }

    // MARK: - Blocks

    struct Block: Codable, Equatable, Hashable, Identifiable {
        let blockId: String
        let archetype: String
        let vertical: String
        let audience: Audience
        let fieldsPerLevel: [String: [String]]
        let trackingRef: TrackingRef?
        let overlay: [String: AnyJSON]?
        let content: [String: AnyJSON]?
        let createdAt: Int
        let updatedAt: Int
        let version: Int

        var id: String { blockId }

        struct Audience: Codable, Equatable, Hashable {
            let groups: [String]
        }

        struct TrackingRef: Codable, Equatable, Hashable {
            let module: String
            let recordId: String
            let snapshotHash: String?
        }
    }

    struct CreateBlockInput: Encodable {
        let vertical: String
        let archetype: String
        let audience: Audience
        let fieldsPerLevel: [String: [String]]
        let content: [String: AnyJSON]?
        let overlay: [String: AnyJSON]?
        let trackingRef: TrackingRefInput?

        struct Audience: Encodable {
            let groups: [String]
        }

        struct TrackingRefInput: Encodable {
            let module: String
            let recordId: String
        }
    }

    func listBlocks(vertical: String? = nil) async throws -> [Block] {
        struct R: Decodable { let blocks: [Block] }
        let suffix = queryString(["vertical": vertical])
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/blocks\(suffix)", method: "GET")
        return r.blocks
    }

    @discardableResult
    func createBlock(_ input: CreateBlockInput) async throws -> Block {
        struct R: Decodable { let block: Block }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/blocks", method: "POST", body: input)
        return r.block
    }

    func getBlock(_ blockId: String) async throws -> Block? {
        struct R: Decodable { let block: Block? }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/blocks/\(blockId)", method: "GET")
        return r.block
    }

    func deleteBlock(_ blockId: String) async throws {
        let _: ProfileEmptyResponse = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/blocks/\(blockId)", method: "DELETE")
    }

    // MARK: - Groups

    func listGroups() async throws -> [Group] {
        struct R: Decodable { let groups: [Group] }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/groups", method: "GET")
        return r.groups
    }

    @discardableResult
    func createGroup(id: String, label: String? = nil) async throws -> Group {
        struct R: Decodable { let group: Group }
        var body: [String: AnyJSON] = ["id": .string(id)]
        if let label = label { body["label"] = .string(label) }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/groups", method: "POST", body: body)
        return r.group
    }

    @discardableResult
    func addMember(groupId: String, rootPubkeyHex: String) async throws -> Group {
        struct R: Decodable { let group: Group }
        let body: [String: AnyJSON] = ["rootPubkey": .string(rootPubkeyHex)]
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/groups/\(groupId)/members", method: "POST", body: body)
        return r.group
    }

    @discardableResult
    func removeMember(groupId: String, rootPubkeyHex: String) async throws -> Group {
        struct R: Decodable { let group: Group }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/groups/\(groupId)/members/\(rootPubkeyHex)", method: "DELETE")
        return r.group
    }

    struct InviteLinkResponse: Codable, Equatable {
        let link: Group.InviteLink
    }

    func issueInviteLink(groupId: String, ttlSeconds: Int? = nil, maxUses: Int? = nil) async throws -> Group.InviteLink {
        var body: [String: AnyJSON] = [:]
        if let ttl = ttlSeconds { body["ttlSeconds"] = .number(Double(ttl)) }
        if let max = maxUses { body["maxUses"] = .number(Double(max)) }
        let r: InviteLinkResponse = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/groups/\(groupId)/invite-link", method: "POST", body: body)
        return r.link
    }

    // MARK: - Capabilities

    struct Capability: Codable, Equatable, Hashable, Identifiable {
        let capId: String
        let blockId: String
        let level: String
        let issuedTo: String?
        let issuedAt: Int
        let expiresAt: Int

        var id: String { capId }
    }

    @discardableResult
    func issueCapability(blockId: String, level: String, issuedToHex: String? = nil, ttlSeconds: Int? = nil) async throws -> Capability {
        struct R: Decodable { let capability: Capability }
        var body: [String: AnyJSON] = ["blockId": .string(blockId), "level": .string(level)]
        if let issuedToHex = issuedToHex { body["issuedToHex"] = .string(issuedToHex) }
        if let ttl = ttlSeconds { body["ttlSeconds"] = .number(Double(ttl)) }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/profile/capabilities/issue", method: "POST", body: body)
        return r.capability
    }

    // MARK: - Peers

    struct PeerDirectoryEntry: Codable, Equatable, Hashable, Identifiable {
        let handle: Handle
        let trustedLocally: Bool

        var id: String { handle.fingerprint }
    }

    func listPeers() async throws -> [PeerDirectoryEntry] {
        struct R: Decodable { let peers: [PeerDirectoryEntry] }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/peers/directory", method: "GET")
        return r.peers
    }

    @discardableResult
    func pairByFingerprint(pairingLink: String) async throws -> Handle {
        struct R: Decodable { let handle: Handle }
        let body: [String: AnyJSON] = ["pairingLink": .string(pairingLink)]
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/peers/pair-by-fingerprint", method: "POST", body: body)
        return r.handle
    }

    // MARK: - Feed

    struct FeedEntry: Codable, Equatable, Hashable, Identifiable {
        let blockId: String
        let vertical: String
        let owner: Owner
        let publishedAt: Int
        let preview: [String: AnyJSON]

        var id: String { blockId }

        struct Owner: Codable, Equatable, Hashable {
            let rootPubkey: String
            let handle: Handle
        }
    }

    func listFeed(vertical: String? = nil, groupId: String? = nil, keywords: String? = nil, limit: Int = 50) async throws -> [FeedEntry] {
        struct R: Decodable { let entries: [FeedEntry] }
        let suffix = queryString([
            "vertical": vertical, "groupId": groupId, "keywords": keywords,
            "limit": String(limit),
        ])
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/feed\(suffix)", method: "GET")
        return r.entries
    }

    // MARK: - Chats

    struct ChatThread: Codable, Equatable, Hashable, Identifiable {
        let peer: Peer
        let lastMessageAt: Int
        let unreadCount: Int

        var id: String { peer.handle.fingerprint }

        struct Peer: Codable, Equatable, Hashable {
            let rootPubkey: String
            let handle: Handle
        }
    }

    struct ChatMessage: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let threadPeerRootPubkey: String
        let fromMe: Bool
        let body: String
        let sentAt: Int
        let draftFromAgent: Bool
    }

    func listChats() async throws -> [ChatThread] {
        struct R: Decodable { let threads: [ChatThread] }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/chats", method: "GET")
        return r.threads
    }

    func listMessages(peer: String, limit: Int = 50, before: Int? = nil) async throws -> [ChatMessage] {
        struct R: Decodable { let messages: [ChatMessage] }
        var pairs: [String: String?] = ["limit": String(limit)]
        if let b = before { pairs["before"] = String(b) }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/chats/\(peer)/messages\(queryString(pairs))", method: "GET")
        return r.messages
    }

    @discardableResult
    func sendMessage(peer: String, body: String) async throws -> ChatMessage {
        struct R: Decodable { let message: ChatMessage }
        let payload: [String: AnyJSON] = ["body": .string(body)]
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/chats/\(peer)/messages", method: "POST", body: payload)
        return r.message
    }

    func markRead(peer: String) async throws {
        let _: ProfileEmptyResponse = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/chats/\(peer)/read", method: "POST")
    }

    // MARK: - Marketplace

    struct DiscoveredIntent: Codable, Equatable, Hashable, Identifiable {
        let intentId: String
        let vertical: String
        let side: String
        let fields: [String: AnyJSON]
        let geoZone: String?
        let tag: String?
        let priceBand: Int?
        let expiresAt: Int
        let ownerHandle: Handle?

        var id: String { intentId }
    }

    struct ExpressInterestResult: Codable, Equatable {
        let capabilityId: String
        let mailboxMessageId: String
    }

    func discoveredIntents(vertical: String? = nil, geoZone: String? = nil, tag: String? = nil, priceBand: Int? = nil, limit: Int = 100) async throws -> [DiscoveredIntent] {
        struct R: Decodable { let intents: [DiscoveredIntent] }
        var pairs: [String: String?] = [
            "vertical": vertical, "geoZone": geoZone, "tag": tag,
            "limit": String(limit),
        ]
        if let band = priceBand { pairs["priceBand"] = String(band) }
        let r: R = try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/marketplace/discovered-intents\(queryString(pairs))", method: "GET")
        return r.intents
    }

    @discardableResult
    func expressInterest(intentId: String, template: String? = nil) async throws -> ExpressInterestResult {
        var body: [String: AnyJSON] = ["intentId": .string(intentId)]
        if let template = template { body["bodyTemplate"] = .string(template) }
        return try await indexClient.send("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/marketplace/express-interest", method: "POST", body: body)
    }

    // MARK: - Helpers

    private func queryString(_ pairs: [String: String?]) -> String {
        let items = pairs.compactMap { key, value -> URLQueryItem? in
            guard let value = value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        guard !items.isEmpty else { return "" }
        var c = URLComponents()
        c.queryItems = items
        return c.percentEncodedQuery.map { "?\($0)" } ?? ""
    }
}
