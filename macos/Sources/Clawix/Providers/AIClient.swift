import AIProviders
import Foundation

/// Errors returned by every `AIClient` impl. Surfaced verbatim in the
/// "Test connection" button and in feature failure banners.
enum AIClientError: Error, LocalizedError, Equatable {
    case capabilityNotSupported(Capability)
    case missingCredentials
    case missingBaseURL
    case http(Int, String)
    case timedOut
    case decoding(String)
    case provider(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .capabilityNotSupported(let cap): return "This model does not support \(cap.rawValue)."
        case .missingCredentials: return "No credentials configured for this account."
        case .missingBaseURL: return "Base URL is required."
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(160))"
        case .timedOut: return "The request timed out."
        case .decoding(let detail): return "Couldn't parse the response: \(detail)"
        case .provider(let detail): return detail
        case .cancelled: return "Request cancelled."
        }
    }
}

struct AIChatMessage: Sendable, Hashable {
    enum Role: String, Sendable, Codable { case system, user, assistant }
    let role: Role
    let content: String
    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

struct ChatRequest: Sendable {
    var messages: [AIChatMessage]
    var temperature: Double?
    var maxTokens: Int?
    var timeoutSeconds: Int = 30
}

struct TranscribeRequest: Sendable {
    var audio: Data
    var mimeType: String
    var language: String?
    var timeoutSeconds: Int = 60
}

/// One provider account + model resolved into a callable client. Each
/// concrete `*Client.swift` knows its own provider's HTTP shape; the
/// factory in `AIClientFactory` chooses which to instantiate based on
/// `account.providerId`.
protocol AIClient: Sendable {
    var account: ProviderAccount { get }
    var model: ModelDefinition { get }

    /// Lightweight ping that authenticates without consuming inference
    /// quota. Used by the Add Account sheet's "Test connection" button.
    /// Implementations typically GET `/v1/models` or HEAD a cheap path.
    func testConnection() async throws

    func chat(_ request: ChatRequest) async throws -> String

    func transcribe(_ request: TranscribeRequest) async throws -> String
}

extension AIClient {
    func chat(_ request: ChatRequest) async throws -> String {
        throw AIClientError.capabilityNotSupported(.chat)
    }

    func transcribe(_ request: TranscribeRequest) async throws -> String {
        throw AIClientError.capabilityNotSupported(.stt)
    }
}

/// Builds the right `AIClient` impl for a given account + model.
@MainActor
enum AIClientFactory {
    static func client(
        for account: ProviderAccount,
        model: ModelDefinition,
        accountStore: AIAccountStore = AIAccountVaultStore.shared
    ) async throws -> any AIClient {
        let credentials = try accountStore.revealCredentials(accountId: account.id)
        switch account.providerId {
        case .openai:
            return OpenAIClient(account: account, model: model, credentials: credentials)
        case .anthropic:
            return AnthropicClient(account: account, model: model, credentials: credentials)
        case .googleGemini:
            return GoogleGeminiClient(account: account, model: model, credentials: credentials)
        case .ollama:
            return OllamaClient(account: account, model: model, credentials: credentials)
        case .githubCopilot:
            return GitHubCopilotClient(account: account, model: model, credentials: credentials)
        case .cursor:
            return CursorClient(account: account, model: model, credentials: credentials)
        case .groq, .deepseek, .togetherAI, .glmZhipu, .xai, .mistral,
             .openrouter, .cerebras, .fireworks, .openAICompatibleCustom:
            return OpenAICompatibleClient(account: account, model: model, credentials: credentials)
        }
    }

    /// Convenience: load default selection for a feature and build the
    /// client. Throws if no provider is configured for that capability.
    static func client(
        forFeature feature: FeatureRouting.FeatureID,
        capability: Capability,
        accountStore: AIAccountStore = AIAccountVaultStore.shared
    ) async throws -> any AIClient {
        guard let resolved = FeatureRouting.resolve(
            feature: feature,
            capability: capability,
            store: accountStore
        ) else {
            throw AIClientError.missingCredentials
        }
        return try await client(for: resolved.account, model: resolved.model, accountStore: accountStore)
    }
}
