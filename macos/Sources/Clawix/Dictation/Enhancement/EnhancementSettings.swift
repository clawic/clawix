import Foundation

/// Centralized read/write of every UserDefaults key the AI enhancement
/// module owns. Kept in one struct so settings UI doesn't end up with
/// a scattered swarm of `@AppStorage` keys.
enum EnhancementSettings {

    // MARK: - Keys

    /// Master toggle. OFF by default — opting in is deliberate
    /// because Enhancement adds latency, can cost money, and changes
    /// the transcript text.
    static let enabledKey = "dictation.enhancement.enabled"
    /// Active provider raw value (`EnhancementProviderID.rawValue`).
    static let providerKey = "dictation.enhancement.provider"
    /// Per-provider model id (e.g. "gpt-4o-mini", "claude-haiku-4-5",
    /// "llama3.2:3b" for Ollama). Key is namespaced per provider so
    /// switching providers preserves the previous selection.
    static func modelKey(for provider: String) -> String {
        "dictation.enhancement.model.\(provider)"
    }
    /// Per-provider base URL (Ollama, custom). Most providers ignore
    /// this.
    static func baseURLKey(for provider: String) -> String {
        "dictation.enhancement.baseURL.\(provider)"
    }
    /// Active prompt UUID — points to either a built-in entry from
    /// `PromptLibrary` or a user-created prompt.
    static let activePromptKey = "dictation.enhancement.activePromptId"

    // MARK: Skip short transcriptions (#18)

    static let skipShortEnabledKey = "dictation.enhancement.skipShortEnabled"
    static let skipShortMinWordsKey = "dictation.enhancement.skipShortMinWords"

    // MARK: Timeout / retry policy

    static let timeoutSecondsKey = "dictation.enhancement.timeoutSeconds"
    /// On timeout: `"fail"` returns the raw transcript untouched;
    /// `"retry"` retries up to 3 times with exponential backoff.
    static let timeoutPolicyKey = "dictation.enhancement.timeoutPolicy"

    // MARK: Context awareness

    static let clipboardContextKey = "dictation.enhancement.clipboardContext"

    // MARK: Defaults

    static func bootstrapIfNeeded(_ defaults: UserDefaults = .standard) {
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(false, forKey: enabledKey)
        }
        if defaults.object(forKey: providerKey) == nil {
            defaults.set(EnhancementProviderID.openai.rawValue, forKey: providerKey)
        }
        if defaults.object(forKey: skipShortEnabledKey) == nil {
            defaults.set(true, forKey: skipShortEnabledKey)
        }
        if defaults.object(forKey: skipShortMinWordsKey) == nil {
            defaults.set(3, forKey: skipShortMinWordsKey)
        }
        if defaults.object(forKey: timeoutSecondsKey) == nil {
            defaults.set(7, forKey: timeoutSecondsKey)
        }
        if defaults.object(forKey: timeoutPolicyKey) == nil {
            defaults.set("retry", forKey: timeoutPolicyKey)
        }
        if defaults.object(forKey: clipboardContextKey) == nil {
            defaults.set(false, forKey: clipboardContextKey)
        }
        // Defaults for built-in models per provider, to give first-run
        // users a sensible value to point at.
        if defaults.object(forKey: modelKey(for: EnhancementProviderID.openai.rawValue)) == nil {
            defaults.set("gpt-4o-mini", forKey: modelKey(for: EnhancementProviderID.openai.rawValue))
        }
        if defaults.object(forKey: modelKey(for: EnhancementProviderID.anthropic.rawValue)) == nil {
            defaults.set("claude-haiku-4-5", forKey: modelKey(for: EnhancementProviderID.anthropic.rawValue))
        }
        if defaults.object(forKey: modelKey(for: EnhancementProviderID.ollama.rawValue)) == nil {
            defaults.set("llama3.2:3b", forKey: modelKey(for: EnhancementProviderID.ollama.rawValue))
        }
        if defaults.object(forKey: baseURLKey(for: EnhancementProviderID.ollama.rawValue)) == nil {
            defaults.set("http://localhost:11434", forKey: baseURLKey(for: EnhancementProviderID.ollama.rawValue))
        }
        // Sensible defaults for the new providers' first-pick model.
        for id in [EnhancementProviderID.groq, .mistral, .xai, .openrouter] {
            if defaults.object(forKey: modelKey(for: id.rawValue)) == nil,
               let firstModel = id.defaultModels.first {
                defaults.set(firstModel, forKey: modelKey(for: id.rawValue))
            }
        }
    }
}

/// IDs for every supported provider. Adding more (Groq, Mistral, etc.)
/// is intentionally a small change: extend the enum, register the
/// provider in `EnhancementService.providers`, and the UI picker
/// updates automatically.
enum EnhancementProviderID: String, CaseIterable, Codable {
    case openai
    case anthropic
    case ollama
    case groq
    case mistral
    case xai
    case openrouter
    case custom

    var displayName: String {
        switch self {
        case .openai:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .ollama:     return "Ollama (local)"
        case .groq:       return "Groq"
        case .mistral:    return "Mistral"
        case .xai:        return "xAI"
        case .openrouter: return "OpenRouter"
        case .custom:     return "Custom (OpenAI-compatible)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .custom:
            return false // Custom may require one — checked at call time.
        case .openai, .anthropic, .groq, .mistral, .xai, .openrouter:
            return true
        }
    }

    /// Catalog of "well-known" model IDs the user can pick without
    /// hitting the provider's models endpoint. The catalog isn't
    /// exhaustive — the model picker also accepts free-form input.
    var defaultModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"]
        case .anthropic:
            return [
                "claude-haiku-4-5",
                "claude-sonnet-4-6",
                "claude-opus-4-7"
            ]
        case .ollama:
            return ["llama3.2:3b", "llama3.1:8b", "qwen2.5:3b", "mistral:7b"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        case .mistral:
            return ["mistral-small-latest", "mistral-large-latest", "open-mistral-7b"]
        case .xai:
            return ["grok-4.3-latest", "grok-4.20-reasoning-latest", "grok-4.20-non-reasoning-latest"]
        case .openrouter:
            return [
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-haiku",
                "meta-llama/llama-3.3-70b-instruct",
                "google/gemini-2.0-flash-001"
            ]
        case .custom:
            return []
        }
    }
}
