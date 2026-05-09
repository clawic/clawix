import AIProviders
import Foundation

/// Cursor's API is OpenAI-compatible at `/v1/chat/completions` with a
/// bearer API key. OAuth flow is not yet public; users generate a key
/// in cursor.com → Settings → API. This client is a thin alias around
/// the OpenAI-compatible body shape.
struct CursorClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .cursor)?.defaultBaseURL
            ?? URL(string: "https://api.cursor.sh/v1")!
    }

    func testConnection() async throws {
        guard let key = credentials.apiKey, !key.isEmpty else {
            throw AIClientError.missingCredentials
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        _ = try await AIHTTP.send(req, timeoutSeconds: 10)
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        guard let key = credentials.apiKey, !key.isEmpty else {
            throw AIClientError.missingCredentials
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try AIHTTP.encode(OpenAIChatBody(
            model: model.id,
            messages: request.messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
            temperature: request.temperature,
            max_tokens: request.maxTokens
        ))
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(OpenAIChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}
