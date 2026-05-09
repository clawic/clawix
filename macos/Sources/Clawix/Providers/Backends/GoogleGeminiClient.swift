import AIProviders
import Foundation

/// Google Generative Language API. The wire shape is roughly OpenAI-
/// compatible only on `/v1beta/openai/chat/completions`. We use the
/// native `:generateContent` endpoint which is cleaner for Gemini.
struct GoogleGeminiClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .googleGemini)?.defaultBaseURL
            ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    func testConnection() async throws {
        guard let key = credentials.apiKey, !key.isEmpty else {
            throw AIClientError.missingCredentials
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("models"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        _ = try await AIHTTP.send(req, timeoutSeconds: 10)
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        guard let key = credentials.apiKey, !key.isEmpty else {
            throw AIClientError.missingCredentials
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
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try AIHTTP.encode(GeminiGenerateBody(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: GeminiGenerationConfig(
                temperature: request.temperature,
                maxOutputTokens: request.maxTokens
            )
        ))
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
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
