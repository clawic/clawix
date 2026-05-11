import Foundation

/// Minimal YAML emitter / parser used to persist agent / personality /
/// skill-collection / connection records under `~/.clawjs/`. Only
/// supports the flat shape this project actually uses:
///
/// ```yaml
/// # comment
/// stringKey: value
/// stringKey: "quoted value with : colon"
/// boolKey: true
/// intKey: 42
/// arrayKey:
///   - one
///   - two
/// ```
///
/// `SimpleYaml` is intentionally NOT a general-purpose YAML library: it
/// trades coverage for predictability and zero dependencies. Anything
/// the project needs that does not fit the grammar above goes into its
/// own file (see the per-record layout under `~/.clawjs/agents/<id>/`),
/// not into nested YAML.
enum SimpleYaml {

    enum Value {
        case string(String)
        case bool(Bool)
        case int(Int)
        case array([Value])
    }

    // MARK: - Emit

    static func emit(_ dict: [(String, Value)]) -> String {
        var lines: [String] = []
        for (key, value) in dict {
            switch value {
            case .string(let s):
                lines.append("\(key): \(encodeScalar(s))")
            case .bool(let b):
                lines.append("\(key): \(b ? "true" : "false")")
            case .int(let i):
                lines.append("\(key): \(i)")
            case .array(let items):
                if items.isEmpty {
                    lines.append("\(key): []")
                } else {
                    lines.append("\(key):")
                    for item in items {
                        switch item {
                        case .string(let s):
                            lines.append("  - \(encodeScalar(s))")
                        case .bool(let b):
                            lines.append("  - \(b ? "true" : "false")")
                        case .int(let i):
                            lines.append("  - \(i)")
                        case .array:
                            // Nested arrays are out of scope.
                            continue
                        }
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func encodeScalar(_ s: String) -> String {
        // Quote when the scalar contains characters that would change
        // the meaning of the line (colon, hash, leading dash, leading
        // whitespace) or when it is empty / would parse as bool/int.
        if s.isEmpty { return "\"\"" }
        let needsQuoting = s.contains(":") || s.contains("#") || s.contains("\n")
            || s.hasPrefix("- ") || s.hasPrefix(" ") || s.hasSuffix(" ")
            || ["true", "false", "yes", "no", "null", "~"].contains(s.lowercased())
            || Int(s) != nil
        if needsQuoting {
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }

    // MARK: - Parse

    static func parse(_ text: String) -> [String: Value] {
        var dict: [String: Value] = [:]
        var pendingArrayKey: String?
        var pendingArrayItems: [Value] = []

        func flushPendingArray() {
            if let key = pendingArrayKey {
                dict[key] = .array(pendingArrayItems)
                pendingArrayKey = nil
                pendingArrayItems = []
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Skip comment-only lines and blank lines but flush any
            // pending array context first so a blank line after items
            // closes the array cleanly.
            let trimmedLeading = line.drop(while: { $0 == " " })
            if trimmedLeading.isEmpty || trimmedLeading.first == "#" {
                continue
            }
            let isIndented = line.hasPrefix("  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isIndented, trimmed.hasPrefix("- "), pendingArrayKey != nil {
                let item = String(trimmed.dropFirst(2))
                pendingArrayItems.append(.string(decodeScalar(item)))
                continue
            }
            // New top-level key. Close any open array context.
            flushPendingArray()
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                pendingArrayKey = key
                pendingArrayItems = []
                continue
            }
            if rest == "[]" {
                dict[key] = .array([])
                continue
            }
            let decoded = decodeScalar(rest)
            switch decoded.lowercased() {
            case "true":  dict[key] = .bool(true)
            case "false": dict[key] = .bool(false)
            default:
                if let intVal = Int(decoded) {
                    dict[key] = .int(intVal)
                } else {
                    dict[key] = .string(decoded)
                }
            }
        }
        flushPendingArray()
        return dict
    }

    private static func decodeScalar(_ s: String) -> String {
        guard s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Convenience getters

    static func string(_ dict: [String: Value], _ key: String, default fallback: String = "") -> String {
        if case let .string(s) = dict[key] { return s }
        return fallback
    }

    static func bool(_ dict: [String: Value], _ key: String, default fallback: Bool = false) -> Bool {
        if case let .bool(b) = dict[key] { return b }
        return fallback
    }

    static func int(_ dict: [String: Value], _ key: String, default fallback: Int = 0) -> Int {
        if case let .int(i) = dict[key] { return i }
        return fallback
    }

    static func stringArray(_ dict: [String: Value], _ key: String) -> [String] {
        if case let .array(items) = dict[key] {
            return items.compactMap {
                if case let .string(s) = $0 { return s }
                return nil
            }
        }
        return []
    }
}
