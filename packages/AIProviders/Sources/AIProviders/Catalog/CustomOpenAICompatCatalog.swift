import Foundation

public enum CustomOpenAICompatCatalog {
    public static let definition = ProviderDefinition(
        id: .openAICompatibleCustom,
        displayName: "Custom (OpenAI-compatible)",
        tagline: "Any endpoint that implements /v1/chat/completions. Bring your own URL.",
        authMethods: [.apiKey, .none],
        defaultBaseURL: nil,
        supportsCustomBaseURL: true,
        docsURL: URL(string: "https://platform.openai.com/docs/api-reference/chat")!,
        brand: ProviderBrand(monogram: "·", colorHex: "#6B7280"),
        models: [
            ModelDefinition(
                id: "custom-chat",
                providerId: .openAICompatibleCustom,
                displayName: "Custom chat model",
                capabilities: [.chat, .toolUse],
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "custom-stt",
                providerId: .openAICompatibleCustom,
                displayName: "Custom STT model",
                capabilities: [.stt],
                isDefaultFor: [.stt]
            ),
            ModelDefinition(
                id: "custom-embeddings",
                providerId: .openAICompatibleCustom,
                displayName: "Custom embeddings model",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            )
        ],
        notes: "Set the base URL on each account (e.g. http://localhost:8080/v1)."
    )
}
