import Foundation

/// Vocabulary-hint store (#15). Distinct from `DictationReplacementStore`,
/// which post-processes Whisper output. Here we send a comma-joined
/// list of terms to Whisper as part of the `initial_prompt` so the
/// decoder weights those tokens higher and gets proper nouns / jargon
/// / brand names right at the source.
///
/// Persistence: a single JSON-encoded `[String]` in UserDefaults.
/// Keeping vocabulary global (not per-language) is intentional — most
/// proper nouns ("Clawix", "Tailscale", "OpenAI") are language-agnostic.
@MainActor
final class VocabularyManager: ObservableObject {

    static let shared = VocabularyManager()

    static let defaultsKey = "dictation.vocabulary"

    @Published private(set) var entries: [String] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = []
        }
    }

    /// Add a single term, ignoring duplicates (case-insensitive) and
    /// blank input.
    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if entries.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }
        var copy = entries
        copy.append(trimmed)
        entries = copy
    }

    func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        var copy = entries
        copy.remove(at: index)
        entries = copy
    }

    func remove(_ term: String) {
        var copy = entries
        copy.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        entries = copy
    }

    /// Comma-joined string suitable for splicing into a Whisper
    /// `initial_prompt`. Returns nil when the list is empty so callers
    /// can decide between "no vocabulary" and "empty prompt".
    func asPromptFragment() -> String? {
        guard !entries.isEmpty else { return nil }
        return entries.joined(separator: ", ")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
