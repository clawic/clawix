import Foundation

/// A user-defined substitution applied to the Whisper transcript right
/// before it is pasted/delivered. The `original` field accepts a
/// comma-separated list of variants ("super base, Supabase, Superbase")
/// because Whisper tends to misrecognise the same proper noun in
/// several different ways; one entry covers them all and shares a
/// single canonical replacement.
struct DictationReplacement: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var original: String
    var replacement: String
    var enabled: Bool
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        original: String,
        replacement: String,
        enabled: Bool = true,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.enabled = enabled
        self.dateAdded = dateAdded
    }

    /// Variants split from `original` by comma, trimmed, and deduped
    /// case-insensitively while preserving the casing of the first
    /// occurrence (so "Claude, claude" round-trips to ["Claude"]).
    var variants: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in original.split(separator: ",") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
            }
        }
        return out
    }
}
