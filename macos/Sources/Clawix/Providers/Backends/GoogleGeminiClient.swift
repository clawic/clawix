import AIProviders
import Foundation

/// Google Generative Language API. The wire shape is roughly OpenAI-
/// compatible only on `/v1beta/openai/chat/completions`. We use the
/// native `:generateContent` endpoint which is cleaner for Gemini.
struct GoogleGeminiClient: AIClient {
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
            ?? ProviderCatalog.definition(for: .googleGemini)?.defaultBaseURL
            ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    func testConnection() async throws {
        if let key = credentials?.apiKey, !key.isEmpty {
            var req = URLRequest(url: baseURL.appendingPathComponent("models"))
            req.httpMethod = "GET"
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            _ = try await AIHTTP.send(req, timeoutSeconds: 10)
            return
        }
        _ = try await AIAccountBroker.send(
            account: account,
            method: "GET",
            url: baseURL.appendingPathComponent("models"),
            headers: ["x-goog-api-key": "{{\(AIAccountBroker.secretName(for: account)).value}}"],
            body: nil,
            agent: "clawix.ai.gemini",
            riskTier: "read",
            timeoutSeconds: 10
        )
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        var systemInstruction: GeminiContent?
        var contents: [GeminiContent] = []
        for message in request.messages {
            switch message.role {
            case .system:
                let combined = (systemInstruction?.parts.first?.text ?? "") + (systemInstruction == nil ? "" : "\n\n") + message.content
                systemInstruction = GeminiContent(role: nil, parts: [GeminiPart(text: combined)])
            case .user:
                contents.append(GeminiContent(role: "user", parts: [GeminiPart(text: message.content)]))
            case .assistant:
                contents.append(GeminiContent(role: "model", parts: [GeminiPart(text: message.content)]))
            }
        }
        let path = "models/\(model.id):generateContent"
        let body = try AIHTTP.encode(GeminiGenerateBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: GeminiGenerationConfig(
                temperature: request.temperature,
                maxOutputTokens: request.maxTokens
            )
        ))
        let (data, _) = try await AIAccountBroker.send(
            account: account,
            method: "POST",
            url: baseURL.appendingPathComponent(path),
            headers: [
                "x-goog-api-key": "{{\(AIAccountBroker.secretName(for: account)).value}}",
                "Content-Type": "application/json"
            ],
            body: String(data: body, encoding: .utf8),
            agent: "clawix.ai.gemini",
            riskTier: "write",
            timeoutSeconds: request.timeoutSeconds
        )
        let response = try AIHTTP.decode(GeminiGenerateResponse.self, from: data)
        guard let text = response.candidates.first?.content.parts.first?.text else {
            throw AIClientError.decoding("no candidates in response")
        }
        return text
    }
}

// MARK: - Wire types

struct GeminiPart: Codable, Sendable { let text: String }
struct GeminiContent: Codable, Sendable {
    let role: String?
    let parts: [GeminiPart]
}
struct GeminiGenerationConfig: Codable, Sendable {
    let temperature: Double?
    let maxOutputTokens: Int?
}
struct GeminiGenerateBody: Codable, Sendable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GeminiGenerationConfig
}
struct GeminiGenerateResponse: Codable, Sendable {
    struct Candidate: Codable, Sendable { let content: GeminiContent }
    let candidates: [Candidate]
}
