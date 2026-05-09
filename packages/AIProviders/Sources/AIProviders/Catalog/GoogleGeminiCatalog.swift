import Foundation

public enum GoogleGeminiCatalog {
    public static let definition = ProviderDefinition(
        id: .googleGemini,
        displayName: "Google Gemini",
        tagline: "Gemini 2.0 / 1.5 family via Google AI Studio.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://aistudio.google.com/app/apikey")!,
        brand: ProviderBrand(monogram: "G", colorHex: "#4285F4"),
        models: [
            ModelDefinition(
                id: "gemini-2.0-flash",
                providerId: .googleGemini,
                displayName: "Gemini 2.0 Flash",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 1_000_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "gemini-2.0-flash-thinking-exp",
                providerId: .googleGemini,
                displayName: "Gemini 2.0 Flash Thinking",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 1_000_000
            ),
            ModelDefinition(
                id: "gemini-1.5-pro",
                providerId: .googleGemini,
                displayName: "Gemini 1.5 Pro",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 2_000_000
            ),
            ModelDefinition(
                id: "gemini-1.5-flash",
                providerId: .googleGemini,
                displayName: "Gemini 1.5 Flash",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 1_000_000
            ),
            ModelDefinition(
                id: "text-embedding-004",
                providerId: .googleGemini,
                displayName: "Text Embedding 004",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            )
        ]
    )
}
