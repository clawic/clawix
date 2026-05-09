import Foundation

public enum GitHubCopilotCatalog {
    public static let definition = ProviderDefinition(
        id: .githubCopilot,
        displayName: "GitHub Copilot",
        tagline: "Sign in with GitHub to use Copilot models. Subscription required.",
        authMethods: [.deviceCode(.githubCopilot)],
        defaultBaseURL: URL(string: "https://api.githubcopilot.com"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://github.com/features/copilot")!,
        brand: ProviderBrand(monogram: "G", colorHex: "#181717"),
        models: [
            ModelDefinition(
                id: "gpt-4o",
                providerId: .githubCopilot,
                displayName: "GPT-4o (Copilot)",
                capabilities: [.chat, .vision, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "gpt-4o-mini",
                providerId: .githubCopilot,
                displayName: "GPT-4o mini (Copilot)",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "claude-3.5-sonnet",
                providerId: .githubCopilot,
                displayName: "Claude 3.5 Sonnet (Copilot)",
                capabilities: [.chat, .toolUse],
                contextWindow: 200_000
            ),
            ModelDefinition(
                id: "o1",
                providerId: .githubCopilot,
                displayName: "o1 (Copilot)",
                capabilities: [.chat],
                contextWindow: 200_000
            )
        ]
    )
}
