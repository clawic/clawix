import AIProviders
import Foundation

/// Anthropic Claude.ai OAuth (PKCE). Endpoints and client_id are
/// public but not officially documented — the same values OpenCode and
/// other community wrappers use. Treat as best-effort: if Anthropic
/// revokes the client_id, the AIClient falls back to API key auth.
struct AnthropicOAuthStrategy: OAuthStrategy {
    let flavor: OAuthFlavor = .anthropicClaudeAi
    let providerId: ProviderID = .anthropic

    /// Anthropic's published OAuth client id for first-party apps.
    /// Public — visible in browser network logs of any sign-in.
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let scopes = "org:create_api_key user:profile user:inference"
    private static let redirectURI = "clawix://oauth-callback/anthropic"

    func startAuthorization() -> OAuthAuthorization {
        let verifier = PKCE.makeCodeVerifier()
        let state = PKCE.makeState()
        let challenge = PKCE.challenge(forVerifier: verifier)
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state)
        ]
        return OAuthAuthorization(
            url: components.url!,
            state: state,
            codeVerifier: verifier,
            callbackHost: "oauth-callback"
        )
    }

    func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokens {
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = encodeForm([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientId
        ])
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: 30)
        return try parseTokens(data)
    }

    func refresh(refreshToken: String) async throws -> OAuthTokens {
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = encodeForm([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientId
        ])
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await AIHTTP.send(req, timeoutSeconds: 30)
        return try parseTokens(data)
    }

    @MainActor
    func refresh(account: ProviderAccount) async throws -> OAuthTokens {
        let secretName = AIAccountBroker.secretName(for: account)
        let body = encodeForm([
            "grant_type": "refresh_token",
            "refresh_token": "{{\(secretName).refresh_token}}",
            "client_id": Self.clientId
        ])
        let response = try await AIAccountBroker.send(
            account: account,
            fieldName: "refresh_token",
            placement: "body",
            method: "POST",
            url: Self.tokenURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body,
            agent: "clawix.ai.anthropic.oauth-refresh",
            riskTier: "write",
            timeoutSeconds: 30
        )
        return try parseTokens(response.0)
    }

    private func parseTokens(_ data: Data) throws -> OAuthTokens {
        struct Response: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let scope: String?
            let account: Account?
            struct Account: Codable {
                let email: String?
            }
        }
        let response = try AIHTTP.decode(Response.self, from: data)
        let expiresAt = response.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        return OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: expiresAt,
            scope: response.scope,
            accountEmail: response.account?.email
        )
    }

    private func encodeForm(_ fields: [String: String]) -> String {
        fields
            .map { (k, v) in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)" }
            .joined(separator: "&")
    }
}
