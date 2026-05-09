import Foundation

public enum AnthropicCatalog {
    public static let definition = ProviderDefinition(
        id: .anthropic,
        displayName: "Anthropic",
        tagline: "Claude family. API key from Console, or sign in with Claude.ai.",
        authMethods: [.apiKey, .oauth(.anthropicClaudeAi)],
        defaultBaseURL: URL(string: "https://api.anthropic.com/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://console.anthropic.com/settings/keys")!,
        brand: ProviderBrand(monogram: "A", colorHex: "#D97706"),
        models: [
            ModelDefinition(
                id: "claude-opus-4-7",
                providerId: .anthropic,
                displayName: "Claude Opus 4.7",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 200_000
            ),
            ModelDefinition(
                id: "claude-sonnet-4-6",
                providerId: .anthropic,
                displayName: "Claude Sonnet 4.6",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 200_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "claude-haiku-4-5",
                providerId: .anthropic,
                displayName: "Claude Haiku 4.5",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 200_000
            )
        ]
    )
}
