import AIProviders
import Foundation

/// Cursor's API is OpenAI-compatible at `/v1/chat/completions` with a
/// bearer API key. Cursor users generate a key in cursor.com → Settings
/// → API; OAuth is not part of Cursor's public provider contract. This
/// client is a thin alias around the OpenAI-compatible body shape.
struct CursorClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials?

    init(account: ProviderAccount, model: ModelDefinition, credentials: AIAccountCredentials? = nil) {
        self.account = account
        self.model = model
        self.credentials = credentials
    }

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .cursor)?.defaultBaseURL
            ?? URL(string: "https://api.cursor.sh/v1")!
    }

    func testConnection() async throws {
        if let key = credentials?.apiKey, !key.isEmpty {
            var req = URLRequest(url: baseURL.appendingPathComponent("models"))
            req.httpMethod = "GET"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            _ = try await AIHTTP.send(req, timeoutSeconds: 10)
            return
        }
        _ = try await AIAccountBroker.send(
            account: account,
            method: "GET",
            url: baseURL.appendingPathComponent("models"),
            headers: ["Authorization": "Bearer {{\(AIAccountBroker.secretName(for: account)).value}}"],
            body: nil,
            agent: "clawix.ai.cursor",
            riskTier: "read",
            timeoutSeconds: 10
        )
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        let body = try AIHTTP.encode(OpenAIChatBody(
            model: model.id,
            messages: request.messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
            temperature: request.temperature,
            max_tokens: request.maxTokens
        ))
        let (data, _) = try await AIAccountBroker.send(
            account: account,
            method: "POST",
            url: baseURL.appendingPathComponent("chat/completions"),
            headers: [
                "Authorization": "Bearer {{\(AIAccountBroker.secretName(for: account)).value}}",
                "Content-Type": "application/json"
            ],
            body: String(data: body, encoding: .utf8),
            agent: "clawix.ai.cursor",
            riskTier: "write",
            timeoutSeconds: request.timeoutSeconds
        )
        let response = try AIHTTP.decode(OpenAIChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }
}
