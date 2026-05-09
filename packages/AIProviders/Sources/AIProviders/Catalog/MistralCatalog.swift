import Foundation

public enum MistralCatalog {
    public static let definition = ProviderDefinition(
        id: .mistral,
        displayName: "Mistral",
        tagline: "Mistral Large / Small / Codestral and embeddings.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.mistral.ai/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://console.mistral.ai/api-keys/")!,
        brand: ProviderBrand(monogram: "M", colorHex: "#FA520F"),
        models: [
            ModelDefinition(
                id: "mistral-large-latest",
                providerId: .mistral,
                displayName: "Mistral Large",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "mistral-small-latest",
                providerId: .mistral,
                displayName: "Mistral Small",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "codestral-latest",
                providerId: .mistral,
                displayName: "Codestral",
                capabilities: [.chat, .toolUse],
                contextWindow: 32_000
            ),
            ModelDefinition(
                id: "open-mistral-7b",
                providerId: .mistral,
                displayName: "Open Mistral 7B",
                capabilities: [.chat],
                contextWindow: 32_000
            ),
            ModelDefinition(
                id: "mistral-embed",
                providerId: .mistral,
                displayName: "Mistral Embed",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            )
        ]
    )
}
