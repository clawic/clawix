import Foundation

/// Centralized read/write of every UserDefaults key the AI enhancement
/// module owns. Provider/account/model routing is framework-owned via
/// `FeatureRouting`; this struct only keeps host UI behavior prefs.
enum EnhancementSettings {

    // MARK: - Keys

    /// Master toggle. OFF by default — opting in is deliberate
    /// because Enhancement adds latency, can cost money, and changes
    /// the transcript text.
    static let enabledKey = "dictation.enhancement.enabled"
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
    }
}
