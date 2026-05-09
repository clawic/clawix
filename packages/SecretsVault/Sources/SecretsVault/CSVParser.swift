import Foundation

/// Minimal RFC4180-ish CSV parser. Handles double-quoted fields with
/// escaped quotes (`""`), embedded commas, embedded newlines. Tolerant of
/// `\r\n` line endings and a trailing newline.
public enum CSVParser {

    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuote = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuote {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuote = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case ",":
                    current.append(field)
                    field = ""
                case "\n":
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                case "\r":
                    break
                case "\"":
                    inQuote = true
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }
}
