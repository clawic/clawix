import Foundation

public struct PlaceholderToken: Codable, Sendable, Hashable {
    public let raw: String
    public let secretInternalName: String
    public let fieldName: String?

    public init(raw: String, secretInternalName: String, fieldName: String?) {
        self.raw = raw
        self.secretInternalName = secretInternalName
        self.fieldName = fieldName
    }
}

public enum PlaceholderResolver {

    /// Match `{{name}}` or `{{name.field}}`. Names and field names allow letters,
    /// digits, dashes, underscores. Whitespace inside the braces is tolerated so
    /// `{{ openai_main . token }}` resolves the same as `{{openai_main.token}}`.
    private static let regex: NSRegularExpression = {
        let pattern = #"\{\{\s*([A-Za-z0-9_\-]+)(?:\s*\.\s*([A-Za-z0-9_\-]+))?\s*\}\}"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    public static func tokens(in text: String) -> [PlaceholderToken] {
        guard !text.isEmpty else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        var result: [PlaceholderToken] = []
        for match in matches {
            let raw = nsText.substring(with: match.range)
            if seen.contains(raw) { continue }
            seen.insert(raw)
            guard match.range(at: 1).location != NSNotFound else { continue }
            let name = nsText.substring(with: match.range(at: 1))
            let field: String?
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                field = nsText.substring(with: match.range(at: 2))
            } else {
                field = nil
            }
            result.append(PlaceholderToken(raw: raw, secretInternalName: name, fieldName: field))
        }
        return result
    }

    public static func tokens(in collection: [String]) -> [PlaceholderToken] {
        var seen = Set<String>()
        var result: [PlaceholderToken] = []
        for text in collection {
            for token in tokens(in: text) where !seen.contains(token.raw) {
                seen.insert(token.raw)
                result.append(token)
            }
        }
        return result
    }

    public static func substitute(_ text: String, with values: [String: String]) -> String {
        guard !values.isEmpty else { return text }
        var output = text
        for (raw, value) in values {
            output = output.replacingOccurrences(of: raw, with: value)
        }
        return output
    }
}
