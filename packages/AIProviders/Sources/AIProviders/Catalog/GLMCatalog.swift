import Foundation

public enum GLMCatalog {
    public static let definition = ProviderDefinition(
        id: .glmZhipu,
        displayName: "GLM (Zhipu)",
        tagline: "GLM family from Zhipu AI. OpenAI-compatible.",
        authMethods: [.apiKey],
        defaultBaseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4"),
        supportsCustomBaseURL: false,
        docsURL: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")!,
        brand: ProviderBrand(monogram: "Z", colorHex: "#1E63FF"),
        models: [
            ModelDefinition(
                id: "glm-4-plus",
                providerId: .glmZhipu,
                displayName: "GLM-4 Plus",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000,
                isDefaultFor: [.chat]
            ),
            ModelDefinition(
                id: "glm-4-air",
                providerId: .glmZhipu,
                displayName: "GLM-4 Air",
                capabilities: [.chat, .toolUse],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "glm-4-flash",
                providerId: .glmZhipu,
                displayName: "GLM-4 Flash",
                capabilities: [.chat],
                contextWindow: 128_000
            ),
            ModelDefinition(
                id: "glm-4v-plus",
                providerId: .glmZhipu,
                displayName: "GLM-4V Plus",
                capabilities: [.chat, .vision],
                contextWindow: 8_000
            ),
            ModelDefinition(
                id: "embedding-3",
                providerId: .glmZhipu,
                displayName: "Embedding-3",
                capabilities: [.embeddings],
                isDefaultFor: [.embeddings]
            )
        ]
    )
}
