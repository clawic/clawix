import SwiftUI

/// Detail view for one Style. Tabs across Tokens / Brand / Voice /
/// Imagery / Overrides / References / Examples. Read-only in Phase 2;
/// editing arrives in Phase 3.
struct StyleDetailView: View {
    let styleId: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var selectedTab: Tab = .tokens

    enum Tab: String, CaseIterable, Identifiable {
        case tokens, brand, voice, imagery, overrides, references, examples
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tokens:     return "Tokens"
            case .brand:      return "Brand"
            case .voice:      return "Voice"
            case .imagery:    return "Imagery"
            case .overrides:  return "Overrides"
            case .references: return "References"
            case .examples:   return "Examples"
            }
        }
    }

    private var style: StyleManifest? { store.style(id: styleId) }

    var body: some View {
        if let style {
            VStack(alignment: .leading, spacing: 0) {
                header(style)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                tabBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
                Divider().opacity(0.18)
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .tokens:     tokensTab(style)
                        case .brand:      brandTab(style)
                        case .voice:      voiceTab(style)
                        case .imagery:    imageryTab(style)
                        case .overrides:  overridesTab(style)
                        case .references: referencesTab(style)
                        case .examples:   examplesTab(style)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollers()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.background)
        } else {
            notFound
        }
    }

    private func header(_ style: StyleManifest) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                appState.currentRoute = .designStylesHome
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Styles")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                }
                .foregroundColor(Color(white: 0.60))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(style.name)
                        .font(BodyFont.system(size: 26, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    if style.builtin == true {
                        Text("BUILTIN")
                            .font(BodyFont.system(size: 9, wght: 700))
                            .foregroundColor(Color(white: 0.50))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                }
                if let desc = style.description {
                    Text(desc)
                        .font(BodyFont.system(size: 13, wght: 400))
                        .foregroundColor(Color(white: 0.65))
                }
                if let tags = style.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(BodyFont.system(size: 11, wght: 500))
                                .foregroundColor(Color(white: 0.65))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.label)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(tab == selectedTab ? Palette.textPrimary : Color(white: 0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tab == selectedTab ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Tabs

    private func tokensTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionTitle("Color")
            colorGrid(style.tokens.color)
            sectionTitle("Typography")
            typographyBlock(style.tokens.typography)
            sectionTitle("Spacing")
            spacingBlock(style.tokens.spacing)
            sectionTitle("Radius")
            radiusBlock(style.tokens.radius)
            sectionTitle("Shadow")
            shadowBlock(style.tokens.shadow)
            sectionTitle("Motion")
            motionBlock(style.tokens.motion)
        }
    }

    private func brandTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let brand = style.brand {
                if let taglines = brand.taglines, !taglines.isEmpty {
                    block("Taglines", lines: taglines)
                }
                if let claims = brand.claims, !claims.isEmpty {
                    block("Claims", lines: claims)
                }
                if let naming = brand.naming, !naming.isEmpty {
                    multiline("Naming guide", body: naming)
                }
                if let glossary = brand.glossary, !glossary.isEmpty {
                    multiline("Glossary", body: glossary)
                }
                if brand.taglines == nil && brand.claims == nil && brand.naming == nil && brand.glossary == nil {
                    emptyHint("No brand metadata yet for this style.")
                }
            } else {
                emptyHint("No brand metadata yet for this style.")
            }
        }
    }

    private func voiceTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let voice = style.brand?.voice, !voice.isEmpty {
                multiline("Voice", body: voice)
            } else {
                emptyHint("No voice rules captured for this style.")
            }
            if let dd = style.brand?.doDont, !dd.isEmpty {
                multiline("Do / Don't", body: dd)
            }
        }
    }

    private func imageryTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            guard let imagery = style.imagery else {
                return AnyView(emptyHint("No imagery rules captured for this style."))
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    if let p = imagery.photography, !p.isEmpty { multiline("Photography", body: p) }
                    if let i = imagery.illustration, !i.isEmpty { multiline("Illustration", body: i) }
                    if let ic = imagery.iconography, !ic.isEmpty { multiline("Iconography", body: ic) }
                    if let s = imagery.generationPromptSuffix, !s.isEmpty {
                        multiline("Generation prompt suffix", body: s, mono: true)
                    }
                    if let n = imagery.negativePrompt, !n.isEmpty {
                        multiline("Negative prompt", body: n, mono: true)
                    }
                }
            )
        }
    }

    private func overridesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let overrides = style.overrides, !overrides.isEmpty {
                ForEach(overrides.keys.sorted(), id: \.self) { format in
                    if let entries = overrides[format] {
                        sectionTitle(format.capitalized)
                        keyValueGrid(entries.map { ($0.key, $0.value) })
                    }
                }
            } else {
                emptyHint("No format-specific overrides set for this style.")
            }
        }
    }

    private func referencesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let refs = (style.references ?? []).compactMap { store.reference(id: $0) }
            if refs.isEmpty {
                emptyHint("No references linked to this style yet.")
            } else {
                ForEach(refs) { ref in
                    referenceRow(ref)
                }
            }
        }
    }

    private func examplesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let examples = style.examples ?? []
            if examples.isEmpty {
                emptyHint("No generated examples yet. Apply the style to a template to populate this list.")
            } else {
                ForEach(examples, id: \.self) { id in
                    Text(id)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Color(white: 0.70))
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 700))
            .foregroundColor(Color(white: 0.60))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func colorGrid(_ color: StyleColorTokens) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)], spacing: 12) {
            ForEach(color.allNamed, id: \.0) { name, hex in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: hex) ?? Color.gray)
                        .frame(height: 52)
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

    private func typographyBlock(_ typography: StyleTypographyTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            typographySample(label: "Display", stack: typography.display, size: 28)
            typographySample(label: "Body",    stack: typography.body,    size: 15)
            typographySample(label: "Mono",    stack: typography.mono,    size: 13)
            HStack(spacing: 10) {
                scaleChip("xs", typography.scale.xs)
                scaleChip("sm", typography.scale.sm)
                scaleChip("md", typography.scale.md)
                scaleChip("lg", typography.scale.lg)
                scaleChip("xl", typography.scale.xl)
                scaleChip("2xl", typography.scale.xl2)
                scaleChip("3xl", typography.scale.xl3)
            }
        }
    }

    private func typographySample(label: String, stack: StyleTypographyStack, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 60, alignment: .leading)
            Text("The quick brown fox")
                .font(.custom(firstFamily(stack.family), size: size))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Text(stack.family)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
                .lineLimit(1)
        }
    }

    private func scaleChip(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 9, wght: 700))
                .foregroundColor(Color(white: 0.55))
            Text("\(Int(value))")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func spacingBlock(_ spacing: StyleSpacingTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Base unit · \(Int(spacing.unit))px")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.70))
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(spacing.scale.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }), id: \.key) { key, value in
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 18, height: CGFloat(min(value, 80)))
                        Text(key)
                            .font(BodyFont.system(size: 10, wght: 500))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
            }
        }
    }

    private func radiusBlock(_ radius: StyleRadiusTokens) -> some View {
        HStack(alignment: .center, spacing: 18) {
            radiusSample("none", radius.none)
            radiusSample("sm",   radius.sm)
            radiusSample("md",   radius.md)
            radiusSample("lg",   radius.lg)
            radiusSample("xl",   radius.xl)
            if let sq = radius.squircle { radiusSample("squircle", sq) }
        }
    }

    private func radiusSample(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: CGFloat(value), style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 52, height: 52)
            Text(label)
                .font(BodyFont.system(size: 10, wght: 500))
                .foregroundColor(Color(white: 0.55))
        }
    }

    private func shadowBlock(_ shadow: StyleShadowTokens) -> some View {
        HStack(spacing: 22) {
            shadowSample("sm", shadow.sm)
            shadowSample("md", shadow.md)
            shadowSample("lg", shadow.lg)
        }
    }

    private func shadowSample(_ label: String, _ token: StyleShadowToken) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 60, height: 60)
                .shadow(color: Color(hex: token.color) ?? .black.opacity(0.2),
                        radius: CGFloat(token.blur / 2),
                        x: CGFloat(token.offsetX),
                        y: CGFloat(token.offsetY))
            Text(label)
                .font(BodyFont.system(size: 10, wght: 500))
                .foregroundColor(Color(white: 0.55))
        }
    }

    private func motionBlock(_ motion: StyleMotionTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            keyValueGrid(motion.curves.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }, label: "Curves")
            keyValueGrid(motion.durations.sorted(by: { ($0.value) < ($1.value) }).map { ($0.key, "\(Int($0.value))ms") }, label: "Durations")
        }
    }

    private func keyValueGrid(_ pairs: [(String, String)], label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label.uppercased())
                    .font(BodyFont.system(size: 10, wght: 700))
                    .foregroundColor(Color(white: 0.55))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 6)], alignment: .leading, spacing: 4) {
                ForEach(pairs, id: \.0) { k, v in
                    HStack(spacing: 8) {
                        Text(k)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Color(white: 0.85))
                            .frame(width: 110, alignment: .leading)
                        Text(v)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func block(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.85))
            }
        }
    }

    private func multiline(_ title: String, body: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            Text(body)
                .font(mono ? .system(size: 12, design: .monospaced) : BodyFont.system(size: 13.5, wght: 400))
                .foregroundColor(Color(white: 0.85))
                .lineSpacing(3)
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
    }

    private func referenceRow(_ ref: ReferenceManifest) -> some View {
        HStack(spacing: 10) {
            Image(systemName: referenceIcon(ref.type))
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

    private func referenceIcon(_ type: ReferenceType) -> String {
        switch type {
        case .web:        return "globe"
        case .pdf:        return "doc.richtext"
        case .image:      return "photo"
        case .video:      return "play.rectangle"
        case .screenshot: return "camera.viewfinder"
        case .snippet:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 13, wght: 400))
            .foregroundColor(Color(white: 0.55))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("Style not found")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Button("Back to styles") {
                appState.currentRoute = .designStylesHome
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }
}
