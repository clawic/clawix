import AIProviders
import Foundation

/// OpenAI's official endpoints for chat, transcription, and embeddings.
/// Also the structural template that `OpenAICompatibleClient` mirrors —
/// any provider that ships a `/v1/chat/completions`-shaped API can
/// reuse the request bodies built here.
struct OpenAIClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: account.providerId)?.defaultBaseURL
            ?? URL(string: "https://api.openai.com/v1")!
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
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.decoding("no choices in response")
        }
        return content
    }

    func transcribe(_ request: TranscribeRequest) async throws -> String {
        guard model.capabilities.contains(.stt) else {
            throw AIClientError.capabilityNotSupported(.stt)
        }
        guard let key = credentials.apiKey, !key.isEmpty else {
            throw AIClientError.missingCredentials
        }
        let boundary = "Boundary-" + UUID().uuidString
        var parts: [AIHTTP.Multipart] = [
            .text(name: "model", value: model.id),
            .file(name: "file", filename: "audio." + audioExtension(for: request.mimeType),
                  mime: request.mimeType, data: request.audio)
        ]
        if let language = request.language {
            parts.append(.text(name: "language", value: language))
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = AIHTTP.multipart(boundary: boundary, parts: parts)
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(OpenAITranscribeResponse.self, from: data)
        return response.text
    }

    private func audioExtension(for mime: String) -> String {
        switch mime {
        case "audio/wav": return "wav"
        case "audio/m4a", "audio/mp4": return "m4a"
        case "audio/mpeg": return "mp3"
        case "audio/webm": return "webm"
        case "audio/ogg": return "ogg"
        default: return "bin"
        }
    }
}

// MARK: - Wire types

struct OpenAIMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OpenAIChatBody: Codable, Sendable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double?
    let max_tokens: Int?
}

struct OpenAIChatResponse: Codable, Sendable {
    struct Choice: Codable, Sendable { let message: OpenAIMessage }
    let choices: [Choice]
}

struct OpenAITranscribeResponse: Codable, Sendable {
    let text: String
}
