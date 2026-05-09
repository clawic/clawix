import Foundation

/// Stable identifiers for the 16 providers shipped in v1. Adding a new
/// provider means: extend this enum, add its catalog file, append to
/// `ProviderCatalog.all`, optionally add an OAuth strategy in the macOS
/// target. Removing one is more disruptive: existing accounts keyed
/// by the removed id become orphaned and need a manual purge.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Hashable {
    case openai
    case anthropic
    case googleGemini = "google_gemini"
    case groq
    case deepseek
    case togetherAI = "together_ai"
    case glmZhipu = "glm_zhipu"
    case xai
    case mistral
    case openrouter
    case cursor
    case githubCopilot = "github_copilot"
    case cerebras
    case fireworks
    case ollama
    case openAICompatibleCustom = "openai_compatible_custom"
}
