import Foundation
import ClawixEngine

/// Single power-mode profile. A "power mode" is a context-aware
/// override layer that auto-activates when the user is in a specific
/// app (or on a specific website), so different contexts can get their
/// own dictation behaviour without manual switching.
///
/// Many fields are overrides: when nil/empty, dictation falls back to
/// the global defaults; when set, they win.
struct PowerModeConfig: Identifiable, Codable, Equatable {
    /// Stable random ID. Generated on insert; never reused even after
    /// rename/edit so settings sync (#26) can match across machines.
    let id: UUID
    var name: String
    /// Single-glyph emoji shown next to the name in the list and as
    /// the badge in the recorder pill when this PM is active.
    var emoji: String

    // MARK: Triggers

    /// Bundle identifiers that activate this profile.
    var triggerBundleIds: [String]
    /// URL host substrings that activate this profile when the
    /// foreground app is a supported browser (Safari, Chrome, Arc,
    /// Brave). E.g. `github.com`. Substring match, case-insensitive.
    var triggerURLHosts: [String]

    // MARK: Transcription overrides

    /// Override the active dictation model for this profile. nil =
    /// keep the user's global selection.
    var transcriptionModelOverride: DictationModel?
    /// Override Whisper language code. nil = use global. Use `"auto"`
    /// to force auto-detect specifically for this profile even if the
    /// global is a fixed language.
    var languageOverride: String?
    /// Per-PM Whisper `initial_prompt`. Overrides the per-language
    /// global prompt set in `WhisperPromptStore`. nil = use global.
    var whisperPromptOverride: String?

    // MARK: Enhancement overrides

    var enhancementEnabled: Bool

    // MARK: Output overrides

    /// `none` is treated as "use global setting"; any concrete enum
    /// case wins as an override. We keep the string form to keep the
    /// JSON forward-compatible if the enum grows.
    var autoSendKeyOverride: String?

    // MARK: Behavior

    /// When true, this profile is the fallback when no app/URL match
    /// fires. Exactly one config is `isDefault`; the manager enforces
    /// uniqueness on save.
    var isDefault: Bool
    /// User can disable a profile without deleting it.
    var enabled: Bool

    // MARK: Convenience

    static func newBlank(name: String = "New profile", emoji: String = "✨") -> PowerModeConfig {
        PowerModeConfig(
            id: UUID(),
            name: name,
            emoji: emoji,
            triggerBundleIds: [],
            triggerURLHosts: [],
            transcriptionModelOverride: nil,
            languageOverride: nil,
            whisperPromptOverride: nil,
            enhancementEnabled: false,
            autoSendKeyOverride: nil,
            isDefault: false,
            enabled: true
        )
    }
}

/// Curated profiles seeded on first launch. Bundle IDs and the
/// language defaults reflect typical Spanish + English mixed usage,
/// which matches the user base.
enum PowerModePresets {
    static let presets: [PowerModeConfig] = [
        PowerModeConfig(
            id: UUID(),
            name: "Clawix",
            emoji: "🦊",
            triggerBundleIds: [
                Bundle.main.bundleIdentifier ?? "com.example.clawix.desktop"
            ],
            triggerURLHosts: [],
            transcriptionModelOverride: nil,
            languageOverride: nil,
            whisperPromptOverride: nil,
            enhancementEnabled: false,
            autoSendKeyOverride: DictationAutoSendKey.cmdEnter.rawValue,
            isDefault: false,
            enabled: true
        ),
        PowerModeConfig(
            id: UUID(),
            name: "Chat",
            emoji: "💬",
            triggerBundleIds: [],
            triggerURLHosts: [],
            transcriptionModelOverride: nil,
            languageOverride: nil,
            whisperPromptOverride: nil,
            enhancementEnabled: false,
            autoSendKeyOverride: DictationAutoSendKey.enter.rawValue,
            isDefault: false,
            enabled: true
        ),
        PowerModeConfig(
            id: UUID(),
            name: "Code editor",
            emoji: "📝",
            triggerBundleIds: [],
            triggerURLHosts: [],
            transcriptionModelOverride: nil,
            languageOverride: nil,
            whisperPromptOverride: "This is a technical text. Code keywords like `func`, `let`, `var`, `if`, `else`, `return`, `for`, `while`, `nil`, `true`, `false` are written verbatim.",
            enhancementEnabled: false,
            autoSendKeyOverride: DictationAutoSendKey.none.rawValue,
            isDefault: false,
            enabled: true
        ),
        PowerModeConfig(
            id: UUID(),
            name: "Mail",
            emoji: "✉️",
            triggerBundleIds: ["com.apple.mail"],
            triggerURLHosts: [],
            transcriptionModelOverride: nil,
            languageOverride: nil,
            whisperPromptOverride: nil,
            enhancementEnabled: false,
            autoSendKeyOverride: DictationAutoSendKey.none.rawValue,
            isDefault: false,
            enabled: true
        )
    ]
}
