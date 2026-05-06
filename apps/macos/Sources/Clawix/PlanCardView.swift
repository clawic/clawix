import SwiftUI

// MARK: - Plan content segmentation
//
// Plan mode delivers the final spec as a regular assistant message
// whose body contains a `<proposed_plan>...</proposed_plan>` block (see the
// Plan Mode developer prompt). The app intercepts that block and
// renders it as a Plan card instead of normal markdown. This parser keeps that
// here: an assistant message gets split into "text" and "plan" segments
// before rendering, so prose around the block stays as prose and the
// block itself becomes a `PlanCardView`.
//
// While the assistant is still streaming the plan we may have seen the
// opening tag but not the closing one yet; that streaming state shows
// the shimmer header.

enum PlanSegment: Hashable {
    case text(String)
    case plan(content: String, completed: Bool)
}

enum PlanSegmenter {
    private static let openTag  = "<proposed_plan>"
    private static let closeTag = "</proposed_plan>"

    static func segments(from text: String) -> [PlanSegment] {
        var out: [PlanSegment] = []
        var remaining = Substring(text)

        while let openRange = remaining.range(of: openTag) {
            let before = remaining[..<openRange.lowerBound]
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(.text(String(before)))
            }

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: closeTag) {
                var body = afterOpen[..<closeRange.lowerBound]
                body = trimSurroundingNewlines(body)
                out.append(.plan(content: String(body), completed: true))
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                let body = trimSurroundingNewlines(afterOpen)
                out.append(.plan(content: String(body), completed: false))
                remaining = ""
                break
            }
        }

        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.text(String(remaining)))
        }
        return out
    }

    static func containsPlan(_ text: String) -> Bool {
        text.contains(openTag)
    }

    private static func trimSurroundingNewlines(_ s: Substring) -> Substring {
        var t = s
        while let f = t.first, f == "\n" || f == "\r" { t = t.dropFirst() }
        while let l = t.last, l == "\n" || l == "\r" { t = t.dropLast() }
        return t
    }
}

// MARK: - Plan card view

struct PlanCardView: View {
    let content: String
    let completed: Bool

    /// The card collapses by default once the plan is finished.
    /// While it's still being written it must stay open so the user can
    /// watch the markdown stream in.
    @State private var collapsed: Bool

    @State private var hovered = false
    @State private var copyHovered = false
    @State private var downloadHovered = false
    @State private var chevronHovered = false
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>? = nil

    init(content: String, completed: Bool) {
        self.content = content
        self.completed = completed
        _collapsed = State(initialValue: completed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(maxHeight: collapsed ? 320 : nil)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: completed) { _, isDone in
            // The first time the closing tag arrives, snap to collapsed
            // so the user gets the same tap-to-expand affordance
            // shows.
            if isDone {
                withAnimation(.easeOut(duration: 0.22)) { collapsed = true }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if completed {
                    Text(String(localized: "Plan", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .font(BodyFont.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(white: 0.94))
                } else {
                    ThinkingShimmer(
                        text: String(localized: "Writing plan", bundle: AppLocale.bundle, locale: AppLocale.current),
                        font: BodyFont.system(size: 14, weight: .semibold),
                        baseOpacity: 0.55,
                        peakOpacity: 1.0
                    )
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                if completed {
                    headerIconButton(
                        systemName: justCopied ? "checkmark" : "square.on.square",
                        hovered: $copyHovered,
                        accessibilityLabel: justCopied
                            ? String(localized: "Copied", bundle: AppLocale.bundle, locale: AppLocale.current)
                            : String(localized: "Copy plan", bundle: AppLocale.bundle, locale: AppLocale.current),
                        action: handleCopy
                    )
                    headerIconButton(
                        systemName: "arrow.down.to.line",
                        hovered: $downloadHovered,
                        accessibilityLabel: String(localized: "Download plan", bundle: AppLocale.bundle, locale: AppLocale.current),
                        action: handleDownload
                    )
                }
                headerIconButton(
                    systemName: "chevron.up",
                    hovered: $chevronHovered,
                    accessibilityLabel: collapsed
                        ? String(localized: "Expand", bundle: AppLocale.bundle, locale: AppLocale.current)
                        : String(localized: "Collapse", bundle: AppLocale.bundle, locale: AppLocale.current),
                    rotationDegrees: collapsed ? 180 : 0,
                    action: { withAnimation(.easeOut(duration: 0.20)) { collapsed.toggle() } }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func headerIconButton(
        systemName: String,
        hovered: Binding<Bool>,
        accessibilityLabel: String,
        rotationDegrees: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        let tint = Color(white: hovered.wrappedValue ? 1.0 : 0.62)
        return Button(action: action) {
            Group {
                if systemName == "square.on.square" {
                    CopyIconViewSquircle(color: tint, lineWidth: 1.0)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: systemName)
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hovered.wrappedValue ? 0.07 : 0))
            )
            .rotationEffect(.degrees(rotationDegrees))
            .animation(.easeOut(duration: 0.18), value: rotationDegrees)
        }
        .buttonStyle(.plain)
        .onHover { hovered.wrappedValue = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: body

    @ViewBuilder
    private func body(maxHeight: CGFloat?) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                PlanMarkdown.render(content)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, collapsed ? 80 : 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(!collapsed)
            .frame(maxHeight: maxHeight)

            if collapsed {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(white: 0.085).opacity(0.0), location: 0.0),
                            .init(color: Color(white: 0.085).opacity(0.85), location: 0.55),
                            .init(color: Color(white: 0.085), location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .allowsHitTesting(false)

                    expandPill
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private var expandPill: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) { collapsed = false }
        } label: {
            Text(String(localized: "Expand plan", bundle: AppLocale.bundle, locale: AppLocale.current))
                .font(BodyFont.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.10))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(white: 0.94))
                )
                .shadow(color: Color.black.opacity(0.30), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Expand plan", bundle: AppLocale.bundle, locale: AppLocale.current))
    }

    // MARK: actions

    private func handleCopy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)

        copyResetTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.20)) { justCopied = false }
            }
        }
    }

    private func handleDownload() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PLAN.md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.data(using: .utf8)?.write(to: url)
        }
    }
}

