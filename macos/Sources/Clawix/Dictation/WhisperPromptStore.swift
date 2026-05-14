import Foundation

/// Per-language Whisper `initial_prompt` editor (#16). The prompt
/// biases the decoder toward the formatting style and vocabulary
/// embedded in the snippet — useful for forcing capitalization,
/// punctuation, or unfamiliar terms (proper nouns, brand names) that
/// Whisper otherwise mangles.
///
/// Stored as `[String: String]` keyed by ISO 639-1 language code with
/// a JSON blob in UserDefaults. Defaults are deliberately short and
/// neutral — long prompts eat into Whisper's 244-token window.
@MainActor
final class WhisperPromptStore: ObservableObject {

    static let shared = WhisperPromptStore()

    nonisolated static let defaultsKey = "dictation.whisperPrompts"

    @Published private(set) var prompts: [String: String] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.prompts = decoded
        } else {
            self.prompts = Self.builtInDefaults
        }
    }

    func prompt(for language: String?) -> String? {
        let key = language ?? "auto"
        if let text = prompts[key], !text.isEmpty { return text }
        // Auto / unknown language: fall back to English seed (the
        // most useful for code-mixed dictation).
        return prompts["en"]
    }

    func setPrompt(_ text: String, for language: String) {
        var copy = prompts
        copy[language] = text
        prompts = copy
    }

    func resetToDefault(for language: String) {
        guard let seed = Self.builtInDefaults[language] else { return }
        var copy = prompts
        copy[language] = seed
        prompts = copy
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prompts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Conservative seed prompts. Each shows the kind of formatting
    /// the user wants the transcript to follow — punctuation, casing
    /// of acronyms, no all-caps. Intentionally a couple of sentences
    /// only so they don't burn the prompt window.
    static let builtInDefaults: [String: String] = [
        "en": "This is a casual but properly punctuated text. Acronyms like USA, EU and AI are written without periods.",
        "es": "Este es un texto con puntuación correcta y mayúsculas estándar. Las siglas USA, EU e IA van sin puntos.",
        "fr": "Voici un texte ponctué correctement. Les sigles comme USA, UE et IA s'écrivent sans points.",
        "de": "Dies ist ein normal interpunktierter Text. Abkürzungen wie USA, EU und KI werden ohne Punkte geschrieben.",
        "it": "Questo è un testo con punteggiatura corretta. Le sigle come USA, UE e IA si scrivono senza punti.",
        "pt": "Este é um texto com pontuação correta. Siglas como EUA, UE e IA são escritas sem pontos.",
        "ja": "これは句読点が正しく付いた文章です。",
        "zh": "这是标点正确的文本。",
        "ko": "이것은 구두점이 올바른 텍스트입니다.",
        "ru": "Это текст с правильной пунктуацией.",
        "auto": ""
    ]
}
