import SwiftUI
import AppKit

/// Block-level markdown renderer used by the right-sidebar file preview.
/// Handles the subset that shows up in real READMEs: ATX headings, body
/// paragraphs with inline `code` / **bold** / [link](url), bullet and
/// numbered lists, and fenced code blocks with the language label + copy
/// affordance shown in the Codex Desktop reference.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case bulletList([AttributedString])
    case numberedList([AttributedString])
    case codeBlock(language: String, code: String)
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
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

            // ATX headings
            if let level = headingLevel(for: trimmed) {
                let body = trimmed.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level,
                                       text: parseInline(body)))
                i += 1
                continue
            }

            // Fenced code block
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

            // Bullet list
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

            // Numbered list ("1. body", "12) body")
            if let _ = numberedRange(in: trimmed) {
                var items: [AttributedString] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let r = numberedRange(in: t) else { break }
                    items.append(parseInline(String(t[r.upperBound...])))
                    i += 1
                }
                blocks.append(.numberedList(items))
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
                    || numberedRange(in: nt) != nil {
                    break
                }
                paragraph.append(next)
                i += 1
            }
            blocks.append(.paragraph(parseInline(paragraph.joined(separator: " "))))
        }
        return blocks
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

    private static func numberedRange(in trimmed: String) -> Range<String.Index>? {
        trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression)
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

/// Renders an array of `MarkdownBlock`s with the visual rules used by the
/// Codex Desktop file preview (large headings, body 14pt with generous
/// line spacing, inline `code` chips, fenced code blocks with a header
/// row showing the language and a copy button).
struct MarkdownDocumentView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(block, isFirst: idx == 0)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .foregroundColor(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isFirst ? 0 : headingTopPadding(level))
                .padding(.bottom, headingBottomPadding(level))

        case .paragraph(let attr):
            Text(styledInline(attr))
                .font(.system(size: 14))
                .foregroundColor(Palette.textPrimary.opacity(0.92))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                            .font(.system(size: 14))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 8, alignment: .leading)
                        Text(styledInline(item))
                            .font(.system(size: 14))
                            .foregroundColor(Palette.textPrimary.opacity(0.92))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(idx + 1).")
                            .font(.system(size: 14))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 20, alignment: .leading)
                        Text(styledInline(item))
                            .font(.system(size: 14))
                            .foregroundColor(Palette.textPrimary.opacity(0.92))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
                .padding(.bottom, 14)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 26, weight: .bold)
        case 2:  return .system(size: 20, weight: .bold)
        case 3:  return .system(size: 16, weight: .semibold)
        default: return .system(size: 14, weight: .semibold)
        }
    }

    private func headingTopPadding(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 18
        case 2:  return 14
        case 3:  return 10
        default: return 8
        }
    }

    private func headingBottomPadding(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 10
        case 2:  return 8
        case 3:  return 6
        default: return 4
        }
    }

    /// Walk the inline run table and tint inline `code` runs with a chip
    /// background. `AttributedString.runs` exposes Apple-defined intent
    /// metadata under `presentationIntent`, including a `.code` indicator.
    private func styledInline(_ source: AttributedString) -> AttributedString {
        var out = source
        for run in out.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                out[run.range].font = .system(size: 12.5, design: .monospaced)
                out[run.range].backgroundColor = Color(white: 0.18)
                out[run.range].foregroundColor = Color(white: 0.92)
            }
        }
        return out
    }
}

private struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false
    @State private var hoverCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Color(white: 0.55))
                Spacer(minLength: 8)
                Button(action: copyCode) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(white: hoverCopy ? 0.85 : 0.55))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .onHover { hoverCopy = $0 }
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(Palette.textPrimary.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .textSelection(.enabled)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func copyCode() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }
}
