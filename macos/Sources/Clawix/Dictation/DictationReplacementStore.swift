import Foundation
import Combine

/// Owns the user's dictionary of dictation substitutions and applies
/// them to a Whisper transcript on demand.
///
/// Persistence: a single JSON-encoded array under
/// `dictation.replacements` in `UserDefaults`. This matches every other
/// dictation setting (see `DictationCoordinator.injectDefaultsKey` and
/// friends) and keeps the feature out of the GRDB schema for now.
///
/// Matching rules applied by `apply(to:)`:
///
///   - Case-insensitive match against the entry's variants.
///   - Word boundary aware via Unicode lookarounds — "ink" does not
///     match inside "thinking", but "ink." and "ink," still match.
///   - Variants are matched longest-first so that a more specific
///     entry ("supabase") wins over a shorter one ("base") when both
///     appear in the text.
///   - Smart-case applied to each match: if the matched substring is
///     all uppercase (≥2 letters) the canonical replacement is
///     uppercased; otherwise the canonical replacement is used
///     verbatim. This preserves emphasis ("CLAUDE" stays loud) while
///     letting the user define the form they actually want for the
///     normal case.
@MainActor
final class DictationReplacementStore: ObservableObject {

    static let shared = DictationReplacementStore()

    nonisolated static let defaultsKey = "dictation.replacements"

    @Published private(set) var entries: [DictationReplacement]

    enum AddError: Error, Equatable {
        case emptyOriginal
        case emptyReplacement
        /// At least one variant in `original` (case-insensitive) is
        /// already used by another entry. The associated value is the
        /// other entry's `original` string so the UI can tell the user
        /// which entry to edit instead.
        case duplicateVariant(conflictingEntryOriginal: String, variant: String)
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    // MARK: - Mutations

    @discardableResult
    func add(original: String, replacement: String) -> Result<DictationReplacement, AddError> {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOriginal.isEmpty { return .failure(.emptyOriginal) }
        if trimmedReplacement.isEmpty { return .failure(.emptyReplacement) }

        let candidate = DictationReplacement(
            original: trimmedOriginal,
            replacement: trimmedReplacement
        )
        if let conflict = firstConflict(for: candidate, ignoring: nil) {
            return .failure(conflict)
        }

        entries.insert(candidate, at: 0)
        save()
        return .success(candidate)
    }

    /// Updates an existing entry by `id`. Returns `.failure` if the
    /// entry no longer exists or if any of its variants now collide
    /// with another entry.
    @discardableResult
    func update(_ entry: DictationReplacement) -> Result<DictationReplacement, AddError> {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else {
            return .failure(.emptyOriginal)
        }
        let trimmedOriginal = entry.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOriginal.isEmpty { return .failure(.emptyOriginal) }
        if trimmedReplacement.isEmpty { return .failure(.emptyReplacement) }

        var updated = entry
        updated.original = trimmedOriginal
        updated.replacement = trimmedReplacement
        if let conflict = firstConflict(for: updated, ignoring: entry.id) {
            return .failure(conflict)
        }
        entries[idx] = updated
        save()
        return .success(updated)
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].enabled = enabled
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Apply

    /// Runs every enabled entry's variants over `text`, applying smart
    /// case to each match. Returns the rewritten string.
    func apply(to text: String) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        // Flatten enabled entries into (variant, canonicalReplacement)
        // pairs and sort longest-first so specific variants win over
        // shorter substrings ("supabase" before "base").
        struct Rule {
            let variant: String
            let replacement: String
        }
        var rules: [Rule] = []
        for entry in entries where entry.enabled {
            let canonical = entry.replacement
            guard !canonical.isEmpty else { continue }
            for variant in entry.variants {
                rules.append(Rule(variant: variant, replacement: canonical))
            }
        }
        guard !rules.isEmpty else { return text }
        rules.sort { lhs, rhs in
            if lhs.variant.count != rhs.variant.count {
                return lhs.variant.count > rhs.variant.count
            }
            return lhs.variant < rhs.variant
        }

        var output = text as NSString
        for rule in rules {
            let pattern = Self.buildPattern(for: rule.variant)
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let fullRange = NSRange(location: 0, length: output.length)
            let matches = regex.matches(in: output as String, options: [], range: fullRange)
            // Walk matches right-to-left so each replacement does not
            // shift the offsets of the matches still ahead of us.
            for match in matches.reversed() {
                let matchedString = output.substring(with: match.range)
                let replaced = Self.smartCase(replacement: rule.replacement, matchedAs: matchedString)
                output = output.replacingCharacters(in: match.range, with: replaced) as NSString
            }
        }
        return output as String
    }

    // MARK: - Helpers

    private func firstConflict(
        for candidate: DictationReplacement,
        ignoring ignoredID: UUID?
    ) -> AddError? {
        let candidateVariants = candidate.variants
        guard !candidateVariants.isEmpty else { return .emptyOriginal }
        let candidateLowered = Set(candidateVariants.map { $0.lowercased() })
        for existing in entries where existing.id != ignoredID {
            for v in existing.variants where candidateLowered.contains(v.lowercased()) {
                return .duplicateVariant(
                    conflictingEntryOriginal: existing.original,
                    variant: v
                )
            }
        }
        return nil
    }

    /// Wraps `variant` in Unicode word-boundary lookarounds so that the
    /// match does not eat into surrounding letters or digits. We skip
    /// the lookaround on whichever side already starts/ends with a
    /// non-letter character (so an entry like `"don't"` still matches
    /// inside a sentence). If the variant contains only non-letter
    /// characters we fall back to substring matching, which is the
    /// right behaviour for CJK / Hangul / Hiragana scripts.
    private static func buildPattern(for variant: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: variant)
        let leadIsLetter = variant.first.map(Self.isLetterOrDigit) ?? false
        let tailIsLetter = variant.last.map(Self.isLetterOrDigit) ?? false
        if !leadIsLetter && !tailIsLetter { return escaped }
        var pattern = ""
        if leadIsLetter { pattern += #"(?<![\p{L}\p{N}])"# }
        pattern += escaped
        if tailIsLetter { pattern += #"(?![\p{L}\p{N}])"# }
        return pattern
    }

    private static func isLetterOrDigit(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }

    /// Smart case rule:
    ///
    /// - matched substring is ALL CAPS (≥2 cased letters) → uppercase
    ///   the canonical replacement so emphasis carries through.
    /// - everything else (lower, Title, mixed) → use the canonical
    ///   replacement verbatim so internal capitalisation the user
    ///   defined ("Supabase", "GraphQL") is preserved.
    static func smartCase(replacement: String, matchedAs match: String) -> String {
        guard match.count >= 2 else { return replacement }
        let upper = match.uppercased()
        let lower = match.lowercased()
        if match == upper && upper != lower {
            return replacement.uppercased()
        }
        return replacement
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> [DictationReplacement] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DictationReplacement].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
