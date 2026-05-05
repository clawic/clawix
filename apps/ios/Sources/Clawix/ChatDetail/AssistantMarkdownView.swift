import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Block-level markdown renderer used by the assistant message body in
// the iOS chat. Mirrors the macOS `MarkdownDocumentView` semantics with
// the subset of markdown the agent actually emits in chat:
//
//   - ATX headings (# .. ######)
//   - paragraphs with inline `code`, **bold**, *italic*, [label](url)
//   - bullet and numbered lists
//   - fenced code blocks (```lang ... ```) with a header row showing the
//     language label and a copy affordance
//
// The parser is deliberately tolerant of in-flight streaming: an
// unclosed fence consumes everything to the end of the input so the
// user sees the partial code while it streams instead of seeing the
// raw triple-backtick.

enum AssistantBlock: Equatable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case bulletList([AttributedString])
    case numberedList(start: Int, items: [AttributedString])
    case codeBlock(language: String, code: String)
}

enum AssistantMarkdownParser {
    static func parse(_ source: String) -> [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        let raw = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if let level = headingLevel(for: trimmed) {
                let body = trimmed.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: parseInline(body)))
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var collected: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    collected.append(inner)
                    i += 1
                }
                blocks.append(.codeBlock(language: language,
                                         code: collected.joined(separator: "\n")))
                continue
            }

            if isBulletPrefix(trimmed) {
                var items: [AttributedString] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBulletPrefix(t) else { break }
                    items.append(parseInline(String(t.dropFirst(2))))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            if let firstMatch = numberedMatch(in: trimmed) {
                var items: [AttributedString] = []
                let startNumber = firstMatch.number
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let m = numberedMatch(in: t) else { break }
                    let body = String(t[m.contentStart...])
                        .trimmingCharacters(in: .whitespaces)
                    items.append(parseInline(body))
                    i += 1
                }
                blocks.append(.numberedList(start: startNumber, items: items))
                continue
            }

            // Paragraph: gather contiguous non-blank lines until the next
            // structural break (blank line, heading, fence, list).
            var paragraph: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nt = next.trimmingCharacters(in: .whitespaces)
                if nt.isEmpty
                    || headingLevel(for: nt) != nil
                    || nt.hasPrefix("```")
                    || isBulletPrefix(nt)
                    || numberedMatch(in: nt) != nil {
                    break
                }
                paragraph.append(next)
                i += 1
            }
            blocks.append(.paragraph(parseInline(paragraph.joined(separator: " "))))
        }
        return continueNumberingAcrossParagraphs(blocks)
    }

    /// Numbered list items separated by a paragraph (an explanation under
    /// each item) end up parsed as a sequence of single-item lists. If
    /// the source kept restarting at "1." (a common LLM habit, since
    /// CommonMark renderers typically auto-increment), we'd render them
    /// all as "1." even with explicit-number support. Walk the blocks
    /// and, when only paragraphs sit between two numbered lists and the
    /// next list's explicit start is `<=` the previous list's last
    /// number, treat it as a continuation. Any structural break
    /// (heading, code, bullet) resets the counter.
    private static func continueNumberingAcrossParagraphs(_ blocks: [AssistantBlock]) -> [AssistantBlock] {
        var out: [AssistantBlock] = []
        var lastEnd: Int? = nil
        var onlyParagraphsSinceLastList = false
        for block in blocks {
            switch block {
            case .numberedList(let start, let items):
                let resolvedStart: Int
                if let prevEnd = lastEnd, onlyParagraphsSinceLastList, start <= prevEnd {
                    resolvedStart = prevEnd + 1
                } else {
                    resolvedStart = start
                }
                out.append(.numberedList(start: resolvedStart, items: items))
                lastEnd = resolvedStart + items.count - 1
                onlyParagraphsSinceLastList = true
            case .paragraph:
                out.append(block)
            case .heading, .codeBlock, .bulletList:
                out.append(block)
                lastEnd = nil
                onlyParagraphsSinceLastList = false
            }
        }
        return out
    }

    private static func headingLevel(for trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes),
              trimmed.count > hashes,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " "
        else { return nil }
        return hashes
    }

    private static func isBulletPrefix(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    /// Matches a numbered list marker at the start of a trimmed line and
    /// returns both the explicit number (so we render "2." when the source
    /// says "2." instead of always falling back to `idx + 1`) and the
    /// index where the actual item content begins (after the marker and
    /// any run of whitespace, so leading spaces from `1.    Compilar`
    /// don't leak into the rendered text).
    private static func numberedMatch(in trimmed: String) -> (number: Int, contentStart: String.Index)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s+"#) else { return nil }
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: nsRange),
              let digitsRange = Range(match.range(at: 1), in: trimmed),
              let fullRange = Range(match.range, in: trimmed),
              let number = Int(trimmed[digitsRange])
        else { return nil }
        return (number, fullRange.upperBound)
    }

    private static func parseInline(_ text: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attr = try? AttributedString(markdown: text, options: opts) {
            return attr
        }
        return AttributedString(text)
    }
}

