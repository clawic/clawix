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
                id: "grok-2-latest",
                providerId: .xai,
                displayName: "Grok 2",
                capabilities: [.chat, .toolUse],
                contextWindow: 131_072,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "grok-2-vision-latest",
                providerId: .xai,
                displayName: "Grok 2 Vision",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 32_768
            ),
            ModelDefinition(
                id: "grok-beta",
                providerId: .xai,
                displayName: "Grok Beta",
                capabilities: [.chat],
                contextWindow: 131_072
            )
        ]
    )
}
