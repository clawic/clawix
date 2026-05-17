import Foundation

public enum XAICatalog {
    public static let definition = ProviderDefinition(
        id: .xai,
        displayName: "xAI",
        tagline: "Grok family. OpenAI-compatible.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.x.ai/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://console.x.ai/")!,
        brand: ProviderBrand(monogram: "X", colorHex: "#000000"),
        models: [
            ModelDefinition(
                id: "grok-4.3-latest",
                providerId: .xai,
                displayName: "Grok 4.3",
                capabilities: [.chat, .toolUse],
                contextWindow: 1_000_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "grok-4.20-reasoning-latest",
                providerId: .xai,
                displayName: "Grok 4.20 Reasoning",
                capabilities: [.chat, .toolUse],
                contextWindow: 2_000_000
            ),
            ModelDefinition(
                id: "grok-4.20-non-reasoning-latest",
                providerId: .xai,
                displayName: "Grok 4.20 Non-Reasoning",
                capabilities: [.chat, .toolUse],
                contextWindow: 2_000_000
            )
        ]
    )
}
