import Foundation

/// HTTP client for the bundled `clawjs/publishing` service. Mirrors the wire
/// shape of `clawjs/publishing/src/server/routes/v1/index.ts` and the types in
/// `clawjs/publishing/src/shared/types.ts`. Follows the same pattern as
/// `ClawJSDriveClient`: per-request URLSession wrapper, bearer-token auth,
/// typed Codable responses.
final class ClawJSPublishingClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "Publishing service is not running."
            case .invalidURL:      return "Could not build a URL for the publishing service."
            case .http(let status, let body): return "Publishing returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):  return "Could not decode publishing response: \(error.localizedDescription)"
            case .transport(let error): return "Could not reach publishing service: \(error.localizedDescription)"
            }
        }
    }

    private let session: URLSession
    private let origin: URL
    var bearerToken: String?
    /// Optional workspace id sent as `X-Publishing-Workspace`. The publishing
    /// daemon uses it to scope the ephemeral admin principal to a specific
    /// workspace; the rest of the routes already take the workspace id in
    /// their path, so the header is only honoured for unscoped calls.
    var workspaceId: String?

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    init(
        bearerToken: String? = nil,
        workspaceId: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.publishing.port)")!,
        session: URLSession = ClawJSPublishingClient.defaultSession
    ) {
        self.bearerToken = bearerToken
        self.workspaceId = workspaceId
        self.origin = origin
        self.session = session
    }

    // MARK: - Wire types

    struct Workspace: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let slug: String
        let defaultTimezone: String?
        let defaultLocale: String?
        let createdAt: Double?

        enum CodingKeys: String, CodingKey {
            case id, name, slug
            case defaultTimezone = "default_timezone"
            case defaultLocale = "default_locale"
            case createdAt = "created_at"
        }
    }

    struct WorkspaceListResponse: Decodable { let workspaces: [Workspace] }
    struct WorkspaceCreateResponse: Decodable { let workspace: Workspace }

    struct FamilyText: Codable, Hashable {
        let minChars: Int?
        let maxChars: Int
        let supportsMarkdown: Bool
        let supportsMentions: Bool
        let supportsHashtags: Bool
    }

    struct FamilyCapabilities: Codable, Hashable {
        let contentKinds: [String]
        let text: FamilyText
        let multiVariant: String
    }

    struct Family: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let group: String
        let authKind: String
        let capabilities: FamilyCapabilities
    }

    struct FamilyListResponse: Decodable { let families: [Family] }

    struct ChannelAccount: Codable, Identifiable, Hashable {
        let id: String
        let workspaceId: String
        let familyId: String
        let providerAccountId: String
        let displayName: String
        let handle: String?
        let avatarUrl: String?
        let authorized: Bool
        let createdAt: Double
    }

    struct ChannelAccountListResponse: Decodable { let accounts: [ChannelAccount] }
    struct ChannelAccountCreateResponse: Decodable { let account: ChannelAccount }

    /// Mirrors `PostRow` from `clawjs/publishing/src/server/domain/posts.ts`.
    /// Timestamps land as epoch milliseconds (publishing uses `Date.now()`),
    /// so they come through as `Double` and the caller converts.
    struct Post: Codable, Identifiable, Hashable {
        let id: String
        let workspaceId: String
        let editorialStatus: String
        let publishStatus: String
        let scheduledAt: Double?
        let publishedAt: Double?
        let createdAt: Double
        let updatedAt: Double

        enum CodingKeys: String, CodingKey {
            case id
            case workspaceId = "workspace_id"
            case editorialStatus = "editorial_status"
            case publishStatus = "publish_status"
            case scheduledAt = "scheduled_at"
            case publishedAt = "published_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        var scheduledDate: Date? {
            scheduledAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        }

        var publishedDate: Date? {
            publishedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        }
    }

    struct PostListResponse: Decodable { let posts: [Post] }
    struct PostCreateResponse: Decodable { let post: Post }
    struct PostScheduleResponse: Decodable { let post: Post }

    /// Spec the composer hands to `createPost`. Mirrors `PostSpec` from
    /// `clawjs/publishing/src/shared/types.ts`, narrowed to the fields the v1
    /// composer needs (single original variant; per-account variant
    /// override goes through a separate `variants` endpoint in v2).
    struct PostSpec: Encodable {
        let accounts: [String]
        let editorialStatus: String?
        let schedule: Schedule?
        let variants: [Variant]

        struct Schedule: Encodable {
            let kind: String
            let at: String?
            let timezone: String?

            static func now() -> Schedule { .init(kind: "now", at: nil, timezone: nil) }
            static func datetime(_ iso: String, timezone: String? = nil) -> Schedule {
                .init(kind: "datetime", at: iso, timezone: timezone)
            }
            static let unscheduled = Schedule(kind: "unscheduled", at: nil, timezone: nil)
        }

        struct Variant: Encodable {
            let isOriginal: Bool?
            let channelAccountId: String?
            let blocks: [Block]

            enum CodingKeys: String, CodingKey {
                case isOriginal = "is_original"
                case channelAccountId = "channel_account_id"
                case blocks
            }
        }

        struct Block: Encodable {
            let body: String
        }

        enum CodingKeys: String, CodingKey {
            case accounts
            case editorialStatus = "editorial_status"
            case schedule
            case variants
        }
    }

    // MARK: - Workspaces

    func listWorkspaces() async throws -> [Workspace] {
        let response: WorkspaceListResponse = try await get("/v1/workspaces")
        return response.workspaces
    }

    func createWorkspace(name: String) async throws -> Workspace {
        let response: WorkspaceCreateResponse = try await post(
            "/v1/workspaces",
            body: ["name": name]
        )
        return response.workspace
    }

    // MARK: - Families

    func listFamilies() async throws -> [Family] {
        let response: FamilyListResponse = try await get("/v1/families")
        return response.families
    }

    // MARK: - Channels

    func listChannels(workspaceId: String) async throws -> [ChannelAccount] {
        let response: ChannelAccountListResponse = try await get(
            "/v1/ws/\(workspaceId)/channels"
        )
        return response.accounts
    }

    func connectChannel(
        workspaceId: String,
        familyId: String,
        payload: [String: String]
    ) async throws -> ChannelAccount {
        let response: ChannelAccountCreateResponse = try await post(
            "/v1/ws/\(workspaceId)/channels/connect/\(familyId)",
            body: payload as [String: Any]
        )
        return response.account
    }

    @discardableResult
    func disconnectChannel(workspaceId: String, accountId: String) async throws -> Bool {
        struct R: Decodable { let ok: Bool }
        let r: R = try await delete("/v1/ws/\(workspaceId)/channels/\(accountId)")
        return r.ok
    }

    @discardableResult
    func probeChannel(workspaceId: String, accountId: String) async throws -> Bool {
        struct R: Decodable { let ok: Bool }
        let r: R = try await post(
            "/v1/ws/\(workspaceId)/channels/\(accountId)/probe",
            body: nil
        )
        return r.ok
    }

    // MARK: - Posts

    func listPosts(
        workspaceId: String,
        from: Date? = nil,
        to: Date? = nil,
        status: String? = nil,
        limit: Int? = nil
    ) async throws -> [Post] {
        var components = URLComponents(string: "/v1/ws/\(workspaceId)/posts")!
        var items: [URLQueryItem] = []
        if let from { items.append(URLQueryItem(name: "from", value: ClawJSPublishingClient.iso8601(from))) }
        if let to   { items.append(URLQueryItem(name: "to",   value: ClawJSPublishingClient.iso8601(to))) }
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let limit  { items.append(URLQueryItem(name: "limit",  value: String(limit))) }
        if !items.isEmpty { components.queryItems = items }
        let response: PostListResponse = try await get(components.url!.absoluteString)
        return response.posts
    }

    func createPost(workspaceId: String, spec: PostSpec) async throws -> Post {
        let response: PostCreateResponse = try await postJSON(
            "/v1/ws/\(workspaceId)/posts",
            payload: spec
        )
        return response.post
    }

    func schedulePost(workspaceId: String, postId: String, at date: Date) async throws -> Post {
        let response: PostScheduleResponse = try await post(
            "/v1/ws/\(workspaceId)/posts/\(postId)/schedule",
            body: ["at": ClawJSPublishingClient.iso8601(date)]
        )
        return response.post
    }

    // MARK: - Helpers

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    // MARK: - Internal HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: String, body: Any?) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    private func postJSON<T: Decodable, E: Encodable>(_ path: String, payload: E) async throws -> T {
        try await encodedRequest(path: path, method: "POST", payload: payload)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "DELETE", body: nil)
    }

    private func request<T: Decodable>(path: String, method: String, body: Any?) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let workspaceId, !workspaceId.isEmpty {
            request.setValue(workspaceId, forHTTPHeaderField: "X-Publishing-Workspace")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let cleaned = sanitize(body)
            request.httpBody = try JSONSerialization.data(withJSONObject: cleaned, options: [])
        }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw Error.transport(error) }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.transport(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Error.decoding(error) }
    }

    private func encodedRequest<T: Decodable, E: Encodable>(
        path: String,
        method: String,
        payload: E
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let workspaceId, !workspaceId.isEmpty {
            request.setValue(workspaceId, forHTTPHeaderField: "X-Publishing-Workspace")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw Error.transport(error) }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.transport(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Error.decoding(error) }
    }

    private func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                let cleaned = sanitize(child)
                if cleaned is NSNull { continue }
                out[key] = cleaned
            }
            return out
        }
        if value is NSNull { return NSNull() }
        if let optional = value as? Optional<Any>, optional == nil { return NSNull() }
        return value
    }
}
