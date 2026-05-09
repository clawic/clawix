import AIProviders
import Foundation

/// Ollama runs locally; the API is unauthenticated by default. Falls
/// back to OpenAI-compatible if the user runs Ollama with the
/// `OLLAMA_API_KEY` env variable set.
struct OllamaClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .ollama)?.defaultBaseURL
            ?? URL(string: "http://localhost:11434")!
    }

    func testConnection() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.httpMethod = "GET"
        _ = try await AIHTTP.send(req, timeoutSeconds: 5)
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try AIHTTP.encode(OllamaChatBody(
            model: model.id,
            messages: request.messages.map { OllamaMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            options: OllamaOptions(temperature: request.temperature)
        ))
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(OllamaChatResponse.self, from: data)
        return response.message.content
    }
}

struct OllamaMessage: Codable, Sendable {
    let role: String
    let content: String
}
struct OllamaOptions: Codable, Sendable {
    let temperature: Double?
}
struct OllamaChatBody: Codable, Sendable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions
}
struct OllamaChatResponse: Codable, Sendable {
    let message: OllamaMessage
}
