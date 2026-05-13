import Foundation

/// Minimal HTTP client for the `@clawjs/database` service that Phase 2's
/// supervisor will spawn on the registered database port once `ClawJSServiceManager`
/// gets a non-nil `commandLine(for:)`. The endpoint paths and request
/// shapes mirror what `@clawjs/database@\(ClawJSRuntime.expectedVersion)`
/// exposes in `packages/clawjs-database/src/app.ts`.
///
/// Phase 4 keeps this client deliberately small: only the surface a
/// thin-slice consumer actually needs (health probe, list namespaces,
/// list collection records). Auth, mutation, files, tokens, and the
/// `/v1/realtime` WebSocket subscription stay out until a real consumer
/// drives the requirement, so we don't ship dead code that diverges
/// from the upstream contract before anyone exercises it.
struct ClawJSDatabaseClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady:
                return "ClawJS database service is not running."
            case .invalidURL:
                return "Could not build a URL for the database service."
            case .http(let status, let body):
                return "Database returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode database response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach database service: \(error.localizedDescription)"
            }
        }
    }

    /// Bearer token issued by `/v1/auth/admin/login` or by a scoped
    /// namespace token. `nil` while we have not authenticated yet; the
    /// health probe is the only call that does not require auth.
    var bearerToken: String?

    /// Loopback origin. Defaults to the canonical port the supervisor
    /// uses (`ClawJSService.database.port`). Tests inject a custom
    /// origin when running against an ephemeral fixture.
    let origin: URL

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.database.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Health

    struct HealthResponse: Decodable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    /// `GET /v1/health`. Unauthenticated. Returns the service's reported
    /// host/port so we can confirm we're hitting the right process.
    func probeHealth() async throws -> HealthResponse {
        try await get("/v1/health", authenticated: false)
    }

    // MARK: - Namespaces

    struct Namespace: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let createdAt: String?
    }

    private struct NamespacesResponse: Decodable {
        let namespaces: [Namespace]
    }

    /// `GET /v1/namespaces`. Requires bearer auth.
    func listNamespaces() async throws -> [Namespace] {
        let response: NamespacesResponse = try await get("/v1/namespaces")
        return response.namespaces
    }

    // MARK: - Records

    struct Record: Decodable, Identifiable, Equatable {
        let id: String
        let createdAt: String?
        let updatedAt: String?
        /// Free-form payload. Each predefined collection (tasks, people,
        /// events, notes) ships its own schema in ClawJS core; consumers
        /// decode into a strongly-typed shape after this stage.
        let data: [String: AnyJSON]
    }

    private struct RecordsResponse: Decodable {
        let records: [Record]
    }

    /// `GET /v1/namespaces/:namespaceId/collections/:collectionName/records`.
    /// Requires bearer auth. Page parameters land here when a consumer
    /// needs them; for the thin slice the default page is enough.
    func listRecords(
        namespaceId: String,
        collection: String
    ) async throws -> [Record] {
        let path = "/v1/namespaces/\(namespaceId)/collections/\(collection)/records"
        let response: RecordsResponse = try await get(path)
        return response.records
    }

    // MARK: - Transport

    private func get<T: Decodable>(
        _ path: String,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let bearerToken else { throw Error.serviceNotReady }
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }
}

/// Minimal type-erased JSON value. Lives here (rather than in a shared
/// utilities module) because Phase 4 is the only consumer today and we
/// can promote it later if another caller needs the same shape.
indirect enum AnyJSON: Codable, Hashable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let entries): try container.encode(entries)
        case .object(let entries): try container.encode(entries)
        }
    }
}
