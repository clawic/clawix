import Foundation

/// The static list of every provider this build supports. Adding a
/// new provider: create `Catalog/<Name>Catalog.swift`, add its case
/// to `ProviderID`, and append the definition here.
public enum ProviderCatalog {

    public static let all: [ProviderDefinition] = [
        OpenAICatalog.definition,
        AnthropicCatalog.definition,
        GoogleGeminiCatalog.definition,
        GroqCatalog.definition,
        DeepSeekCatalog.definition,
        TogetherAICatalog.definition,
        GLMCatalog.definition,
        XAICatalog.definition,
        MistralCatalog.definition,
        OpenRouterCatalog.definition,
        CursorCatalog.definition,
        GitHubCopilotCatalog.definition,
        CerebrasCatalog.definition,
        FireworksCatalog.definition,
        OllamaCatalog.definition,
        CustomOpenAICompatCatalog.definition
    ]

    public static func definition(for id: ProviderID) -> ProviderDefinition? {
        all.first { $0.id == id }
    }

    public static func model(providerId: ProviderID, modelId: String) -> ModelDefinition? {
        definition(for: providerId)?.models.first { $0.id == modelId }
    }

    /// Models across every provider that can perform `capability`.
    public static func models(for capability: Capability) -> [ModelDefinition] {
        all.flatMap { $0.models }.filter { $0.capabilities.contains(capability) }
    }

    /// First model of a provider that advertises `capability`. Falls
    /// back to any model that lists the capability if none is marked
    /// as default. Used by `FeatureProviderPicker` for fresh selections.
    public static func defaultModel(for capability: Capability, in providerId: ProviderID) -> ModelDefinition? {
        guard let definition = definition(for: providerId) else { return nil }
        if let primary = definition.models.first(where: { $0.isDefaultFor.contains(capability) }) {
            return primary
        }
        return definition.models.first { $0.capabilities.contains(capability) }
    }
}
