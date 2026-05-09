import Foundation

public enum OpenAICatalog {
    public static let definition = ProviderDefinition(
        id: .openai,
        displayName: "OpenAI",
        tagline: "GPT family, Whisper, embeddings, image generation.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://api.openai.com/v1"),
        supportsCustomBaseURL: true,
        docsURL: URL(string: "https://platform.openai.com/api-keys")!,
        brand: ProviderBrand(monogram: "O", colorHex: "#10A37F"),
        models: [
            ModelDefinition(
                id: "gpt-4o",
                providerId: .openai,
                displayName: "GPT-4o",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "gpt-4o-mini",
                providerId: .openai,
                displayName: "GPT-4o mini",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "gpt-4-turbo",
                providerId: .openai,
                displayName: "GPT-4 Turbo",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "whisper-1",
                providerId: .openai,
                displayName: "Whisper v1",
                capabilities: [.stt],
                isDefaultFor: [.stt]
            ),
            ModelDefinition(
                id: "tts-1",
                providerId: .openai,
                displayName: "TTS v1",
                capabilities: [.tts],
                isDefaultFor: [.tts]
            ),
            ModelDefinition(
                id: "tts-1-hd",
                providerId: .openai,
                displayName: "TTS v1 HD",
                capabilities: [.tts]
            ),
            ModelDefinition(
                id: "text-embedding-3-large",
                providerId: .openai,
                displayName: "Embedding 3 large",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            ),
            ModelDefinition(
                id: "text-embedding-3-small",
                providerId: .openai,
                displayName: "Embedding 3 small",
                capabilities: [.embeddings]
            ),
            ModelDefinition(
                id: "dall-e-3",
                providerId: .openai,
                displayName: "DALL-E 3",
                capabilities: [.imageGen],
                isDefaultFor: [.imageGen]
            )
        ]
    )
}
