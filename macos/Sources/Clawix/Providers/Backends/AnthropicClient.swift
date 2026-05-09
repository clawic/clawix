import AIProviders
import Foundation

/// Anthropic Messages API. Same client handles API key and OAuth
/// accounts: the auth header switches between `x-api-key` and
/// `Authorization: Bearer <access_token>` based on `account.authMethod`.
struct AnthropicClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .anthropic)?.defaultBaseURL
            ?? URL(string: "https://api.anthropic.com/v1")!
    }

    func testConnection() async throws {
        // Anthropic doesn't ship a public auth-only endpoint; the
        // cheapest validation is a GET /v1/models. Returns 401 for a
        // bad key, which AIHTTP surfaces as `.http(401, ...)`.
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.httpMethod = "GET"
        applyAuth(to: &req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        _ = try await AIHTTP.send(req, timeoutSeconds: 10)
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        var systemPrompt: String? = nil
        var userAssistant: [AnthropicMessage] = []
        for message in request.messages {
            switch message.role {
            case .system:
                systemPrompt = (systemPrompt.map { $0 + "\n\n" } ?? "") + message.content
            case .user, .assistant:
                userAssistant.append(AnthropicMessage(role: message.role.rawValue, content: message.content))
            }
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "POST"
        applyAuth(to: &req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try AIHTTP.encode(AnthropicMessagesBody(
            model: model.id,
            max_tokens: request.maxTokens ?? 4096,
            system: systemPrompt,
            messages: userAssistant,
            temperature: request.temperature
        ))
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: request.timeoutSeconds)
        let response = try AIHTTP.decode(AnthropicMessagesResponse.self, from: data)
        guard let block = response.content.first(where: { $0.type == "text" }) else {
            throw AIClientError.decoding("no text block in response")
        }
        return block.text ?? ""
    }

    private func applyAuth(to req: inout URLRequest) {
        switch account.authMethod {
        case .oauth:
            if let token = credentials.accessToken, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        default:
            if let key = credentials.apiKey, !key.isEmpty {
                req.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        }
    }
}

// MARK: - Wire types

struct AnthropicMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct AnthropicMessagesBody: Codable, Sendable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let temperature: Double?
}

struct AnthropicMessagesResponse: Codable, Sendable {
    struct Block: Codable, Sendable {
        let type: String
        let text: String?
    }
    let content: [Block]
}
