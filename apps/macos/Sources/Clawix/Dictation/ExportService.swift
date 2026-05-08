import Foundation

/// CSV / JSON export entry points (#26). Both produce a temporary
/// file in `NSTemporaryDirectory()` and return the URL; UI saves it
/// via `NSSavePanel`.
@MainActor
enum DictationExportService {

    // MARK: - Transcripts CSV

    static func exportTranscripts() async throws -> URL {
        let rows = try await TranscriptionsRepository.shared.fetchPage(offset: 0, limit: 100_000)
        var csv = "id,timestamp,model,language,duration_s,word_count,original,enhanced\n"
        let formatter = ISO8601DateFormatter()
        for row in rows {
            let parts = [
                row.id,
                formatter.string(from: row.timestamp),
                row.modelUsed ?? "",
                row.language ?? "",
                String(format: "%.2f", row.durationSeconds),
                String(row.wordCount),
                escape(row.originalText),
                escape(row.enhancedText ?? "")
            ]
            csv.append(parts.joined(separator: ","))
            csv.append("\n")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawix-transcripts-\(Date().timeIntervalSince1970).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ field: String) -> String {
        // RFC 4180 light: wrap in double quotes when the field
        // contains a comma, quote, or newline; double-up internal
        // quotes.
        var needsQuoting = false
        for ch in field {
            if ch == "," || ch == "\"" || ch == "\n" || ch == "\r" {
                needsQuoting = true
                break
            }
        }
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - Settings JSON

    /// Serialize every dictation pref UserDefaults key (and a few
    /// adjacent stores) into a single JSON dump suitable for backup
    /// and transfer between machines. **Excludes** API keys —
    /// Keychain entries don't travel through this path.
    static func exportSettings() throws -> URL {
        let defaults = UserDefaults.standard
        var dump: [String: Any] = [:]

        let prefixes = ["dictation.", "quickAsk."]
        for (key, value) in defaults.dictionaryRepresentation() {
            for prefix in prefixes where key.hasPrefix(prefix) {
                // Keychain references aren't UserDefaults; nothing to
                // skip here. API key text fields never write directly
                // to UserDefaults — `EnhancementKeychain` puts them
                // in the keychain. So this enumeration is safe.
                dump[key] = value
                break
            }
        }
        let payload: [String: Any] = [
            "schema": "clawix-dictation-settings",
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "values": dump
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawix-dictation-settings-\(Date().timeIntervalSince1970).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Inverse of `exportSettings`. Reads `values` and writes each
    /// key back into UserDefaults. Skips the schema metadata. Returns
    /// the count of keys written.
    @discardableResult
    static func importSettings(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["values"] as? [String: Any] else {
            throw NSError(
                domain: "ClawixDictationImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File doesn't look like a Clawix settings JSON."]
            )
        }
        let defaults = UserDefaults.standard
        var written = 0
        for (key, value) in values {
            defaults.set(value, forKey: key)
            written += 1
        }
        return written
    }
}
