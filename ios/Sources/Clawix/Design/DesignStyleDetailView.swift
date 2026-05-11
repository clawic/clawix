import SwiftUI

/// iOS Style detail (read-only). Mirrors the macOS tab layout but
/// drops inline editing — the canonical editing flow stays on the
/// desktop in Phase 5. iPad surfaces tokens / brand / voice / imagery
/// so the user can review what is applied when generating.
struct DesignStyleDetailView: View {
    let styleId: String

    @ObservedObject private var design: DesignStore = .shared
    @State private var tab: Tab = .tokens

    enum Tab: String, CaseIterable, Identifiable {
        case tokens, brand, voice, imagery, references, examples
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tokens: return "Tokens"
            case .brand: return "Brand"
            case .voice: return "Voice"
            case .imagery: return "Imagery"
            case .references: return "References"
            case .examples: return "Examples"
            }
        }
    }

    var body: some View {
        if let style = design.style(id: styleId) {
            VStack(spacing: 0) {
                header(style)
                tabStrip
                Divider().opacity(0.18)
                ScrollView {
                    Group {
                        switch tab {
                        case .tokens:     tokensTab(style)
                        case .brand:      brandTab(style)
                        case .voice:      voiceTab(style)
                        case .imagery:    imageryTab(style)
                        case .references: referencesTab(style)
                        case .examples:   examplesTab(style)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        } else {
            notFound
        }
    }

    private func header(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(style.name)
                    .font(BodyFont.system(size: 26, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                if style.builtin == true {
                    Text("BUILTIN")
                        .font(BodyFont.system(size: 9, wght: 700))
                        .foregroundColor(Color(white: 0.55))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                Spacer()
            }
            if let desc = style.description {
                Text(desc)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { entry in
                    Button {
                        tab = entry
                    } label: {
                        Text(entry.label)
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(tab == entry ? Palette.textPrimary : Color(white: 0.65))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(tab == entry ? Color.white.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Tabs

    private func tokensTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 10)], spacing: 10) {
                    ForEach(style.tokens.color.allNamed, id: \.0) { name, hex in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                            Text(name)
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            Text(hex.uppercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }
                }
            }
            section("Typography") {
                VStack(alignment: .leading, spacing: 10) {
                    typeRow("Display", stack: style.tokens.typography.display, size: 26)
                    typeRow("Body", stack: style.tokens.typography.body, size: 14)
                    typeRow("Mono", stack: style.tokens.typography.mono, size: 12)
                }
            }
        }
    }

    private func brandTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let taglines = style.brand?.taglines, !taglines.isEmpty {
                section("Taglines") {
                    ForEach(taglines, id: \.self) { line in
                        Text(line)
                            .font(BodyFont.system(size: 14, wght: 400))
                            .foregroundColor(Color(white: 0.85))
                    }
                }
            }
            if let claims = style.brand?.claims, !claims.isEmpty {
                section("Claims") {
                    ForEach(claims, id: \.self) { line in
                        Text(line)
                            .font(BodyFont.system(size: 14, wght: 400))
                            .foregroundColor(Color(white: 0.85))
                    }
                }
            }
            if let naming = style.brand?.naming, !naming.isEmpty {
                section("Naming") {
                    multilineBlock(naming)
                }
            }
            if let glossary = style.brand?.glossary, !glossary.isEmpty {
                section("Glossary") {
                    multilineBlock(glossary)
                }
            }
            if (style.brand?.taglines ?? []).isEmpty && (style.brand?.claims ?? []).isEmpty {
                emptyHint("No brand metadata yet for this style.")
            }
        }
    }

    private func voiceTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let voice = style.brand?.voice, !voice.isEmpty {
                section("Voice") { multilineBlock(voice) }
            } else {
                emptyHint("No voice rules captured for this style.")
            }
            if let dd = style.brand?.doDont, !dd.isEmpty {
                section("Do / Don't") { multilineBlock(dd) }
            }
        }
    }

    private func imageryTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let img = style.imagery
            if img == nil {
                emptyHint("No imagery rules captured for this style.")
            }
            if let p = img?.photography, !p.isEmpty { section("Photography") { multilineBlock(p) } }
            if let i = img?.illustration, !i.isEmpty { section("Illustration") { multilineBlock(i) } }
            if let ic = img?.iconography, !ic.isEmpty { section("Iconography") { multilineBlock(ic) } }
            if let s = img?.generationPromptSuffix, !s.isEmpty { section("Prompt suffix") { multilineBlock(s, mono: true) } }
            if let n = img?.negativePrompt, !n.isEmpty { section("Negative prompt") { multilineBlock(n, mono: true) } }
        }
    }

    private func referencesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let refs = (style.references ?? []).compactMap { design.reference(id: $0) }
            if refs.isEmpty {
                emptyHint("No references linked to this style yet.")
            } else {
                ForEach(refs) { ref in
                    HStack(spacing: 10) {
                        Image(systemName: refIcon(ref.type))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.75))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.name)
                                .font(BodyFont.system(size: 13, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            if let source = ref.source {
                                Text(source)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(white: 0.55))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(ref.type.displayName)
                            .font(BodyFont.system(size: 10, wght: 600))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Palette.border, lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    private func examplesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let examples = style.examples ?? []
            if examples.isEmpty {
                emptyHint("No generated examples yet.")
            } else {
                ForEach(examples, id: \.self) { id in
                    Text(id)
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Color(white: 0.70))
                }
            }
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            content()
        }
    }

    private func typeRow(_ label: String, stack: StyleTypographyStack, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased())
                    .font(BodyFont.system(size: 10, wght: 700))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Text(stack.family)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }
            Text("The quick brown fox")
                .font(.custom(firstFamily(stack.family), size: size))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func multilineBlock(_ body: String, mono: Bool = false) -> some View {
        Text(body)
            .font(mono ? .system(size: 12, design: .monospaced) : BodyFont.system(size: 13.5, wght: 400))
            .foregroundColor(Color(white: 0.85))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.border, lineWidth: 0.5)
                    )
            )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 13, wght: 400))
            .foregroundColor(Color(white: 0.55))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func refIcon(_ type: ReferenceType) -> String {
        switch type {
        case .web:        return "globe"
        case .pdf:        return "doc.richtext"
        case .image:      return "photo"
        case .video:      return "play.rectangle"
        case .screenshot: return "camera.viewfinder"
        case .snippet:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }

    private var notFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(Color(white: 0.45))
            Text("Style not found")
                .font(BodyFont.system(size: 14, wght: 500))
                .foregroundColor(Color(white: 0.70))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }
}
