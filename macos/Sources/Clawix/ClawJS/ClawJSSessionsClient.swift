import Foundation

struct ClawJSSessionsClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case encoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "ClawJS sessions service is not running."
            case .invalidURL: return "Could not build a URL for the sessions service."
            case .http(let status, let body): return "Sessions returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error): return "Could not decode sessions response: \(error.localizedDescription)"
            case .encoding(let error): return "Could not encode sessions request: \(error.localizedDescription)"
            case .transport(let error): return "Could not reach sessions service: \(error.localizedDescription)"
            }
        }
    }

    var bearerToken: String?
    let origin: URL
    let session: URLSession

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.sessions.port)")!,
        session: URLSession = .shared
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
        self.session = session
    }

    @MainActor
    static func local() -> ClawJSSessionsClient {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .sessions)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .sessions))
        return ClawJSSessionsClient(bearerToken: token)
    }

    struct HealthResponse: Decodable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    struct Project: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let displayName: String
        let path: String
        let hidden: Bool
        let archived: Bool
        let sortRank: Int
        let createdAt: Int64
        let updatedAt: Int64
    }

    struct SessionRecord: Codable, Identifiable, Equatable {
        let id: String
        let agent: String
        let runtime: String?
        let machine: String?
        let workspaceId: String?
        let projectId: String?
        let projectPath: String?
        let runtimeAdapter: String?
        let runtimeSessionId: String?
        let title: String
        let createdAt: Int64
        let lastMessageAt: Int64?
        let messageCount: Int
        let pinned: Bool
        let archived: Bool
        let sidebarVisible: Bool
        let branch: String?
        let cwd: String?
        let status: String
        let customMetadata: AnyJSON?
    }

    struct MessageRecord: Codable, Identifiable, Equatable {
        let id: String
        let sessionId: String
        let role: String
        let contentText: String
        let contentBlocks: [AnyJSON]?
        let timestamp: Int64
        let toolCalls: [AnyJSON]?
        let timeline: [AnyJSON]?
        let workSummary: AnyJSON?
        let streamingState: String?
        let audioRef: AudioRef?
        let attachments: [AnyJSON]?
        let sourceNativeId: String?
    }

    struct AudioRef: Codable, Equatable, Hashable {
        let id: String
        let mimeType: String
        let durationMs: Int
    }

    struct ListProjectsResponse: Decodable {
        let items: [Project]
        let total: Int
    }

    struct ListSessionsResponse: Decodable {
        let items: [SessionRecord]
        let total: Int
    }

    struct MessagesResponse: Decodable {
        let items: [MessageRecord]
    }

    struct SessionWithMessages: Decodable {
        let session: SessionRecord
        let messages: [MessageRecord]
    }

    struct TurnResponse: Decodable {
        let session: SessionRecord?
        let userMessage: MessageRecord
        let assistantMessage: MessageRecord?
    }

    struct InterruptResponse: Decodable {
        let interrupted: Bool
        let session: SessionRecord
    }

    struct ImportCodexResponse: Decodable {
        struct Item: Decodable {
            let filePath: String
            let sessionId: String?
            let messagesImported: Int
            let skipped: Bool?
            let reason: String?
        }

        let scanned: Int
        let imported: [Item]
    }

    struct CreateProjectRequest: Encodable {
        let displayName: String?
        let path: String
        let hidden: Bool?
        let archived: Bool?
        let sortRank: Int?
    }

    struct CreateSessionRequest: Encodable {
        let id: String?
        let agent: String
        let runtime: String?
        let runtimeAdapter: String?
        let runtimeSessionId: String?
        let projectId: String?
        let projectPath: String?
        let title: String?
        let cwd: String?
        let branch: String?
    }

    struct StartTurnRequest: Encodable {
        let prompt: String
        let projectId: String?
        let projectPath: String?
        let cwd: String?
        let title: String?
        let attachments: [AnyJSON]?
        let audioRef: AudioRef?
        let fakeReply: String?
    }

    func probeHealth() async throws -> HealthResponse {
        try await request("/v1/health", method: "GET", authenticated: false)
    }

    func listProjects(hidden: Bool? = nil, archived: Bool? = nil) async throws -> [Project] {
        var items: [URLQueryItem] = []
        if let hidden { items.append(URLQueryItem(name: "hidden", value: hidden ? "true" : "false")) }
        if let archived { items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false")) }
        let response: ListProjectsResponse = try await request("/v1/projects", queryItems: items)
        return response.items
    }

    @discardableResult
    func createProject(_ input: CreateProjectRequest) async throws -> Project {
        try await request("/v1/projects", method: "POST", body: input)
    }

    @discardableResult
    func updateProject(id: String, patch: [String: AnyJSON]) async throws -> Project {
        try await request("/v1/projects/\(id)", method: "PATCH", body: patch)
    }

    func deleteProject(id: String) async throws {
        let _: EmptyResponse = try await request("/v1/projects/\(id)", method: "DELETE")
    }

    func listSessions(
        projectId: String? = nil,
        projectPath: String? = nil,
        pinned: Bool? = nil,
        archived: Bool? = nil,
        sidebarVisible: Bool? = nil
    ) async throws -> [SessionRecord] {
        var items: [URLQueryItem] = []
        if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }
        if let projectPath { items.append(URLQueryItem(name: "projectPath", value: projectPath)) }
        if let pinned { items.append(URLQueryItem(name: "pinned", value: pinned ? "true" : "false")) }
        if let archived { items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false")) }
        if let sidebarVisible { items.append(URLQueryItem(name: "sidebarVisible", value: sidebarVisible ? "true" : "false")) }
        let response: ListSessionsResponse = try await request("/v1/sessions", queryItems: items)
        return response.items
    }

    func getSession(id: String, includeMessages: Bool = false) async throws -> SessionWithMessages {
        let query = includeMessages ? [URLQueryItem(name: "includeMessages", value: "true")] : []
        if includeMessages {
            return try await request("/v1/sessions/\(id)", queryItems: query)
        }
        let session: SessionRecord = try await request("/v1/sessions/\(id)")
        return SessionWithMessages(session: session, messages: [])
    }

    @discardableResult
    func createSession(_ input: CreateSessionRequest) async throws -> SessionRecord {
        try await request("/v1/sessions", method: "POST", body: input)
    }

    @discardableResult
    func updateSession(id: String, patch: [String: AnyJSON]) async throws -> SessionRecord {
        try await request("/v1/sessions/\(id)", method: "PATCH", body: patch)
    }

    func listMessages(sessionId: String) async throws -> [MessageRecord] {
        let response: MessagesResponse = try await request("/v1/sessions/\(sessionId)/messages")
        return response.items
    }

    @discardableResult
    func importCodex(forceReimport: Bool = false) async throws -> ImportCodexResponse {
        struct Body: Encodable {
            let forceReimport: Bool?
        }
        return try await request(
            "/v1/sessions/import/codex",
            method: "POST",
            body: Body(forceReimport: forceReimport ? true : nil)
        )
    }

    @discardableResult
    func startTurn(sessionId: String, input: StartTurnRequest) async throws -> TurnResponse {
        try await request("/v1/sessions/\(sessionId)/turns", method: "POST", body: input)
    }

    @discardableResult
    func interrupt(sessionId: String) async throws -> InterruptResponse {
        try await request("/v1/sessions/\(sessionId)/interrupt", method: "POST", body: EmptyRequest())
    }

    private func request<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let baseURL = URL(string: path, relativeTo: origin)?.absoluteURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw Error.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let bearerToken else { throw Error.serviceNotReady }
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw Error.encoding(error)
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Error.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private struct EmptyRequest: Encodable {}
    private struct EmptyResponse: Decodable {}
}

private struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeBlock = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}