/// Renders a streamed assistant body as a vertical stack of markdown
/// blocks. Used by `ChatDetailView` instead of `Text(message.content)`
/// so the user sees fenced code in proper code blocks, headings as
/// headings, and inline `code` / **bold** / *italic* / [link](url) all
/// styled correctly.
struct AssistantMarkdownView: View {
    let text: String

    var body: some View {
        let blocks = AssistantMarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: AssistantBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let attr):
            Text(styledInline(attr))
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                            .font(Typography.bodyFont)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 8, alignment: .leading)
                        Text(styledInline(item))
                            .font(Typography.bodyFont)
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

        case .numberedList(let start, let items):
            // Render the explicit number from the source so a list whose
            // items are separated by paragraph continuations (parsed as
            // many single-item lists) still numbers correctly: each list
            // remembers where its source said it started, instead of
            // always restarting at 1 via `idx + 1`.
            //
            // Padding tuned for mobile: right-aligned marker so periods
            // line up across single/double-digit numbers, narrower frame
            // (18 vs 22) and tighter HStack spacing (6 vs 10) so the
            // indent is ~24pt total instead of ~32pt.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(start + idx).")
                            .font(Typography.bodyFont)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 18, alignment: .trailing)
                        Text(styledInline(item))
                            .font(Typography.bodyFont)
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

        case .codeBlock(let language, let code):
            AssistantCodeBlockView(language: language, code: code)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return AppFont.system(size: 22, weight: .bold)
        case 2:  return AppFont.system(size: 19, weight: .bold)
        case 3:  return AppFont.system(size: 17, weight: .semibold)
        default: return AppFont.system(size: 16, weight: .semibold)
        }
    }

    /// Tints inline `code` runs of an `AttributedString`.
    /// `inlinePresentationIntent.contains(.code)` is the system-defined
    /// indicator the markdown parser emits for backtick spans.
    /// We don't paint a `backgroundColor` chip here on purpose: SwiftUI
    /// `Text` runs render that as a sharp-edged rectangle (no squircle
    /// possible per-run), which breaks the project-wide continuous-corner
    /// language. Contrast comes from monospaced font + warm-white tint.
    private func styledInline(_ source: AttributedString) -> AttributedString {
        var out = source
        for run in out.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                out[run.range].font = .system(size: 14.5, design: .monospaced)
                out[run.range].foregroundColor = Color(white: 0.94)
            }
        }
        return out
    }
}

/// Fenced code block: dark surface, monospaced body, header row with the
/// language label and a copy button. On mobile we always horizontal-scroll
/// long lines (no word-wrap toggle); ChatGPT-iOS does the same and it
/// reads better than wrapping code at ~360pt.
private struct AssistantCodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(BodyFont.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
                Spacer(minLength: 8)
                Button(action: copy) {
                    ZStack {
                        if copied {
                            Image(systemName: "checkmark")
                                .font(BodyFont.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(white: 0.78))
                                .transition(.opacity)
                        } else {
                            CopyIconView(color: Color(white: 0.65), lineWidth: 0.85)
                                .frame(width: 14, height: 14)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(BodyFont.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary.opacity(0.94))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .textSelection(.enabled)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #endif
        withAnimation(.easeOut(duration: 0.18)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
        }
    }
}
