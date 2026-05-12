import Foundation

/// Thin client for the mp/1.0.0 endpoints exposed by `@clawjs/index`.
/// Cryptographic work (key generation, signing, sealed-box) is owned by the
/// daemon-side `@clawjs/mp` package; this client only ferries blobs already
/// produced there.
struct ClawJSMpClient {

    var indexClient: ClawJSIndexClient

    // MARK: - Identity

    struct RootKey: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let pubkey: String       // base64
        let label: String?
        let createdAt: String
        let revokedAt: String?
    }

    struct DeviceKey: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let rootKeyId: String
        let pubkey: String
        let deviceName: String
        let certificateCbor: String
        let createdAt: String
        let revokedAt: String?
    }

    struct RoleKey: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let rootKeyId: String
        let pubkey: String
        let roleName: String
        let vertical: String
        let certificateCbor: String
        let createdAt: String
        let revokedAt: String?
    }

    func listRoots() async throws -> [RootKey] {
        struct R: Decodable { let roots: [RootKey] }
        let resp: R = try await indexClient.send("/v1/mp/identity/roots", method: "GET")
        return resp.roots
    }

    func listDevices(rootKeyId: String? = nil) async throws -> [DeviceKey] {
        struct R: Decodable { let devices: [DeviceKey] }
        let suffix = queryString(["rootKeyId": rootKeyId])
        let resp: R = try await indexClient.send("/v1/mp/identity/devices\(suffix)", method: "GET")
        return resp.devices
    }

    func listRoles(rootKeyId: String? = nil, vertical: String? = nil) async throws -> [RoleKey] {
        struct R: Decodable { let roles: [RoleKey] }
        let suffix = queryString(["rootKeyId": rootKeyId, "vertical": vertical])
        let resp: R = try await indexClient.send("/v1/mp/identity/roles\(suffix)", method: "GET")
        return resp.roles
    }

    // MARK: - Intents

    struct Intent: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let intentIdHash: String       // base64
        let side: String                // "offer" or "want"
        let roleKeyId: String?
        let vertical: String
        let payload: AnyJSON
        let visibilityLevels: [String: Int]
        let provenance: String          // "native" or "observed"
        let observedSource: String?
        let observedExternalUrl: String?
        let status: String
        let expiresAt: String?
        let createdAt: String
        let publishedAt: String?
        let withdrawnAt: String?
    }

    func listIntents(filter: IntentFilter = .init()) async throws -> [Intent] {
        struct R: Decodable { let intents: [Intent] }
        let suffix = queryString([
            "side": filter.side,
            "vertical": filter.vertical,
            "status": filter.status,
            "provenance": filter.provenance,
            "roleKeyId": filter.roleKeyId,
        ])
        let resp: R = try await indexClient.send("/v1/mp/intents\(suffix)", method: "GET")
        return resp.intents
    }

    struct IntentFilter {
        var side: String? = nil
        var vertical: String? = nil
        var status: String? = nil
        var provenance: String? = nil
        var roleKeyId: String? = nil
    }

    func updateIntentStatus(id: String, status: String) async throws {
        let body: [String: AnyJSON] = ["status": .string(status)]
        let _: EmptyResponse = try await indexClient.send("/v1/mp/intents/\(id)/status", method: "PATCH", body: body)
    }

    // MARK: - Match receipts

    struct MatchReceipt: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let receiptHash: String
        let myRoleKeyId: String
        let peerRolePubkey: String
        let offerIntentId: String?
        let wantIntentId: String?
        let reachedLevel: Int
        let fieldsRevealed: [String]
        let contactHandover: AnyJSON?
        let status: String
        let proposedAt: String
        let signedAt: String?
        let rejectedAt: String?
    }

    func listMatchReceipts(myRoleKeyId: String? = nil, status: String? = nil) async throws -> [MatchReceipt] {
        struct R: Decodable { let receipts: [MatchReceipt] }
        let suffix = queryString(["myRoleKeyId": myRoleKeyId, "status": status])
        let resp: R = try await indexClient.send("/v1/mp/match-receipts\(suffix)", method: "GET")
        return resp.receipts
    }

    // MARK: - Mailbox

    struct InboundMessage: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let recipientRoleKeyId: String
        let senderPubkey: String
        let threadId: String?
        let intentIdRef: String?
        let kind: String
        let plaintext: AnyJSON
        let receivedAt: String
        let readAt: String?
    }

    func listInbound(recipientRoleKeyId: String? = nil) async throws -> [InboundMessage] {
        struct R: Decodable { let messages: [InboundMessage] }
        let suffix = queryString(["recipientRoleKeyId": recipientRoleKeyId])
        let resp: R = try await indexClient.send("/v1/mp/mailbox/inbound\(suffix)", method: "GET")
        return resp.messages
    }

    func markRead(messageId: String) async throws {
        let _: EmptyResponse = try await indexClient.send("/v1/mp/mailbox/inbound/\(messageId)/read", method: "POST")
    }

    // MARK: - Peer levels

    struct PeerLevel: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let myRoleKeyId: String
        let peerPubkey: String
        let intentId: String?
        let currentLevel: Int
        let proofs: AnyJSON?
        let lastUpdatedAt: String
    }

    func listPeerLevels(myRoleKeyId: String? = nil) async throws -> [PeerLevel] {
        struct R: Decodable { let peers: [PeerLevel] }
        let suffix = queryString(["myRoleKeyId": myRoleKeyId])
        let resp: R = try await indexClient.send("/v1/mp/peer-levels\(suffix)", method: "GET")
        return resp.peers
    }

    // MARK: - Brokers

    struct Broker: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let brokerPubkey: String
        let endpoints: [String]
        let verticalsSupported: [String]
        let trustLocal: Bool
        let lastSeenAt: String
    }

    func listBrokers(vertical: String? = nil) async throws -> [Broker] {
        struct R: Decodable { let brokers: [Broker] }
        let suffix = queryString(["vertical": vertical])
        let resp: R = try await indexClient.send("/v1/mp/brokers\(suffix)", method: "GET")
        return resp.brokers
    }

    private func queryString(_ values: [String: String?]) -> String {
        let parts = values.compactMap { key, value -> String? in
            guard let value else { return nil }
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(escaped)"
        }
        return parts.isEmpty ? "" : "?\(parts.joined(separator: "&"))"
    }
}

private struct EmptyResponse: Decodable {}

extension ClawJSIndexClient {
    func send<T: Decodable>(_ path: String, method: String = "GET", body: Any? = nil) async throws -> T {
        try await request(path, method: method, body: body)
    }
}
