import Foundation

/// Default loopback port the `@clawjs/audio` service listens on. Kept
/// here (rather than referenced from `ClawJSService.audio`) because the
/// client lives in `ClawixEngine` and the macOS-only supervisor enum is
/// not reachable from the daemon helper that also consumes this client.
public let clawJSAudioDefaultPort: UInt16 = 7794

/// Loopback HTTP client for the `@clawjs/audio` service that the ClawJS
/// supervisor spawns on `127.0.0.1:7794`. Endpoint paths mirror what
/// `@clawjs/audio` exposes in `packages/clawjs-audio/src/app.ts`.
///
/// All endpoints require a bearer token: the shared secret either the
/// GUI generated through its session admin-token slot, or the daemon
/// read from `<data-dir>/.admin-token` (the supervisor writes it there
/// on first spawn).
public struct ClawJSAudioClient: Sendable {

    public enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case notFound

        public var errorDescription: String? {
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

    public let bearerToken: String
    public let origin: URL

    public init(
        bearerToken: String,
        origin: URL = URL(string: "http://127.0.0.1:\(clawJSAudioDefaultPort)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Wire shapes

    /// Mirrors `WireAudioAsset` in the ClawJS audio package. Encoded with
    /// camelCase keys matching the framework's TS types.
    public struct Asset: Codable, Equatable, Sendable {
        public let id: String
        public let kind: String
        public let appId: String
        public let originActor: String
        public let mimeType: String
        public let bytesRelPath: String
        public let durationMs: Int
        public let createdAt: Int64
        public let deviceId: String?
        public let sessionId: String?
        public let threadId: String?
        public let linkedMessageId: String?
        public let metadataJson: String?
    }

    public struct Transcript: Codable, Equatable, Sendable {
        public let id: String
        public let audioId: String
        public let role: String
        public let text: String
        public let provider: String?
        public let language: String?
        public let createdAt: Int64
        public let isPrimary: Bool
    }

    public struct AssetWithTranscripts: Codable, Equatable, Sendable {
        public let asset: Asset
        public let transcripts: [Transcript]
    }

    public struct ListResult: Codable, Equatable, Sendable {
        public let items: [AssetWithTranscripts]
        public let total: Int
    }

    public struct BytesResponse: Codable, Equatable, Sendable {
        public let base64: String
        public let mimeType: String
        public let durationMs: Int
    }

    public struct DeleteResponse: Codable, Equatable, Sendable {
        public let deleted: Bool
    }

    public struct RegisterTranscriptInput: Codable, Equatable, Sendable {
        public let text: String
        public let role: String?
        public let provider: String?
        public let language: String?

        public init(text: String, role: String? = nil, provider: String? = nil, language: String? = nil) {
            self.text = text
            self.role = role
            self.provider = provider
            self.language = language
        }
    }

    public struct RegisterInput: Codable, Equatable, Sendable {
        public let id: String?
        public let kind: String
        public let appId: String
        public let originActor: String
        public let mimeType: String
        public let bytesBase64: String
        public let durationMs: Int
        public let deviceId: String?
        public let sessionId: String?
        public let threadId: String?
        public let linkedMessageId: String?
        public let metadataJson: String?
        public let transcript: RegisterTranscriptInput?

        public init(
            id: String? = nil,
            kind: String,
            appId: String,
            originActor: String,
            mimeType: String,
            bytesBase64: String,
            durationMs: Int,
            deviceId: String? = nil,
            sessionId: String? = nil,
            threadId: String? = nil,
            linkedMessageId: String? = nil,
            metadataJson: String? = nil,
            transcript: RegisterTranscriptInput? = nil
        ) {
            self.id = id
            self.kind = kind
            self.appId = appId
            self.originActor = originActor
            self.mimeType = mimeType
            self.bytesBase64 = bytesBase64
            self.durationMs = durationMs
            self.deviceId = deviceId
            self.sessionId = sessionId
            self.threadId = threadId
            self.linkedMessageId = linkedMessageId
            self.metadataJson = metadataJson
            self.transcript = transcript
        }
    }

    public struct AttachTranscriptInput: Codable, Equatable, Sendable {
        public let text: String
        public let role: String
        public let provider: String?
        public let language: String?
        public let markAsPrimary: Bool?

        public init(text: String, role: String, provider: String? = nil, language: String? = nil, markAsPrimary: Bool? = nil) {
            self.text = text
            self.role = role
            self.provider = provider
            self.language = language
            self.markAsPrimary = markAsPrimary
        }
    }

    public struct ListFilter: Sendable {
        public let appId: String
        public var kind: String? = nil
        public var originActor: String? = nil
        public var deviceId: String? = nil
        public var sessionId: String? = nil
        public var threadId: String? = nil
        public var linkedMessageId: String? = nil
        public var limit: Int? = nil
        public var offset: Int? = nil

        public init(
            appId: String,
            kind: String? = nil,
            originActor: String? = nil,
            deviceId: String? = nil,
            sessionId: String? = nil,
            threadId: String? = nil,
            linkedMessageId: String? = nil,
            limit: Int? = nil,
            offset: Int? = nil
        ) {
            self.appId = appId
            self.kind = kind
            self.originActor = originActor
            self.deviceId = deviceId
            self.sessionId = sessionId
            self.threadId = threadId
            self.linkedMessageId = linkedMessageId
            self.limit = limit
            self.offset = offset
        }
    }

    // MARK: - Endpoints

    public func register(_ input: RegisterInput) async throws -> AssetWithTranscripts {
        try await post(ClawixPersistentSurfaceAPI.path("/audio"), body: input)
    }

    public func attachTranscript(audioId: String, input: AttachTranscriptInput) async throws -> Transcript {
        try await post(ClawixPersistentSurfaceAPI.path("/audio/\(audioId)/transcripts"), body: input)
    }

    public func get(audioId: String, appId: String) async throws -> AssetWithTranscripts {
        try await get(ClawixPersistentSurfaceAPI.path("/audio/\(audioId)?appId=\(urlEncode(appId))"))
    }

    public func getBytes(audioId: String, appId: String) async throws -> BytesResponse {
        try await get(ClawixPersistentSurfaceAPI.path("/audio/\(audioId)/bytes?appId=\(urlEncode(appId))"))
    }

    public func list(filter: ListFilter) async throws -> ListResult {
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
        components.path = ClawixPersistentSurfaceAPI.path("/audio")
        components.queryItems = items
        return try await get(components.url(relativeTo: origin)!.absoluteString.replacingOccurrences(of: origin.absoluteString, with: ""))
    }

    @discardableResult
    public func delete(audioId: String, appId: String) async throws -> Bool {
        let response: DeleteResponse = try await deleteRequest(ClawixPersistentSurfaceAPI.path("/audio/\(audioId)?appId=\(urlEncode(appId))"))
        return response.deleted
    }

    /// Reads the per-session bearer token the supervisor wrote to disk
    /// when it spawned the audio service. Returns nil when the file is
    /// missing or empty (e.g. service has never run on this machine).
    public static func tokenFromAdminTokenFile(_ url: URL) -> String? {
        let tokenURL = url.appendingPathComponent(".admin-token", isDirectory: false)
        guard let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
