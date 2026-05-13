import Foundation

/// Minimal HTTP client for the `@clawjs/memory` service that
/// `ClawJSServiceManager` spawns on the registered memory port. Mirrors the
/// endpoints exposed in `clawjs/memory/src/server.ts`.
///
/// Memory is unauthenticated on loopback today (same as Database). The
/// `probeHealth()` call returns the canonical `/v1/health` response; the
/// rest of the surface (`/api/notes`, `/api/search`, `/api/stats`,
/// `/api/captures`, `/api/promote`, `/api/tools/status`) is reachable
/// without bearer auth from the local app.
struct ClawJSMemoryClient {

    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not build a URL for the memory service."
            case .http(let status, let body):
                return "Memory returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode memory response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach memory service: \(error.localizedDescription)"
            }
        }
    }

    /// Loopback origin. Defaults to the canonical memory port. Tests
    /// inject custom origins for ephemeral fixtures.
    let origin: URL

    init(origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.memory.port)")!) {
        self.origin = origin
    }

    // MARK: - Health

    struct HealthResponse: Decodable, Equatable {
        let ok: Bool
        let service: String
        let host: String?
        let port: Int?
    }

    func probeHealth() async throws -> HealthResponse {
        try await get("/v1/health")
    }

    // MARK: - Notes

    struct MemoryNote: Decodable, Identifiable, Equatable {
        let id: String
        let slug: String?
        let kind: String           // "entity" | "memory"
        let type: String           // semanticKind: observation, decision, preference, person, project, ...
        let title: String
        let semanticKind: String?
        let schemaVersion: Int?
        let frontmatter: [String: AnyJSON]
        let body: String

        var noteKindIsMemory: Bool { kind == "memory" }

        var tags: [String] {
            guard case .array(let values) = frontmatter["tags"] else { return [] }
            return values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }

        var scopeUser: String? { stringValue(forKey: "scopeUser") }
        var scopeAgent: String? { stringValue(forKey: "scopeAgent") }
        var scopeProject: String? { stringValue(forKey: "scopeProject") }
        var createdAt: String? { stringValue(forKey: "createdAt") }
        var updatedAt: String? { stringValue(forKey: "updatedAt") }
        var lastEditedAt: String? { stringValue(forKey: "lastEditedAt") }
        var lastEditedBy: String? { stringValue(forKey: "lastEditedBy") }
        var createdBy: String? { stringValue(forKey: "createdBy") }
        var provenance: String? { stringValue(forKey: "provenance") }
        var memoryClassRaw: String? { stringValue(forKey: "memoryClass") }
        var originalBody: String? { stringValue(forKey: "originalBody") }

        private func stringValue(forKey key: String) -> String? {
            guard case .string(let value) = frontmatter[key] else { return nil }
            return value
        }
    }

    /// `GET /api/notes`. Returns the validated set of notes; supports
    /// optional `noteKind` / `type` / `text` filters.
    func listNotes(noteKind: String? = nil, type: String? = nil, text: String? = nil) async throws -> [MemoryNote] {
        var query: [URLQueryItem] = []
        if let noteKind { query.append(.init(name: "noteKind", value: noteKind)) }
        if let type { query.append(.init(name: "type", value: type)) }
        if let text { query.append(.init(name: "text", value: text)) }
        return try await get("/api/notes", query: query)
    }

    func getNote(id: String) async throws -> MemoryNote {
        try await get("/api/notes/\(percentEscaped(id))")
    }

    struct CreateNoteInput: Encodable {
        var noteKind: String   // "memory" | "entity"
        var title: String
        var body: String
        var memoryClass: String?
        var type: String?
        var tags: [String]?
        var scopeUser: String?
        var scopeAgent: String?
        var scopeProject: String?
    }

    struct CreateNoteResponse: Decodable, Equatable {
        let saved: Bool?
        let id: String
        let title: String?
        let memoryClass: String?
        let path: String?
    }

    /// `POST /api/notes`. Creates a memory or entity note; the daemon
    /// returns the canonical id + relative path.
    func createNote(_ input: CreateNoteInput) async throws -> CreateNoteResponse {
        try await send(method: "POST", path: "/api/notes", body: input)
    }

    struct UpdateNotePatch: Encodable {
        var title: String?
        var body: String?
        var tags: [String]?
        var scopeUser: String?
        var scopeAgent: String?
        var scopeProject: String?
        var memoryClass: String?
    }

    struct UpdateNoteResponse: Decodable, Equatable {
        let updated: Bool
        let id: String
        let path: String?
        let lastEditedBy: String?
        let lastEditedAt: String?
    }

    /// `PATCH /api/notes/:id`. The optional `editor` flag becomes the
    /// `X-Memory-Editor` header so the daemon can stamp `lastEditedBy`
    /// and stash the original body.
    func updateNote(id: String, patch: UpdateNotePatch, editor: String = "user") async throws -> UpdateNoteResponse {
        try await send(
            method: "PATCH",
            path: "/api/notes/\(percentEscaped(id))",
            body: patch,
            extraHeaders: ["X-Memory-Editor": editor]
        )
    }

    struct DeleteNoteResponse: Decodable, Equatable {
        let deleted: Bool
        let id: String
        let path: String?
    }

    func deleteNote(id: String) async throws -> DeleteNoteResponse {
        try await send(method: "DELETE", path: "/api/notes/\(percentEscaped(id))", body: Optional<EmptyBody>.none)
    }

    // MARK: - Search

    struct SearchScope: Decodable, Equatable {
        let user: String?
        let agent: String?
        let project: String?
    }

    struct SearchTemporal: Decodable, Equatable {
        let validFrom: String?
        let validTo: String?
        let lastSeen: String?
    }

    struct SearchResult: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let noteKind: String
        let kind: String
        let memoryClass: String?
        let type: String
        let score: Double
        let confidence: Double?
        let trustScore: Double?
        let current: Bool?
        let temporal: SearchTemporal?
        let scope: SearchScope?
        let citation: String?
        let excerpt: String
        let provenance: String?
    }

    struct SearchResponse: Decodable, Equatable {
        let query: String
        let mode: String
        let count: Int
        let minScore: Double?
        let results: [SearchResult]
    }

    /// `GET /api/search`. Smart fallback: pass `semantic=nil` to let the
    /// daemon decide based on its own config. When the user wants to
    /// force a mode the parameter is honoured.
    func search(
        query: String,
        semantic: Bool? = nil,
        limit: Int? = nil,
        scopeUser: String? = nil,
        scopeAgent: String? = nil,
        scopeProject: String? = nil
    ) async throws -> SearchResponse {
        var items: [URLQueryItem] = [.init(name: "q", value: query)]
        if let limit { items.append(.init(name: "limit", value: String(limit))) }
        if let semantic, semantic { items.append(.init(name: "semantic", value: "true")) }
        if let scopeUser { items.append(.init(name: "scopeUser", value: scopeUser)) }
        if let scopeAgent { items.append(.init(name: "scopeAgent", value: scopeAgent)) }
        if let scopeProject { items.append(.init(name: "scopeProject", value: scopeProject)) }
        return try await get("/api/search", query: items)
    }

    // MARK: - Stats

    struct MemoryStatsResponse: Decodable, Equatable {
        let total: Int
        let entities: Int
        let memories: Int
        let valid: Bool
        let byType: [String: Int]
        let byKind: [String: Int]
        let schemaVersion: Int?
    }

    func stats() async throws -> MemoryStatsResponse {
        try await get("/api/stats")
    }

    // MARK: - Captures

    struct Capture: Decodable, Identifiable, Equatable {
        let id: String
        let capturedAt: String?
        let sessionId: String?
        let source: String?
        let user: String?
        let assistant: String?
        let scopeUser: String?
        let scopeAgent: String?
        let scopeProject: String?
        let promotedAt: String?
    }

    private struct CapturesResponse: Decodable {
        let captures: [Capture]
    }

    func listCaptures() async throws -> [Capture] {
        let response: CapturesResponse = try await get("/api/captures")
        return response.captures
    }

    struct PromoteResponse: Decodable, Equatable {
        let promoted: Bool
        let captureId: String
        let memory: CreateNoteResponse?
    }

    func promoteCapture(id: String) async throws -> PromoteResponse {
        struct PromoteBody: Encodable { let id: String }
        return try await send(method: "POST", path: "/api/promote", body: PromoteBody(id: id))
    }

    // MARK: - Doctor

    struct DoctorResponse: Decodable, Equatable {
        let enabled: Bool?
        let workspace: String?
        let notes: Int?
        let valid: Bool?
        let captures: Int?
        let warnings: [String]?
    }

    func doctor() async throws -> DoctorResponse {
        try await get("/api/tools/status")
    }

    // MARK: - Transport

    private struct EmptyBody: Encodable {}

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await perform(method: "GET", path: path, query: query, body: Optional<EmptyBody>.none, extraHeaders: [:])
    }

    private func send<B: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: B?,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        try await perform(method: method, path: path, query: [], body: body, extraHeaders: extraHeaders)
    }

    private func perform<B: Encodable, T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: B?,
        extraHeaders: [String: String]
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = origin.scheme
        components.host = origin.host
        components.port = origin.port
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw Error.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder.memoryDefault.encode(body)
            } catch {
                throw Error.decoding(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: bodyString)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private func percentEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private extension JSONEncoder {
    static let memoryDefault: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return encoder
    }()
}
