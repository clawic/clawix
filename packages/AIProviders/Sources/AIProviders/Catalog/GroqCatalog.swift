import Foundation

public enum GroqCatalog {
    public static let definition = ProviderDefinition(
        id: .groq,
        displayName: "Groq",
        tagline: "Fast inference for Llama and Whisper. OpenAI-compatible.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.groq.com/openai/v1"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://console.groq.com/keys")!,
        brand: ProviderBrand(monogram: "Q", colorHex: "#F55036"),
        models: [
            ModelDefinition(
                id: "llama-3.3-70b-versatile",
                providerId: .groq,
                displayName: "Llama 3.3 70B Versatile",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "llama-3.1-8b-instant",
                providerId: .groq,
                displayName: "Llama 3.1 8B Instant",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "mixtral-8x7b-32768",
                providerId: .groq,
                displayName: "Mixtral 8x7B",
                capabilities: [.chat],
                contextWindow: 32_768
            ),
            ModelDefinition(
                id: "whisper-large-v3",
                providerId: .groq,
                displayName: "Whisper Large v3",
                capabilities: [.stt],
                isDefaultFor: [.stt]
            ),
            ModelDefinition(
                id: "whisper-large-v3-turbo",
                providerId: .groq,
                displayName: "Whisper Large v3 Turbo",
                capabilities: [.stt]
            )
        ]
    )
}
