import Foundation

public enum FireworksCatalog {
    public static let definition = ProviderDefinition(
        id: .fireworks,
        displayName: "Fireworks",
        tagline: "Open-source model hosting (Llama, Qwen, FLUX).",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.fireworks.ai/inference/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://fireworks.ai/api-keys")!,
        brand: ProviderBrand(monogram: "F", colorHex: "#FF6E1F"),
        models: [
            ModelDefinition(
                id: "accounts/fireworks/models/llama-v3p3-70b-instruct",
                providerId: .fireworks,
                displayName: "Llama 3.3 70B Instruct",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "accounts/fireworks/models/llama-v3p1-405b-instruct",
                providerId: .fireworks,
                displayName: "Llama 3.1 405B Instruct",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "accounts/fireworks/models/qwen2p5-72b-instruct",
                providerId: .fireworks,
                displayName: "Qwen 2.5 72B Instruct",
                capabilities: [.chat, .toolUse],
                contextWindow: 32_000
            ),
            ModelDefinition(
                id: "accounts/fireworks/models/deepseek-v3",
                providerId: .fireworks,
                displayName: "DeepSeek V3",
                capabilities: [.chat, .toolUse],
                contextWindow: 64_000
            ),
            ModelDefinition(
                id: "accounts/fireworks/models/flux-1-schnell-fp8",
                providerId: .fireworks,
                displayName: "FLUX.1 Schnell",
                capabilities: [.imageGen],
                isDefaultFor: [.imageGen]
            )
        ]
    )
}
