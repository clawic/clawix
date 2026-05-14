import Foundation

/// Removes hesitation sounds and discourse fillers from a transcript
/// after Whisper hands it back. Words are matched word-boundary +
/// case-insensitive, then collapsed runs of whitespace are normalized
/// and orphan punctuation (a comma left by removing the word in front
/// of it) is cleaned.
///
/// Multi-language by default — when the user dictates in mixed
/// Spanish + English (the most common case for this codebase), both
/// lists need to apply. The store keeps a per-language list keyed by
/// ISO code; the active set is the union of the dictation language's
/// list + the English fallback. With language `auto`, the union of
/// every active language is used (more recall, slightly more risk of
/// over-removal).
@MainActor
final class FillerWordsManager: ObservableObject {

    static let shared = FillerWordsManager()

    nonisolated static let enabledKey = "dictation.fillerWords.enabled"
    nonisolated static let listKey = "dictation.fillerWords.list"

    @Published private(set) var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    /// Dictionary keyed by ISO 639-1 language code. Each value is the
    /// list of filler words/phrases for that language. Mutating
    /// triggers a JSON write to UserDefaults.
    @Published private(set) var lists: [String: [String]] {
        didSet { persistLists() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        if let data = defaults.data(forKey: Self.listKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            // Merge user data on top of defaults so newly-added
            // languages in subsequent app updates appear without
            // wiping any existing customizations.
            var merged = Self.builtInDefaults
            for (k, v) in decoded { merged[k] = v }
            self.lists = merged
        } else {
            self.lists = Self.builtInDefaults
            // Persist immediately so the editor UI sees its initial
            // state even before the user touches anything.
            // (didSet runs only on subsequent assignments.)
            if let data = try? JSONEncoder().encode(Self.builtInDefaults) {
                defaults.set(data, forKey: Self.listKey)
            }
        }
    }

    func setEnabled(_ on: Bool) { enabled = on }

    func setList(_ words: [String], for language: String) {
        var copy = lists
        copy[language] = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        lists = copy
    }

    func resetToDefault(for language: String) {
        guard let defaultsForLang = Self.builtInDefaults[language] else { return }
        var copy = lists
        copy[language] = defaultsForLang
        lists = copy
    }

    private func persistLists() {
        if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: Self.listKey)
        }
    }

    // MARK: - Application

    /// Strip filler words from `text`. `language` is the dictation
    /// language code (`"es"`, `"en"`, `"auto"`, etc.). When `auto`,
    /// the union of every list is used.
    func apply(to text: String, language: String?) -> String {
        guard enabled else { return text }
        let words = wordsForLanguage(language)
        guard !words.isEmpty else { return text }

        // Sort longest-first so multi-word phrases ("you know") are
        // matched before single-word fragments that could otherwise
        // partially consume them ("you").
        let sorted = words.sorted { $0.count > $1.count }

        var result = text
        for word in sorted {
            // Escape regex metacharacters in the word itself.
            let escaped = NSRegularExpression.escapedPattern(for: word)
            // Word-boundary at both ends + case-insensitive. `\b`
            // works for ASCII but doesn't cover all CJK/Cyrillic
            // boundaries; for those we wrap with start/end-of-string
            // OR whitespace/punctuation lookarounds.
            let pattern: String
            if word.first?.isASCII == true {
                pattern = "(?i)\\b\(escaped)\\b"
            } else {
                pattern = "(?i)(?:^|\\s|[\\p{P}])(\(escaped))(?=$|\\s|[\\p{P}])"
            }
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: ""
                )
            }
        }

        return cleanup(result)
    }

    /// Collapse the artifacts removal leaves behind:
    ///   - ", , " or " ,  ," after dropping a word
    ///   - leading whitespace before "."
    ///   - double spaces
    ///   - leading/trailing whitespace + punctuation
    private func cleanup(_ s: String) -> String {
        var result = s
        // Multiple spaces → single space (across lines we keep \n).
        result = result.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )
        // Space before sentence punctuation.
        result = result.replacingOccurrences(
            of: " +([,.;:!?])",
            with: "$1",
            options: .regularExpression
        )
        // Comma followed by another comma (orphan from dropping a word
        // in a comma list).
        result = result.replacingOccurrences(
            of: ",\\s*,",
            with: ",",
            options: .regularExpression
        )
        // Leading punctuation/whitespace.
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    private func wordsForLanguage(_ language: String?) -> [String] {
        if let language, language != "auto" {
            // The dictation language plus English (most users mix in
            // some English even when dictating in their native lang).
            let primary = lists[language] ?? []
            let fallback = lists["en"] ?? []
            return Array(Set(primary + fallback))
        }
        // Auto: union of every list.
        return Array(Set(lists.values.flatMap { $0 }))
    }

    // MARK: - Defaults

    /// Multi-language seed list. Conservative defaults: only words
    /// that almost universally function as fillers in their language.
    /// "Like" and "so" in English are intentionally included even
    /// though they have non-filler senses — the user can remove them
    /// from the editor if they hit false positives.
    static let builtInDefaults: [String: [String]] = [
        "es": ["ehh", "eh", "este", "o sea", "pues", "bueno", "vale", "digamos", "em", "ehm", "mmm"],
        "en": ["uh", "um", "uhm", "hmm", "er", "ah", "like", "you know", "so", "well", "basically", "literally", "actually"],
        "fr": ["euh", "ben", "bah", "donc", "alors", "voilà", "hein"],
        "de": ["äh", "ähm", "also", "halt", "eben", "ja"],
        "it": ["eh", "ehm", "cioè", "allora", "insomma", "mah", "beh"],
        "pt": ["é", "hum", "então", "tipo", "sabe", "ó", "pois"],
        "ja": ["えー", "あの", "その", "ええと", "まあ"],
        "zh": ["嗯", "啊", "呃", "那个", "这个"],
        "ko": ["음", "어", "그", "저"],
        "ru": ["ну", "э-э", "типа", "как бы", "короче"],
        "ar": ["يعني", "طيب", "شو"],
        "hi": ["मतलब", "यानी", "अरे"]
    ]
}
