import Foundation

/// Common surface every enhancement backend implements. The service
/// orchestrator (`EnhancementService`) drives N providers through this
/// protocol so user code can swap providers without recompiling.
///
/// `enhance` is async and throws — providers signal HTTP errors,
/// timeouts, or schema mismatches by throwing. The orchestrator
/// catches and applies the user's `timeoutPolicy` (fail vs retry).
protocol EnhancementProvider: Sendable {
    var id: EnhancementProviderID { get }

    /// `true` when the provider has everything it needs to make a
    /// network call (API key configured, base URL reachable, etc.).
    /// The settings UI uses this to render a "connected" green dot.
    func isConfigured() -> Bool

    /// Send the raw transcript + the prompt that should drive the
    /// post-processing. Returns the enhanced text. `model` is the
    /// per-provider id the user picked; `context` is optional
    /// clipboard/screen text the user may have opted into.
    func enhance(
        text: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        context: EnhancementContext?,
        timeoutSeconds: Int
    ) async throws -> String
}

/// Optional extra context the enhancement step may consume. Both
/// fields are nil when the user hasn't opted into clipboard/screen
/// awareness (`EnhancementSettings.clipboardContextKey`).
struct EnhancementContext: Sendable {
    /// Whatever's currently on `NSPasteboard.general` as a string
    /// (truncated to a safe length before being passed in).
    var clipboardText: String?
    /// OCR-extracted text from the active window's screenshot. Wired
    /// in a follow-up; for now this is always nil even when the toggle
    /// is on.
    var screenText: String?
}

extension EnhancementProvider {
    /// Build the user-facing message that's sent to the LLM. The raw
    /// transcript is wrapped between explicit markers so the prompt
    /// can refer to it as `<<<TRANSCRIPT>>>` without confusing the
    /// model when the user prompt itself contains stray quotes.
    /// Optional context (clipboard, screen) is appended after.
    func composeUserMessage(text: String, prompt: String, context: EnhancementContext?) -> String {
        var parts: [String] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            parts.append(trimmedPrompt)
        }
        parts.append("<<<TRANSCRIPT>>>\n\(text)\n<<<END_TRANSCRIPT>>>")
        if let clip = context?.clipboardText, !clip.isEmpty {
            parts.append("Recent clipboard for context:\n\(clip.prefix(2000))")
        }
        if let screen = context?.screenText, !screen.isEmpty {
            parts.append("Screen context:\n\(screen.prefix(2000))")
        }
        return parts.joined(separator: "\n\n")
    }
}

enum EnhancementError: Error, LocalizedError {
    case notConfigured
    case timedOut
    case provider(String)
    case decoding(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configure your provider's API key first."
        case .timedOut:
            return "Enhancement timed out."
        case .provider(let detail):
            return "Provider error: \(detail)"
        case .decoding(let detail):
            return "Couldn't parse the response: \(detail)"
        case .http(let code, let body):
            return "HTTP \(code): \(body.prefix(160))"
        }
    }
}
