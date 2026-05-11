import Foundation

/// HTTP client for the clawjs-iot daemon.
///
/// Phase 1 surface is intentionally narrow:
///   - `health()` confirms the daemon is reachable on its loopback port.
///   - `listTools()` mirrors `GET /v1/tools/list`.
///   - `invokeTool(id:arguments:)` mirrors `POST /v1/tools/:id/invoke`.
///
/// Phase 2 will add typed accessors (`listHomes`, `listThings`,
/// `getThing`, scene/automation mutators) once adapters land; for the
/// foundation pass everything flows through the tools registry.
///
/// Mirrors `DatabaseClient` enough that they can be merged into a
/// shared HTTP helper if the duplication outgrows its usefulness.
struct IoTClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "IoT service is not running."
            case .invalidURL: return "Could not build a URL for the IoT service."
            case .http(let status, let body):
                return "IoT returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode IoT response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach IoT service: \(error.localizedDescription)"
            }
        }
    }

    /// Loopback base URL `http://127.0.0.1:<iot port>`. Resolved from
    /// `ClawJSService.iot.port` so a port change in one place rewires
    /// every consumer.
    let origin: URL

    /// Bearer token for the future authenticated routes. Phase 1 always
    /// nil; populated by `IoTAdminToken.currentAdminToken()` once the
    /// daemon learns to authenticate writes.
    var bearerToken: String?

    init(origin: URL? = nil, bearerToken: String? = nil) {
        self.origin = origin ?? URL(string: "http://127.0.0.1:\(ClawJSService.iot.port)")!
        self.bearerToken = bearerToken
    }

    func health() async -> Bool {
        guard let url = URL(string: "/v1/health", relativeTo: origin) else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func listTools() async throws -> RemoteToolCatalog {
        try await getJSON(path: "/v1/tools/list", as: RemoteToolCatalog.self)
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        let body: [String: Any] = ["arguments": arguments]
        return try await postJSON(
            path: "/v1/tools/\(id)/invoke",
            body: body,
            as: RemoteToolInvocationResult.self
        )
    }

    // MARK: - HTTP helpers

    private func getJSON<T: Decodable>(path: String, as: T.Type) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return try await send(req)
    }

    private func postJSON<T: Decodable>(path: String, body: [String: Any], as: T.Type) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return try await send(req)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(status: 0, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
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
