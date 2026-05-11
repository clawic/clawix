import Foundation

/// Loopback HTTP client for the `@clawjs/audio` service that the ClawJS
/// supervisor spawns on `127.0.0.1:7794`. The endpoint paths mirror what
/// `@clawjs/audio` exposes in `packages/clawjs-audio/src/app.ts`.
///
/// All endpoints require a bearer token: the shared secret the GUI
/// generated via `adminTokenIfSpawned(for: .audio)`. Without it every
/// request returns 401.
struct ClawJSAudioClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case notFound

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "ClawJS audio service is not running."
            case .invalidURL:      return "Could not build a URL for the audio service."
            case .http(let status, let body):
                return "Audio service returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode audio response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach audio service: \(error.localizedDescription)"
            case .notFound:        return "Audio asset not found."
            }
        }
    }

    let bearerToken: String
    let origin: URL

    init(
        bearerToken: String,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.audio.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Wire shapes

    /// Mirrors `WireAudioAsset` in the ClawJS audio package. Encoded with
    /// camelCase keys matching the framework's TS types.
    struct Asset: Codable, Equatable {
        let id: String
        let kind: String
        let appId: String
        let originActor: String
        let mimeType: String
        let bytesRelPath: String
        let durationMs: Int
        let createdAt: Int64
        let deviceId: String?
        let sessionId: String?
        let threadId: String?
        let linkedMessageId: String?
        let metadataJson: String?
    }

    struct Transcript: Codable, Equatable {
        let id: String
        let audioId: String
        let role: String
        let text: String
        let provider: String?
        let language: String?
        let createdAt: Int64
        let isPrimary: Bool
    }

    struct AssetWithTranscripts: Codable, Equatable {
        let asset: Asset
        let transcripts: [Transcript]
    }

    struct ListResult: Codable, Equatable {
        let items: [AssetWithTranscripts]
        let total: Int
    }

    struct BytesResponse: Codable, Equatable {
        let base64: String
        let mimeType: String
        let durationMs: Int
    }

    struct DeleteResponse: Codable, Equatable {
        let deleted: Bool
    }

    struct RegisterTranscriptInput: Codable, Equatable {
        let text: String
        let role: String?
        let provider: String?
        let language: String?
    }

    struct RegisterInput: Codable, Equatable {
        let id: String?
        let kind: String
        let appId: String
        let originActor: String
        let mimeType: String
        let bytesBase64: String
        let durationMs: Int
        let deviceId: String?
        let sessionId: String?
        let threadId: String?
        let linkedMessageId: String?
        let metadataJson: String?
        let transcript: RegisterTranscriptInput?
    }

    struct AttachTranscriptInput: Codable, Equatable {
        let text: String
        let role: String
        let provider: String?
        let language: String?
        let markAsPrimary: Bool?
    }

    struct ListFilter {
        let appId: String
        var kind: String? = nil
        var originActor: String? = nil
        var deviceId: String? = nil
        var sessionId: String? = nil
        var threadId: String? = nil
        var linkedMessageId: String? = nil
        var limit: Int? = nil
        var offset: Int? = nil
    }

    // MARK: - Endpoints

    func register(_ input: RegisterInput) async throws -> AssetWithTranscripts {
        try await post("/v1/audio", body: input)
    }

    func attachTranscript(audioId: String, input: AttachTranscriptInput) async throws -> Transcript {
        try await post("/v1/audio/\(audioId)/transcripts", body: input)
    }

    func get(audioId: String, appId: String) async throws -> AssetWithTranscripts {
        try await get("/v1/audio/\(audioId)?appId=\(urlEncode(appId))")
    }

    func getBytes(audioId: String, appId: String) async throws -> BytesResponse {
        try await get("/v1/audio/\(audioId)/bytes?appId=\(urlEncode(appId))")
    }

    func list(filter: ListFilter) async throws -> ListResult {
        var items: [URLQueryItem] = [.init(name: "appId", value: filter.appId)]
        if let v = filter.kind { items.append(.init(name: "kind", value: v)) }
        if let v = filter.originActor { items.append(.init(name: "originActor", value: v)) }
        if let v = filter.deviceId { items.append(.init(name: "deviceId", value: v)) }
        if let v = filter.sessionId { items.append(.init(name: "sessionId", value: v)) }
        if let v = filter.threadId { items.append(.init(name: "threadId", value: v)) }
        if let v = filter.linkedMessageId { items.append(.init(name: "linkedMessageId", value: v)) }
        if let v = filter.limit { items.append(.init(name: "limit", value: String(v))) }
        if let v = filter.offset { items.append(.init(name: "offset", value: String(v))) }
        var components = URLComponents()
        components.path = "/v1/audio"
        components.queryItems = items
        return try await get(components.url(relativeTo: origin)!.absoluteString.replacingOccurrences(of: origin.absoluteString, with: ""))
    }

    @discardableResult
    func delete(audioId: String, appId: String) async throws -> Bool {
        let response: DeleteResponse = try await deleteRequest("/v1/audio/\(audioId)?appId=\(urlEncode(appId))")
        return response.deleted
    }

    // MARK: - Transport

    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: Optional<Empty>.none)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    private func deleteRequest<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "DELETE", body: Optional<Empty>.none)
    }

    private func request<B: Encodable, T: Decodable>(path: String, method: String, body: B?) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw Error.decoding(error)
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw Error.notFound }
            if !(200..<300).contains(http.statusCode) {
                throw Error.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
            }
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private struct Empty: Encodable {}
}
