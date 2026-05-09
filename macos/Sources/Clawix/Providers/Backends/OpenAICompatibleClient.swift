import AIProviders
import Foundation

/// A single client class that handles every provider whose HTTP shape
/// is "OpenAI's `/v1/chat/completions` with a different base URL":
/// Groq, DeepSeek, Together AI, GLM/Zhipu, xAI, Mistral, OpenRouter,
/// Cerebras, Fireworks, and the user-supplied Custom provider.
///
/// Groq additionally ships a Whisper-compatible STT endpoint at
/// `/audio/transcriptions`, so this client also implements `transcribe`
/// and the feature filtering by `capability == .stt` decides who gets
/// to call it.
struct OpenAICompatibleClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        if let override = account.baseURLOverride {
            return override
        }
        if let provider = ProviderCatalog.definition(for: account.providerId),
           let url = provider.defaultBaseURL {
            return url
        }
        return URL(string: "https://api.openai.com/v1")!
    }

    func testConnection() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.httpMethod = "GET"
        if let key = credentials.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        _ = try await AIHTTP.send(req, timeoutSeconds: 10)
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        if let key = credentials.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if account.providerId != .openAICompatibleCustom && account.providerId != .ollama {
            throw AIClientError.missingCredentials
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try AIHTTP.encode(OpenAIChatBody(
            model: model.id,
            messages: request.messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
            temperature: request.temperature,
            max_tokens: request.maxTokens
        ))
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(OpenAIChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.decoding("no choices in response")
        }
        return content
    }

    func transcribe(_ request: TranscribeRequest) async throws -> String {
        guard model.capabilities.contains(.stt) else {
            throw AIClientError.capabilityNotSupported(.stt)
        }
        let boundary = "Boundary-" + UUID().uuidString
        var parts: [AIHTTP.Multipart] = [
            .text(name: "model", value: model.id),
            .file(name: "file", filename: "audio.bin", mime: request.mimeType, data: request.audio)
        ]
        if let language = request.language {
            parts.append(.text(name: "language", value: language))
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        if let key = credentials.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = AIHTTP.multipart(boundary: boundary, parts: parts)
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(OpenAITranscribeResponse.self, from: data)
        return response.text
    }
}
