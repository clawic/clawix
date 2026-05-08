import Foundation
import ClawixEngine

/// Auto-format paragraphs (#7). Two paths:
///
///   * `format(_ segmented:)` — preferred, uses Whisper segment
///     timestamps. A gap between segments larger than
///     `paragraphGapSeconds` reads as "the user paused" and gets a
///     paragraph break inserted.
///   * `format(_ text:)` — fallback when segments aren't available
///     (cloud Whisper paths that only return joined text). Walks
///     sentence terminators past a soft length threshold and breaks
///     on the next capital-letter start. Less accurate but never
///     mid-sentence.
enum TranscriptFormatter {

    /// Silence threshold above which adjacent segments become
    /// separate paragraphs. Tuned to taste: 1.2 s catches deliberate
    /// pauses while still keeping the same thought together when the
    /// user takes a breath.
    private static let paragraphGapSeconds: Float = 1.2

    /// Soft character threshold for the heuristic fallback.
    private static let softLimit = 280

    static func format(_ segmented: SegmentedTranscript) -> String {
        let segments = segmented.segments
        guard segments.count >= 2 else {
            // One segment (or zero) → nothing to break. Return the
            // joined text unchanged so the caller doesn't need to
            // branch on segment count.
            return segmented.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var output = ""
        for (index, segment) in segments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if index == 0 {
                output = text
                continue
            }
            let previousEnd = segments[index - 1].end
            let gap = segment.start - previousEnd
            if gap >= paragraphGapSeconds {
                output += "\n\n" + text
            } else {
                // Glue back to the previous segment with a single
                // space; Whisper segments often don't carry trailing
                // whitespace and we don't want to glue words.
                if let lastChar = output.last, !lastChar.isWhitespace {
                    output += " "
                }
                output += text
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Heuristic fallback for cloud paths that don't expose segment
    /// timestamps. Sentence terminator + capital-letter boundary +
    /// soft length threshold. Never breaks mid-sentence.
    static func format(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > softLimit else { return trimmed }

        var output = ""
        var paragraphLength = 0
        var iter = trimmed.startIndex

        while iter < trimmed.endIndex {
            let ch = trimmed[iter]
            output.append(ch)
            paragraphLength += 1
            let next = trimmed.index(after: iter)

            if isSentenceTerminator(ch),
               paragraphLength >= softLimit,
               next < trimmed.endIndex {
                var j = next
                while j < trimmed.endIndex, trimmed[j].isWhitespace { j = trimmed.index(after: j) }
                if j < trimmed.endIndex, startsNewSentence(trimmed[j]) {
                    output.append("\n\n")
                    paragraphLength = 0
                    iter = j
                    continue
                }
            }
            iter = next
        }
        return output
    }

    private static func isSentenceTerminator(_ ch: Character) -> Bool {
        let terminators: Set<Character> = [".", "!", "?", "。", "؟", "؛"]
        return terminators.contains(ch)
    }

    private static func startsNewSentence(_ ch: Character) -> Bool {
        if ch.isUppercase { return true }
        if ch.isNumber { return true }
        if ch.isLetter, !ch.isLowercase, !ch.isUppercase { return true }
        return false
    }
}
