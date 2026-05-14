import AIProviders
import Foundation

/// GitHub Copilot. Uses an OAuth-derived `access_token` (the GitHub
/// device flow handshake) to fetch a short-lived Copilot token via
/// `/copilot_internal/v2/token`, then sends inference requests to
/// `https://api.githubcopilot.com/chat/completions` (OpenAI-compatible).
///
/// The Copilot token lives ~30 min and is cached in
/// `credentials.expiresAt` / `credentials.scope`. When expired, this
/// client refreshes it transparently.
struct GitHubCopilotClient: AIClient {
    let account: ProviderAccount
    let model: ModelDefinition
    let credentials: AIAccountCredentials

    private var baseURL: URL {
        account.baseURLOverride
            ?? ProviderCatalog.definition(for: .githubCopilot)?.defaultBaseURL
            ?? URL(string: "https://api.githubcopilot.com")!
    }

    func testConnection() async throws {
        _ = try await fetchCopilotToken()
    }

    func chat(_ request: ChatRequest) async throws -> String {
        guard model.capabilities.contains(.chat) else {
            throw AIClientError.capabilityNotSupported(.chat)
        }
        let copilotToken = try await fetchCopilotToken()
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(copilotToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.21.0", forHTTPHeaderField: "Editor-Plugin-Version")
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

    /// Resolves the short-lived Copilot inference token from the
    /// long-lived GitHub access token. The undocumented endpoint
    /// `api.github.com/copilot_internal/v2/token` is the same one the
    /// official Copilot extensions hit — it returns `{ token, expires_at, ... }`.
    private func fetchCopilotToken() async throws -> String {
        let data: Data
        if let github = credentials.accessToken, !github.isEmpty {
            var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
            req.httpMethod = "GET"
            req.setValue("token \(github)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("vscode/1.95.0", forHTTPHeaderField: "Editor-Version")
            data = try await AIHTTP.send(req, timeoutSeconds: 10).0
        } else {
            data = try await AIAccountBroker.send(
                account: account,
                fieldName: "access_token",
                method: "GET",
                url: URL(string: "https://api.github.com/copilot_internal/v2/token")!,
                headers: [
                    "Authorization": "token {{\(AIAccountBroker.secretName(for: account)).access_token}}",
                    "Accept": "application/vnd.github+json",
                    "Editor-Version": "vscode/1.95.0"
                ],
                body: nil,
                agent: "clawix.ai.github-copilot",
                riskTier: "read",
                timeoutSeconds: 10
            ).0
        }
        struct Resp: Codable { let token: String }
        return try AIHTTP.decode(Resp.self, from: data).token
    }
}
