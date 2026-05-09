import Foundation

public enum OpenRouterCatalog {
    public static let definition = ProviderDefinition(
        id: .openrouter,
        displayName: "OpenRouter",
        tagline: "Aggregator gateway across many providers under one key.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://openrouter.ai/api/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://openrouter.ai/keys")!,
        brand: ProviderBrand(monogram: "R", colorHex: "#6366F1"),
        models: [
            ModelDefinition(
                id: "anthropic/claude-3.5-sonnet",
                providerId: .openrouter,
                displayName: "Claude 3.5 Sonnet (via OpenRouter)",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 200_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "openai/gpt-4o",
                providerId: .openrouter,
                displayName: "GPT-4o (via OpenRouter)",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "openai/gpt-4o-mini",
                providerId: .openrouter,
                displayName: "GPT-4o mini (via OpenRouter)",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "meta-llama/llama-3.3-70b-instruct",
                providerId: .openrouter,
                displayName: "Llama 3.3 70B Instruct",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "google/gemini-2.0-flash-001",
                providerId: .openrouter,
                displayName: "Gemini 2.0 Flash",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 1_000_000
            ),
            ModelDefinition(
                id: "deepseek/deepseek-chat",
                providerId: .openrouter,
                displayName: "DeepSeek Chat",
                capabilities: [.chat, .toolUse],
                contextWindow: 64_000
            )
        ]
    )
}
