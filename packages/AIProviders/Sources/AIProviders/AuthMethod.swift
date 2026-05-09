import Foundation

/// How a provider account authenticates with the upstream API.
public enum AuthMethod: Codable, Sendable, Hashable {
    /// Plain API key sent as bearer or `x-api-key` header. Most providers.
    case apiKey
    /// PKCE OAuth flow that yields an access_token + refresh_token.
    case oauth(OAuthFlavor)
    /// Device-code flow (terminal/CLI style). GitHub Copilot uses this.
    case deviceCode(DeviceCodeFlavor)
    /// No credentials needed (Ollama on localhost).
    case none
}

public enum OAuthFlavor: String, Codable, Sendable, Hashable {
    case anthropicClaudeAi = "anthropic_claude_ai"
}

public enum DeviceCodeFlavor: String, Codable, Sendable, Hashable {
    case githubCopilot = "github_copilot"
}

extension AuthMethod {
    /// Stable string used inside the vault `authMethod` field. Encoders
    /// round-trip via this so the vault row is self-describing.
    public var storageTag: String {
        switch self {
        case .apiKey: return "api_key"
        case .oauth(let flavor): return "oauth_\(flavor.rawValue)"
        case .deviceCode(let flavor): return "device_code_\(flavor.rawValue)"
        case .none: return "none"
        }
    }

    public init?(storageTag: String) {
        switch storageTag {
        case "api_key": self = .apiKey
        case "none": self = .none
        default:
            if let suffix = storageTag.dropPrefixIfPresent("oauth_"),
               let flavor = OAuthFlavor(rawValue: suffix) {
                self = .oauth(flavor)
                return
            }
            if let suffix = storageTag.dropPrefixIfPresent("device_code_"),
               let flavor = DeviceCodeFlavor(rawValue: suffix) {
                self = .deviceCode(flavor)
                return
            }
            return nil
        }
    }
}

private extension String {
    func dropPrefixIfPresent(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
