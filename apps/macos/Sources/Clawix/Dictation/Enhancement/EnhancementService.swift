import Foundation
import AppKit

/// Orchestrator que se sienta entre Whisper y el TextInjector. Si el
/// master toggle (`EnhancementSettings.enabledKey`) está on, llama al
/// LLM con el prompt activo y devuelve el texto procesado. Si está
/// off, pasa el texto sin tocar.
///
/// La política de fallos respeta el preset del usuario:
///   * `fail` — devuelve el texto raw (transparente para el usuario,
///     paste sigue funcionando aunque el LLM no responda).
///   * `retry` — hasta 3 intentos con backoff exponencial (1s, 2s, 4s)
///     antes de caer al texto raw.
///
/// Skip-short (#18) corta antes de la llamada cuando el transcript
/// tiene menos palabras que el umbral configurado, para no quemar
/// llamadas LLM en utterances tipo "ok" o "sí".
@MainActor
final class EnhancementService {

    static let shared = EnhancementService()

    /// Rate-limit: como mínimo 1 segundo entre dos calls para
    /// proteger la quota del usuario y evitar que un atajo doble
    /// pulse dispare dos requests paralelos.
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

        guard let provider = activeProvider else { return raw }
        guard provider.isConfigured() else { return raw }

        let prompt = PromptLibrary.shared.activePrompt()
        let model = defaults.string(forKey: EnhancementSettings.modelKey(for: provider.id.rawValue))
            ?? provider.id.defaultModels.first
            ?? ""
        let timeout = defaults.integer(forKey: EnhancementSettings.timeoutSecondsKey)
        let policy = defaults.string(forKey: EnhancementSettings.timeoutPolicyKey) ?? "retry"

        let context = EnhancementContext(
            clipboardText: defaults.bool(forKey: EnhancementSettings.clipboardContextKey)
                ? clipboardSnapshot()
                : nil,
            screenText: nil // Wired in a follow-up (ScreenCaptureKit + OCR).
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
}
