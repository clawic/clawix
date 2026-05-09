import Foundation

enum AccessibilityText {
    private static let maxCharacters = 500

    static func clipped(_ text: String, emptyFallback: String? = nil) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return emptyFallback ?? clean
        }
        guard let end = clean.index(
            clean.startIndex,
            offsetBy: maxCharacters,
            limitedBy: clean.endIndex
        ) else {
            return clean
        }
        return String(clean[..<end]) + " ..."
    }
}
