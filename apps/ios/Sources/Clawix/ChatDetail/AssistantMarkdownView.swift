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

/// Cached parse result. Wrapped in a class so it can live in
/// `NSCache`, which only stores `AnyObject` values.
private final class CachedAssistantBlocks {
    let blocks: [AssistantBlock]
    init(_ blocks: [AssistantBlock]) { self.blocks = blocks }
}

enum AssistantMarkdownParser {
    /// Compiled once per process. The pattern is identical between
    /// calls so paying the regex compile cost on every `numberedMatch`
    /// invocation (which happens for every line of every paragraph
    /// during streaming) is pure waste.
    fileprivate static let numberedRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"^(\d+)[.)]\s+"#)

    /// Memoizes block lists keyed by the exact source string. The
    /// SwiftUI body of `AssistantMarkdownView` re-runs whenever any
    /// observed state in the chat detail mutates (a streaming chunk
    /// arrives for *another* message, the user toggles reasoning on
    /// some message, etc). Without this cache, every body cycle
    /// re-parses the full markdown of every visible message. Capped
    /// at 64 entries; NSCache evicts under memory pressure for free.
    fileprivate static let cache: NSCache<NSString, CachedAssistantBlocks> = {
        let c = NSCache<NSString, CachedAssistantBlocks>()
        c.countLimit = 64
        return c
    }()

    static func parse(_ source: String) -> [AssistantBlock] {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }
        let blocks = parseUncached(source)
        cache.setObject(CachedAssistantBlocks(blocks), forKey: key)
        return blocks
    }

    private static func parseUncached(_ source: String) -> [AssistantBlock] {
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
        guard let regex = numberedRegex else { return nil }
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
///
/// Selection model: contiguous prose blocks (paragraphs, headings,
/// lists) coalesce into a single `SelectableProseTextView` so the
/// user can long-press anywhere in the reply and drag the selection
/// across blocks like in a normal page. Code blocks stay separate
/// because they keep their own fenced chrome (language label + copy
/// button) and their own selectable text view inside.
struct AssistantMarkdownView: View {
    let text: String

    /// A run of consecutive blocks that should share one selection
    /// surface. Code blocks always stand alone; everything else
    /// (paragraphs, headings, bullet/numbered lists) coalesces.
    private enum BlockGroup {
        case prose([AssistantBlock])
        case code(language: String, code: String)
    }

    var body: some View {
        let blocks = AssistantMarkdownParser.parse(text)
        let groups = Self.groupForSelection(blocks)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                groupView(group)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func groupView(_ group: BlockGroup) -> some View {
        switch group {
        case .prose(let blocks):
            #if canImport(UIKit)
            SelectableProseTextView(blocks: blocks)
            #else
            // Non-UIKit fallback (previews / macOS catalyst): render
            // each block as before so the code keeps compiling.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    Text(blockFallbackText(block))
                        .font(Typography.chatBodyFont)
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            #endif

        case .code(let language, let code):
            AssistantCodeBlockView(language: language, code: code)
        }
    }

    private static func groupForSelection(_ blocks: [AssistantBlock]) -> [BlockGroup] {
        var groups: [BlockGroup] = []
        var pendingProse: [AssistantBlock] = []
        for block in blocks {
            if case .codeBlock(let language, let code) = block {
                if !pendingProse.isEmpty {
                    groups.append(.prose(pendingProse))
                    pendingProse.removeAll()
                }
                groups.append(.code(language: language, code: code))
            } else {
                pendingProse.append(block)
            }
        }
        if !pendingProse.isEmpty {
            groups.append(.prose(pendingProse))
        }
        return groups
    }

    #if !canImport(UIKit)
    private func blockFallbackText(_ block: AssistantBlock) -> AttributedString {
        switch block {
        case .heading(_, let t), .paragraph(let t):
            return t
        case .bulletList(let items):
            return items.reduce(into: AttributedString()) { acc, item in
                if !acc.characters.isEmpty { acc.append(AttributedString("\n")) }
                acc.append(AttributedString("• "))
                acc.append(item)
            }
        case .numberedList(let start, let items):
            var idx = start
            return items.reduce(into: AttributedString()) { acc, item in
                if !acc.characters.isEmpty { acc.append(AttributedString("\n")) }
                acc.append(AttributedString("\(idx). "))
                acc.append(item)
                idx += 1
            }
        case .codeBlock(_, let code):
            return AttributedString(code)
        }
    }
    #endif
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
                            LucideIcon(.check, size: 12)
                                .foregroundStyle(Color(white: 0.78))
                                .transition(.opacity)
                        } else {
                            CopyIconView(color: Color(white: 0.65), lineWidth: 1.55)
                                .frame(width: 16, height: 16)
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
        Haptics.success()
        withAnimation(.easeOut(duration: 0.18)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
        }
    }
}
