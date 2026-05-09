import Foundation

public enum OllamaCatalog {
    public static let definition = ProviderDefinition(
        id: .ollama,
        displayName: "Ollama",
        tagline: "Local model runner. No API key needed; uses http://localhost:11434.",
        authMethods: [.none],
        defaultBaseURL: URL(string: "http://localhost:11434"),
        supportsCustomBaseURL: true,
        docsURL: URL(string: "https://ollama.com/")!,
        brand: ProviderBrand(monogram: "L", colorHex: "#000000"),
        models: [
            ModelDefinition(
                id: "llama3.2:3b",
                providerId: .ollama,
                displayName: "Llama 3.2 3B",
                capabilities: [.chat],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "llama3.1:8b",
                providerId: .ollama,
                displayName: "Llama 3.1 8B",
                capabilities: [.chat],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "qwen2.5:3b",
                providerId: .ollama,
                displayName: "Qwen 2.5 3B",
                capabilities: [.chat]
            ),
            ModelDefinition(
                id: "mistral:7b",
                providerId: .ollama,
                displayName: "Mistral 7B",
                capabilities: [.chat]
            )
        ],
        notes: "Models must be pulled locally with `ollama pull <name>` first."
    )
}
