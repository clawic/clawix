import Foundation

public enum DeepSeekCatalog {
    public static let definition = ProviderDefinition(
        id: .deepseek,
        displayName: "DeepSeek",
        tagline: "DeepSeek V3, Coder, Reasoner. OpenAI-compatible.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.deepseek.com/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://platform.deepseek.com/api_keys")!,
        brand: ProviderBrand(monogram: "D", colorHex: "#4D6BFE"),
        models: [
            ModelDefinition(
                id: "deepseek-chat",
                providerId: .deepseek,
                displayName: "DeepSeek Chat (V3)",
                capabilities: [.chat, .toolUse],
                contextWindow: 64_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "deepseek-reasoner",
                providerId: .deepseek,
                displayName: "DeepSeek Reasoner (R1)",
                capabilities: [.chat],
                contextWindow: 64_000
            ),
            ModelDefinition(
                id: "deepseek-coder",
                providerId: .deepseek,
                displayName: "DeepSeek Coder",
                capabilities: [.chat, .toolUse],
                contextWindow: 64_000
            )
        ]
    )
}
