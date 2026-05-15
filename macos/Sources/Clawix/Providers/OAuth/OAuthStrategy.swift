import AIProviders
import Foundation

/// Provider-specific OAuth knobs. Each `OAuthFlavor` ships a strategy
/// that knows its authorize URL, token endpoint, scopes, and how to
/// parse the token response.
struct OAuthAuthorization: Sendable {
    let url: URL
    let state: String
    let codeVerifier: String
    /// Scheme + host the strategy expects in the callback (`clawix://auth/callback/<provider>`).
    let callbackHost: String
}

struct OAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scope: String?
    let accountEmail: String?
}

protocol OAuthStrategy: Sendable {
    var flavor: OAuthFlavor { get }
    var providerId: ProviderID { get }

    func startAuthorization() -> OAuthAuthorization
    func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokens
    func refresh(refreshToken: String) async throws -> OAuthTokens
}

enum OAuthRegistry {
    static func strategy(for flavor: OAuthFlavor) -> any OAuthStrategy {
        switch flavor {
        case .anthropicClaudeAi:
            return AnthropicOAuthStrategy()
        }
    }
}
