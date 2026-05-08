import Foundation

public struct RedactionEntry: Equatable, Hashable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public enum Redactor {

    /// Replace every occurrence of each `value` in the text with its `label`.
    /// Replacements are applied in order of decreasing value length so a long
    /// secret that contains a shorter secret as substring is masked first and
    /// the residual cannot match the shorter pattern.
    public static func redact(_ text: String, with entries: [RedactionEntry]) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }
        let sorted = entries
            .filter { !$0.value.isEmpty }
            .sorted { $0.value.count > $1.value.count }
        var output = text
        for entry in sorted {
            output = output.replacingOccurrences(of: entry.value, with: entry.label)
        }
        return output
    }

    /// Convenience for binary buffers. UTF-8-encoded data is redacted as text;
    /// non-UTF-8 data is returned untouched (the proxy currently does not
    /// pretend to redact binary streams).
    public static func redact(data: Data, with entries: [RedactionEntry]) -> Data {
        guard !entries.isEmpty, !data.isEmpty else { return data }
        guard let text = String(data: data, encoding: .utf8) else { return data }
        return Data(redact(text, with: entries).utf8)
    }

    /// Stable label format consumed by Codex / agents reading the redacted
    /// output. Matches the spec text injected into AGENTS.md.
    public static func label(forSecretInternalName name: String, customLabel: String? = nil) -> String {
        if let customLabel, !customLabel.isEmpty { return customLabel }
        return "[REDACTED:\(name)]"
    }
}
