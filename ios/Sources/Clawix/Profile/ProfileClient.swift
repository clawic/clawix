import Foundation

/// iOS-side HTTP client mirror of `ClawJSProfileClient`. Hits the daemon
/// running on the paired Mac (or a self-hosted local node) for the
/// `/v1/profile/*`, `/v1/feed`, `/v1/chats/*`, `/v1/marketplace/*`,
/// `/v1/peers/*` surfaces.
struct ProfileClient {

    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid daemon URL."
            case .http(let status, let body): return "HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error): return error.localizedDescription
            case .transport(let error): return error.localizedDescription
            }
        }
    }

    let origin: URL
    let bearer: String?
    let session: URLSession

    init(origin: URL, bearer: String? = nil, session: URLSession = .shared) {
        self.origin = origin
        self.bearer = bearer
        self.session = session
    }

    struct Handle: Codable, Equatable, Hashable {
        let alias: String
        let fingerprint: String
        let rootPubkey: String
    }

    struct Profile: Codable, Equatable, Hashable {
        let rootPubkey: String
        let handle: Handle
        let version: Int
        let updatedAt: Int
    }

    struct FeedEntry: Codable, Equatable, Hashable, Identifiable {
        let blockId: String
        let vertical: String
        let owner: Owner
        let publishedAt: Int
        let preview: [String: AnyValue]

        var id: String { blockId }

        struct Owner: Codable, Equatable, Hashable {
            let rootPubkey: String
            let handle: Handle
        }
    }

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

    struct DiscoveredIntent: Codable, Equatable, Hashable, Identifiable {
        let intentId: String
        let vertical: String
        let side: String
        let fields: [String: AnyValue]
        let geoZone: String?
        let tag: String?
        let priceBand: Int?
        let expiresAt: Int
        let ownerHandle: Handle?

        var id: String { intentId }
    }

    // MARK: - Top-level calls

    func me() async throws -> Profile? {
        struct R: Decodable { let profile: Profile? }
        let r: R = try await get(path: "/v1/profile/me")
        return r.profile
    }

    func listFeed(limit: Int = 100) async throws -> [FeedEntry] {
        struct R: Decodable { let entries: [FeedEntry] }
        let r: R = try await get(path: "/v1/feed?limit=\(limit)")
        return r.entries
    }

    func listChats() async throws -> [ChatThread] {
        struct R: Decodable { let threads: [ChatThread] }
        let r: R = try await get(path: "/v1/chats")
        return r.threads
    }

    func listMessages(peer: String, limit: Int = 100) async throws -> [ChatMessage] {
        struct R: Decodable { let messages: [ChatMessage] }
        let r: R = try await get(path: "/v1/chats/\(peer)/messages?limit=\(limit)")
        return r.messages
    }

    @discardableResult
    func sendMessage(peer: String, body: String) async throws -> ChatMessage {
        struct R: Decodable { let message: ChatMessage }
        let r: R = try await post(path: "/v1/chats/\(peer)/messages", body: ["body": body])
        return r.message
    }

    func discoveredIntents(vertical: String? = nil, limit: Int = 100) async throws -> [DiscoveredIntent] {
        struct R: Decodable { let intents: [DiscoveredIntent] }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            vertical.map { URLQueryItem(name: "vertical", value: $0) },
        ].compactMap { $0 }
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let r: R = try await get(path: "/v1/marketplace/discovered-intents\(suffix)")
        return r.intents
    }

    @discardableResult
    func expressInterest(intentId: String) async throws -> [String: AnyValue] {
        return try await post(path: "/v1/marketplace/express-interest", body: ["intentId": intentId])
    }

    @discardableResult
    func pair(pairingLink: String) async throws -> Handle {
        struct R: Decodable { let handle: Handle }
        let r: R = try await post(path: "/v1/peers/pair-by-fingerprint", body: ["pairingLink": pairingLink])
        return r.handle
    }

    // MARK: - HTTP plumbing

    private func get<T: Decodable>(path: String) async throws -> T {
        var req = try makeRequest(path: path)
        req.httpMethod = "GET"
        return try await execute(req: req)
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var req = try makeRequest(path: path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(req: req)
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var req = URLRequest(url: url)
        if let bearer = bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func execute<T: Decodable>(req: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw Error.transport(error) }
        guard let http = response as? HTTPURLResponse else { throw Error.invalidURL }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Error.decoding(error) }
    }
}

/// Minimal JSON value enum so we can decode arbitrary `preview` / `fields`
/// dictionaries from the daemon without giving up Codable.
indirect enum AnyValue: Codable, Hashable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AnyValue])
    case object([String: AnyValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AnyValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: AnyValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value.")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
