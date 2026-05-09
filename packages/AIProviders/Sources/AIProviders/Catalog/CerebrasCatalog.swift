import Foundation

public enum CerebrasCatalog {
    public static let definition = ProviderDefinition(
        id: .cerebras,
        displayName: "Cerebras",
        tagline: "High-throughput Llama inference. OpenAI-compatible.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.cerebras.ai/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://cloud.cerebras.ai/")!,
        brand: ProviderBrand(monogram: "C", colorHex: "#FF6B35"),
        models: [
            ModelDefinition(
                id: "llama3.3-70b",
                providerId: .cerebras,
                displayName: "Llama 3.3 70B",
                capabilities: [.chat, .toolUse],
                contextWindow: 8_192,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "llama3.1-8b",
                providerId: .cerebras,
                displayName: "Llama 3.1 8B",
                capabilities: [.chat, .toolUse],
                contextWindow: 8_192
            )
        ]
    )
}
