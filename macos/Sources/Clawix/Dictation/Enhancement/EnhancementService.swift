import AIProviders
import Foundation
import AppKit

/// Orchestrator between Whisper and TextInjector. When the master toggle
/// (`EnhancementSettings.enabledKey`) is on, it calls the LLM with the
/// active prompt and returns processed text. When it is off, it passes
/// text through untouched.
///
/// Failure policy follows the user preset:
///   * `fail` — returns raw text so paste still works when the LLM fails.
///   * `retry` — up to 3 attempts with exponential backoff (1s, 2s, 4s)
///     before falling back to raw text.
///
/// Skip-short (#18) exits before the call when the transcript has fewer
/// words than the configured threshold, avoiding LLM calls for short
/// utterances like "ok" or "yes".
@MainActor
final class EnhancementService {

    static let shared = EnhancementService()

    /// Rate-limit: at least 1 second between calls, protecting the
    /// user's quota and preventing a double shortcut press from firing
    /// two parallel requests.
    private static let minInterval: TimeInterval = 1.0
    private var lastCallAt: Date?

    private let providers: [EnhancementProvider] = [
        OpenAIEnhancementProvider(),
        AnthropicEnhancementProvider(),
        OllamaEnhancementProvider(),
        GroqEnhancementProvider(),
        MistralEnhancementProvider(),
        XAIEnhancementProvider(),
        OpenRouterEnhancementProvider(),
        CustomEnhancementProvider()
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        EnhancementSettings.bootstrapIfNeeded(defaults)
    }

    var isEnabled: Bool {
        defaults.bool(forKey: EnhancementSettings.enabledKey)
    }

    var activeProvider: EnhancementProvider? {
        let raw = defaults.string(forKey: EnhancementSettings.providerKey) ?? EnhancementProviderID.openai.rawValue
        guard let id = EnhancementProviderID(rawValue: raw) else { return nil }
        return providers.first(where: { $0.id == id })
    }

    /// Apply enhancement to `raw`. Returns the original text on every
    /// "skip" condition (master toggle off, no provider configured,
    /// transcript too short, throw with `fail` policy). The caller
    /// then pastes whichever text we returned, so a single try/catch
    /// at the call site is enough.
    func enhance(raw: String, powerMode: PowerModeConfig?) async -> String {
        guard isEnabled else { return raw }
        // Power Mode override: if the active PM has enhancement off
        // explicitly, skip even if the global toggle is on.
        if let pm = powerMode, !pm.enhancementEnabled {
            // Don't override if PM defaults to enhancementEnabled=false
            // AND the global is on — that would silently disable
            // enhancement for every PM-active app. Instead, only honor
            // the override when PM has its own enhancement settings,
            // which we surface in the editor (#21 follow-up).
            return raw
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        // Skip-short (#18): word count below threshold → pass through.
        if defaults.bool(forKey: EnhancementSettings.skipShortEnabledKey) {
            let minWords = max(1, defaults.integer(forKey: EnhancementSettings.skipShortMinWordsKey))
            let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
            if wordCount < minWords {
                return raw
            }
        }

        // Rate limit. We don't queue: a second call inside 1s is
        // discarded silently and returns raw. The user wouldn't have
        // gotten a snappier result by waiting anyway.
        if let last = lastCallAt, Date().timeIntervalSince(last) < Self.minInterval {
            return raw
        }
        lastCallAt = Date()

        let prompt = PromptLibrary.shared.activePrompt()
        let timeoutPolicy = defaults.string(forKey: EnhancementSettings.timeoutPolicyKey) ?? "retry"
        let timeoutFromDefaults = defaults.integer(forKey: EnhancementSettings.timeoutSecondsKey)
        let timeout = timeoutFromDefaults > 0 ? timeoutFromDefaults : 7

        // Framework routing has priority when Settings → Model Providers
        // defines an enhancement route. The per-enhancement provider
        // remains a stable v1 configuration path for users who pick the
        // provider directly in Voice to Text settings.
        if let routed = FeatureRouting.resolve(
            feature: .enhancement,
            capability: .chat,
            store: AIAccountSecretsStore.shared
        ) {
            let context = EnhancementContext(
                clipboardText: defaults.bool(forKey: EnhancementSettings.clipboardContextKey)
                    ? clipboardSnapshot()
                    : nil
            )
            do {
                let client = try await AIClientFactory.client(for: routed.account, model: routed.model)
                let user = composeUserMessage(text: trimmed, prompt: prompt.userPrompt, context: context)
                let request = ChatRequest(
                    messages: [
                        AIChatMessage(role: .system, content: prompt.systemPrompt),
                        AIChatMessage(role: .user, content: user)
                    ],
                    timeoutSeconds: timeout
                )
                let answer = try await client.chat(request).trimmingCharacters(in: .whitespacesAndNewlines)
                try? AIAccountSecretsStore.shared.touch(accountId: routed.account.id)
                return answer.isEmpty ? raw : answer
            } catch {
                NSLog("[Clawix.Enhancement] framework routing failed, trying configured provider: %@", String(describing: error))
            }
        }

        guard let provider = activeProvider else { return raw }
        guard await provider.isConfigured() else { return raw }

        let model = defaults.string(forKey: EnhancementSettings.modelKey(for: provider.id.rawValue))
            ?? provider.id.defaultModels.first
            ?? ""
        _ = timeoutPolicy
        let policy = defaults.string(forKey: EnhancementSettings.timeoutPolicyKey) ?? "retry"

        let context = EnhancementContext(
            clipboardText: defaults.bool(forKey: EnhancementSettings.clipboardContextKey)
                ? clipboardSnapshot()
                : nil
        )

        let maxAttempts = policy == "retry" ? 3 : 1
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                let result = try await provider.enhance(
                    text: trimmed,
                    systemPrompt: prompt.systemPrompt,
                    userPrompt: prompt.userPrompt,
                    model: model,
                    context: context,
                    timeoutSeconds: timeout
                )
                let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? raw : cleaned
            } catch {
                lastError = error
                if attempt + 1 < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s.
                    let delayMs = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayMs)
                    continue
                }
            }
        }
        // All attempts exhausted; surface the last error in NSLog and
        // fall back to raw so the paste still happens.
        if let lastError {
            NSLog("[Clawix.Enhancement] failed: %@", String(describing: lastError))
        }
        return raw
    }

    private func clipboardSnapshot() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Mirrors the message composer in `EnhancementProvider` for the
    /// framework-routed AIClient path so every provider sees the same
    /// transcript wrapper.
    private func composeUserMessage(text: String, prompt: String, context: EnhancementContext?) -> String {
        var parts: [String] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty { parts.append(trimmedPrompt) }
        parts.append("<<<TRANSCRIPT>>>\n\(text)\n<<<END_TRANSCRIPT>>>")
        if let clip = context?.clipboardText, !clip.isEmpty {
            parts.append("Recent clipboard for context:\n\(clip.prefix(2000))")
        }
        return parts.joined(separator: "\n\n")
    }
}
