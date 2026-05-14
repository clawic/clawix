import AIProviders
import Foundation

/// OpenAI's official endpoints for chat, transcription, and embeddings.
/// Also the structural template that `OpenAICompatibleClient` mirrors —
/// any provider that ships a `/v1/chat/completions`-shaped API can
/// reuse the request bodies built here.
struct OpenAIClient: AIClient {
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
            ?? ProviderCatalog.definition(for: account.providerId)?.defaultBaseURL
            ?? URL(string: "https://api.openai.com/v1")!
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
            agent: "clawix.ai.openai",
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
            agent: "clawix.ai.openai",
            riskTier: "write",
            timeoutSeconds: request.timeoutSeconds
        )
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
            .file(name: "file", filename: "audio." + audioExtension(for: request.mimeType),
                  mime: request.mimeType, data: request.audio)
        ]
        if let language = request.language {
            parts.append(.text(name: "language", value: language))
        }
        let dataBody = AIHTTP.multipart(boundary: boundary, parts: parts)
        let (data, _) = try await AIAccountBroker.send(
            account: account,
            method: "POST",
            url: baseURL.appendingPathComponent("audio/transcriptions"),
            headers: [
                "Authorization": "Bearer {{\(AIAccountBroker.secretName(for: account)).value}}",
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ],
            body: nil,
            bodyData: dataBody,
            agent: "clawix.ai.openai",
            riskTier: "write",
            timeoutSeconds: request.timeoutSeconds
        )
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
