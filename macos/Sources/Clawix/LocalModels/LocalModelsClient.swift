import Foundation
import ClawixCore

/// Thin async wrapper over the daemon's REST API. Talks only to the
/// loopback port owned by `LocalModelsDaemon`; nothing here is
/// configurable so we can never accidentally point at a daemon we don't
/// own.
///
/// All endpoints are documented at https://github.com/ollama/ollama/blob/main/docs/api.md.
/// We map only the subset Settings needs (list / show / delete / pull
/// streaming / ps / version / unload).
struct LocalModelsClient {

    static let shared = LocalModelsClient()

    private var baseURL: URL {
        URL(string: "http://\(LocalModelsDaemon.host):\(LocalModelsDaemon.port)")!
    }

    // MARK: - Wire types

    struct VersionResponse: Decodable {
        let version: String
    }

    struct ModelTag: Decodable, Identifiable {
        let name: String
        let digest: String
        let size: Int64
        let modifiedAt: String?

        var id: String { digest }

        enum CodingKeys: String, CodingKey {
            case name, digest, size
            case modifiedAt = "modified_at"
        }
    }

    struct RunningModel: Decodable, Identifiable {
        let name: String
        let digest: String
        let sizeVRAM: Int64

        var id: String { digest }

        enum CodingKeys: String, CodingKey {
            case name, digest
            case sizeVRAM = "size_vram"
        }
    }

    struct ShowResponse: Decodable {
        let modelfile: String?
        let parameters: String?
        let template: String?
        let license: String?
    }

    struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    /// One streamed chunk from `/api/chat`. The daemon emits one JSON
    /// object per line with the assistant's incremental token in
    /// `message.content` until `done == true`.
    struct ChatStreamEvent: Decodable {
        struct InnerMessage: Decodable {
            let role: String?
            let content: String?
        }
        let message: InnerMessage?
        let done: Bool?
        let error: String?
    }

    /// One streamed chunk from `/api/pull`. Status is the human-readable
    /// stage ("pulling manifest", "downloading sha256:…", "success");
    /// when downloading a layer, `total` and `completed` track bytes for
    /// the current blob (the response can re-use the same digest as it
    /// streams updates, so the caller should always take the latest).
    struct PullEvent: Decodable {
        let status: String?
        let digest: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    // MARK: - Endpoints

    func version() async throws -> String {
        try await getJSON(OllamaAPIRoute.version, as: VersionResponse.self).version
    }

    func tags() async throws -> [ModelTag] {
        struct Response: Decodable { let models: [ModelTag] }
        return try await getJSON(OllamaAPIRoute.tags, as: Response.self).models
    }

    func ps() async throws -> [RunningModel] {
        struct Response: Decodable { let models: [RunningModel] }
        return try await getJSON(OllamaAPIRoute.ps, as: Response.self).models
    }

    func show(model: String) async throws -> ShowResponse {
        struct Body: Encodable { let model: String }
        return try await postJSON(OllamaAPIRoute.show, body: Body(model: model), as: ShowResponse.self)
    }

    func delete(model: String) async throws {
        struct Body: Encodable { let model: String }
        var req = makeRequest(path: OllamaAPIRoute.delete, method: "DELETE")
        req.httpBody = try JSONEncoder().encode(Body(model: model))
        let (_, response) = try await URLSession.shared.data(for: req)
        try Self.assertOK(response, path: OllamaAPIRoute.delete)
    }

    /// Hits `/api/generate` with `keep_alive: 0` to force the daemon to
    /// evict the model from VRAM immediately. The daemon documents this
    /// as the supported way to unload (there is no dedicated endpoint).
    func unload(model: String) async throws {
        struct Body: Encodable {
            let model: String
            let prompt: String
            let keep_alive: Int
        }
        var req = makeRequest(path: OllamaAPIRoute.generate, method: "POST")
        req.httpBody = try JSONEncoder().encode(
            Body(model: model, prompt: "", keep_alive: 0)
        )
        let (_, response) = try await URLSession.shared.data(for: req)
        try Self.assertOK(response, path: OllamaAPIRoute.generate)
    }

    /// Streaming chat. Yields the assistant's text content as it
    /// arrives from `/api/chat`. Cancellation aborts the underlying
    /// URLSession task.
    func chat(
        model: String,
        messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        struct Body: Encodable {
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = makeRequest(path: OllamaAPIRoute.chat, method: "POST")
                    req.httpBody = try JSONEncoder().encode(
                        Body(model: model, messages: messages, stream: true)
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    try Self.assertOK(response, path: OllamaAPIRoute.chat)

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let event = try? decoder.decode(ChatStreamEvent.self, from: data)
                        else { continue }
                        if let error = event.error, !error.isEmpty {
                            continuation.finish(throwing: ClientError.daemonError(error))
                            return
                        }
                        if let content = event.message?.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                        if event.done == true {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streaming pull. Yields one `PullEvent` per JSON line on the wire
    /// until the daemon emits `status == "success"` or the stream ends.
    /// Cancellation is honored — stopping the iteration aborts the
    /// underlying URLSession task.
    func pull(model: String) -> AsyncThrowingStream<PullEvent, Error> {
        struct Body: Encodable {
            let model: String
            let stream: Bool
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = makeRequest(path: OllamaAPIRoute.pull, method: "POST")
                    req.httpBody = try JSONEncoder().encode(Body(model: model, stream: true))
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    try Self.assertOK(response, path: OllamaAPIRoute.pull)

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let event = try? decoder.decode(PullEvent.self, from: data)
                        else { continue }
                        continuation.yield(event)
                        if let error = event.error, !error.isEmpty {
                            continuation.finish(throwing: ClientError.daemonError(error))
                            return
                        }
                        if event.status == "success" {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func getJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let req = makeRequest(path: path, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.assertOK(response, path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        as type: Response.Type
    ) async throws -> Response {
        var req = makeRequest(path: path, method: "POST")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.assertOK(response, path: path)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func assertOK(_ response: URLResponse, path: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpError(status: http.statusCode, path: path)
        }
    }

    enum ClientError: LocalizedError {
        case httpError(status: Int, path: String)
        case daemonError(String)

        var errorDescription: String? {
            switch self {
            case .httpError(let status, let path):
                return "Local runtime returned HTTP \(status) for \(path)."
            case .daemonError(let message):
                return "Local runtime error: \(message)"
            }
        }
    }
}