// MARK: - Plan markdown rendering
//
// The plan body uses a small, well-defined markdown subset: H1 title,
// H2 section headings, `- ` bullet items, and paragraphs with inline
// `**bold**`. We render that ourselves so the heading typography matches
// the reference card (large-and-bold title, slightly smaller section
// heads, tight body) without dragging in a full markdown engine.

enum PlanMarkdown {
    fileprivate enum Block {
        case heading1(String)
        case heading2(String)
        case heading3(String)
        case bullet(String)
        case paragraph(String)
    }

    fileprivate static func parse(_ text: String) -> [Block] {
        var out: [Block] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                out.append(.paragraph(trimmed))
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                out.append(.heading1(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                out.append(.heading2(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                out.append(.heading3(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                out.append(.bullet(String(trimmed.dropFirst(2))))
            } else {
                paragraphBuffer.append(trimmed)
            }
        }
        flushParagraph()
        return out
    }

    static func render(_ text: String) -> some View {
        let blocks = parse(text)
        return PlanBlocksView(blocks: blocks)
    }
}

private struct PlanBlocksView: View {
    let blocks: [PlanMarkdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(block, isFirst: idx == 0)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: PlanMarkdown.Block, isFirst: Bool) -> some View {
        switch block {
        case .heading1(let s):
            inlineText(s)
                .font(BodyFont.system(size: 24, weight: .bold))
                .foregroundColor(Color(white: 0.97))
                .padding(.top, isFirst ? 4 : 22)
                .padding(.bottom, 4)
                .fixedSize(horizontal: false, vertical: true)
        case .heading2(let s):
            inlineText(s)
                .font(BodyFont.system(size: 19, weight: .semibold))
                .foregroundColor(Color(white: 0.97))
                .padding(.top, isFirst ? 0 : 18)
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
        case .heading3(let s):
            inlineText(s)
                .font(BodyFont.system(size: 15, weight: .semibold))
                .foregroundColor(Color(white: 0.95))
                .padding(.top, isFirst ? 0 : 14)
                .padding(.bottom, 2)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(BodyFont.system(size: 14))
                    .foregroundColor(Color(white: 0.78))
                inlineText(s)
                    .font(BodyFont.system(size: 14))
                    .foregroundColor(Color(white: 0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .padding(.leading, 4)
        case .paragraph(let s):
            inlineText(s)
                .font(BodyFont.system(size: 14))
                .foregroundColor(Color(white: 0.78))
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Renders a paragraph or heading line with `**bold**` runs as
    /// AttributedString so the bold word stays inline with the
    /// surrounding text instead of breaking onto its own line.
    private func inlineText(_ s: String) -> Text {
        Text(PlanInline.attributed(from: s))
    }
}

enum PlanInline {
    static func attributed(from input: String) -> AttributedString {
        var result = AttributedString()
        var i = input.startIndex
        var run = ""
        var bold = false

        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            if bold {
                piece.font = BodyFont.system(size: 14, weight: .semibold)
                piece.foregroundColor = Color(white: 0.97)
            }
            result.append(piece)
            run.removeAll(keepingCapacity: true)
        }

        while i < input.endIndex {
            if input[i] == "*",
               input.index(after: i) < input.endIndex,
               input[input.index(after: i)] == "*" {
                flush()
                bold.toggle()
                i = input.index(i, offsetBy: 2)
                continue
            }
            if input[i] == "`" {
                let afterTick = input.index(after: i)
                if afterTick < input.endIndex,
                   let close = input[afterTick...].firstIndex(of: "`") {
                    flush()
                    var piece = AttributedString(String(input[afterTick..<close]))
                    piece.font = BodyFont.system(size: 13, design: .monospaced)
                    piece.foregroundColor = Color(white: 0.92)
                    result.append(piece)
                    i = input.index(after: close)
                    continue
                }
            }
            run.append(input[i])
            i = input.index(after: i)
        }
        flush()
        return result
    }
}
