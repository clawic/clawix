import Foundation

public enum TogetherAICatalog {
    public static let definition = ProviderDefinition(
        id: .togetherAI,
        displayName: "Together AI",
        tagline: "Open-source model hosting (Llama, Qwen, Mixtral, FLUX).",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.together.xyz/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://api.together.ai/settings/api-keys")!,
        brand: ProviderBrand(monogram: "T", colorHex: "#0F6FFF"),
        models: [
            ModelDefinition(
                id: "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo",
                providerId: .togetherAI,
                displayName: "Llama 3.1 70B Instruct Turbo",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
                providerId: .togetherAI,
                displayName: "Llama 3.1 405B Instruct Turbo",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "Qwen/Qwen2.5-72B-Instruct-Turbo",
                providerId: .togetherAI,
                displayName: "Qwen 2.5 72B Instruct Turbo",
                capabilities: [.chat, .toolUse],
                contextWindow: 32_000
            ),
            ModelDefinition(
                id: "mistralai/Mixtral-8x22B-Instruct-v0.1",
                providerId: .togetherAI,
                displayName: "Mixtral 8x22B",
                capabilities: [.chat],
                contextWindow: 65_000
            ),
            ModelDefinition(
                id: "BAAI/bge-large-en-v1.5",
                providerId: .togetherAI,
                displayName: "BGE Large EN",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            ),
            ModelDefinition(
                id: "black-forest-labs/FLUX.1-schnell",
                providerId: .togetherAI,
                displayName: "FLUX.1 Schnell",
                capabilities: [.imageGen],
                isDefaultFor: [.imageGen]
            )
        ]
    )
}
