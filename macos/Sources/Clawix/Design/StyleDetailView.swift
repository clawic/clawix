import SwiftUI
import UniformTypeIdentifiers

/// Detail view for one Style. Tabs across Tokens / Brand / Voice /
/// Imagery / Overrides / References / Examples. Builtin styles render
/// read-only with a "Duplicate to edit" banner; user styles render
/// every field inline-editable and auto-persist on commit.
struct StyleDetailView: View {
    let styleId: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var draft: StyleManifest?
    @State private var selectedTab: Tab = .tokens
    @State private var saveError: String?
    @State private var pendingDelete: Bool = false
    @State private var pickerReference: ReferenceManifest?
    @State private var pickerStyleSelection: String = ""

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

    private var isEditable: Bool { (draft?.builtin ?? false) == false }

    var body: some View {
        if let style = currentStyle {
            VStack(alignment: .leading, spacing: 0) {
                header(style)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                if let saveError {
                    saveErrorBanner(saveError)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 10)
                }
                if !isEditable {
                    builtinBanner(style)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }
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
            .onAppear { if draft == nil { draft = store.style(id: styleId) } }
            .onChange(of: styleId) { _, _ in draft = store.style(id: styleId) }
            .onChange(of: store.styles) { _, _ in
                if draft?.id != styleId || store.style(id: styleId) == nil {
                    draft = store.style(id: styleId)
                }
            }
            .alert("Delete \(style.name)?", isPresented: $pendingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    do {
                        try store.deleteStyle(style)
                        appState.currentRoute = .designStylesHome
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            } message: {
                Text("The STYLE.md file and its assets will be removed from disk. This cannot be undone.")
            }
        } else {
            notFound
        }
    }

    private var currentStyle: StyleManifest? {
        draft ?? store.style(id: styleId)
    }

    // MARK: - Header

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
                    if isEditable {
                        TextField("Name", text: bindingForName())
                            .textFieldStyle(.plain)
                            .font(BodyFont.system(size: 26, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                            .frame(maxWidth: 420)
                            .onSubmit { persist() }
                    } else {
                        Text(style.name)
                            .font(BodyFont.system(size: 26, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                    }
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
                if isEditable {
                    TextField("Description", text: bindingForDescription(), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 13, wght: 400))
                        .foregroundColor(Color(white: 0.78))
                        .lineLimit(1...3)
                        .frame(maxWidth: 560)
                        .onSubmit { persist() }
                } else if let desc = style.description {
                    Text(desc)
                        .font(BodyFont.system(size: 13, wght: 400))
                        .foregroundColor(Color(white: 0.65))
                }
                tagsRow(style)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    headerButton("doc.on.doc", "Duplicate", action: duplicate)
                    if isEditable {
                        headerButton("trash", "Delete", role: .destructive, action: { pendingDelete = true })
                    }
                }
            }
        }
    }

    private func headerButton(_ icon: String, _ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(BodyFont.system(size: 12, wght: 500))
            }
            .foregroundColor(role == .destructive ? Color(red: 0.95, green: 0.45, blue: 0.45) : Color(white: 0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func tagsRow(_ style: StyleManifest) -> some View {
        Group {
            if isEditable {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.50))
                    TextField("tag1, tag2, tag3", text: bindingForTags())
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color(white: 0.80))
                        .frame(maxWidth: 360)
                        .onSubmit { persist() }
                }
            } else if let tags = style.tags, !tags.isEmpty {
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
    }

    private func builtinBanner(_ style: StyleManifest) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.pastelBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Builtin style · read-only")
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Duplicate this style to make a custom copy you can edit.")
                    .font(BodyFont.system(size: 12, wght: 400))
                    .foregroundColor(Color(white: 0.60))
            }
            Spacer()
            Button("Duplicate to edit", action: duplicate)
                .buttonStyle(.plain)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.pastelBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.pastelBlue.opacity(0.12))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.pastelBlue.opacity(0.30), lineWidth: 0.5)
                )
        )
    }

    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45))
            Text(message)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                saveError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.30), lineWidth: 0.5)
                )
        )
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
            livePreviewBadge
        }
    }

    private var livePreviewBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.40, green: 0.85, blue: 0.55))
                .frame(width: 6, height: 6)
            Text("Live preview")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Color(white: 0.55))
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tokensTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Color")
                    colorEditor(style)
                    sectionTitle("Typography")
                    typographyEditor(style)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Preview")
                    LivePreviewCard(style: style)
                }
                .frame(width: 260, alignment: .topLeading)
            }
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

    @ViewBuilder
    private func brandTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if isEditable {
                multilineEditor("Taglines (one per line)", bindingForBrandList(\StyleBrand.taglines, default: []))
                multilineEditor("Claims (one per line)",   bindingForBrandList(\StyleBrand.claims,   default: []))
                multilineEditor("Naming guide",            bindingForBrandText(\StyleBrand.naming))
                multilineEditor("Glossary",                bindingForBrandText(\StyleBrand.glossary))
            } else {
                if let taglines = style.brand?.taglines, !taglines.isEmpty {
                    listBlock("Taglines", lines: taglines)
                }
                if let claims = style.brand?.claims, !claims.isEmpty {
                    listBlock("Claims", lines: claims)
                }
                if let naming = style.brand?.naming, !naming.isEmpty {
                    multilineBlock("Naming guide", body: naming)
                }
                if let glossary = style.brand?.glossary, !glossary.isEmpty {
                    multilineBlock("Glossary", body: glossary)
                }
                if (style.brand?.taglines ?? []).isEmpty && (style.brand?.claims ?? []).isEmpty && (style.brand?.naming ?? "").isEmpty && (style.brand?.glossary ?? "").isEmpty {
                    emptyHint("No brand metadata yet for this style.")
                }
            }
        }
    }

    @ViewBuilder
    private func voiceTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if isEditable {
                multilineEditor("Voice", bindingForBrandText(\StyleBrand.voice), minHeight: 160)
                multilineEditor("Do / Don't", bindingForBrandText(\StyleBrand.doDont), minHeight: 160)
            } else {
                if let voice = style.brand?.voice, !voice.isEmpty {
                    multilineBlock("Voice", body: voice)
                } else {
                    emptyHint("No voice rules captured for this style.")
                }
                if let dd = style.brand?.doDont, !dd.isEmpty {
                    multilineBlock("Do / Don't", body: dd)
                }
            }
        }
    }

    @ViewBuilder
    private func imageryTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if isEditable {
                multilineEditor("Photography",                bindingForImageryText(\StyleImagery.photography))
                multilineEditor("Illustration",               bindingForImageryText(\StyleImagery.illustration))
                multilineEditor("Iconography",                bindingForImageryText(\StyleImagery.iconography))
                multilineEditor("Generation prompt suffix",   bindingForImageryText(\StyleImagery.generationPromptSuffix), mono: true)
                multilineEditor("Negative prompt",            bindingForImageryText(\StyleImagery.negativePrompt), mono: true)
            } else {
                let imagery = style.imagery
                if let p = imagery?.photography, !p.isEmpty { multilineBlock("Photography", body: p) }
                if let i = imagery?.illustration, !i.isEmpty { multilineBlock("Illustration", body: i) }
                if let ic = imagery?.iconography, !ic.isEmpty { multilineBlock("Iconography", body: ic) }
                if let s = imagery?.generationPromptSuffix, !s.isEmpty { multilineBlock("Generation prompt suffix", body: s, mono: true) }
                if let n = imagery?.negativePrompt, !n.isEmpty { multilineBlock("Negative prompt", body: n, mono: true) }
                if imagery == nil {
                    emptyHint("No imagery rules captured for this style.")
                }
            }
        }
    }

    @ViewBuilder
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
                emptyHint("No format-specific overrides set for this style. Add per-format settings (web, slides, pdf, doc, social, email, motion) when you need them.")
            }
        }
    }

    @ViewBuilder
    private func referencesTab(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let linkedIds = Set(style.references ?? [])
            let linked = (style.references ?? []).compactMap { store.reference(id: $0) }
            if linked.isEmpty {
                emptyHint("No references linked to this style yet. Add references in the References library, then link them here.")
            } else {
                ForEach(linked) { ref in
                    referenceRow(ref, linked: true) {
                        toggleLink(ref)
                    }
                }
            }
            let available = store.references.filter { !linkedIds.contains($0.id) }
            if !available.isEmpty {
                Divider().opacity(0.18).padding(.vertical, 4)
                Text("AVAILABLE REFERENCES")
                    .font(BodyFont.system(size: 10, wght: 700))
                    .foregroundColor(Color(white: 0.50))
                    .tracking(0.5)
                ForEach(available) { ref in
                    referenceRow(ref, linked: false) {
                        toggleLink(ref)
                    }
                }
            }
        }
    }

    @ViewBuilder
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

    // MARK: - Editors

    private func colorEditor(_ style: StyleManifest) -> some View {
        let pairs = style.tokens.color.allNamed
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 10)], spacing: 10) {
            ForEach(pairs, id: \.0) { name, hex in
                colorRow(name: name, hex: hex)
            }
        }
    }

    private func colorRow(name: String, hex: String) -> some View {
        HStack(spacing: 10) {
            if isEditable {
                ColorPicker("", selection: bindingForColor(name: name, currentHex: hex), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(hex.uppercased())
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func typographyEditor(_ style: StyleManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            typographyRow("Display", binding: bindingForTypography(\StyleTypographyTokens.display), sample: 22)
            typographyRow("Body",    binding: bindingForTypography(\StyleTypographyTokens.body),    sample: 14)
            typographyRow("Mono",    binding: bindingForTypography(\StyleTypographyTokens.mono),    sample: 12)
        }
    }

    private func typographyRow(_ label: String, binding: Binding<StyleTypographyStack>, sample: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 62, alignment: .leading)
            if isEditable {
                TextField("Font stack", text: Binding(
                    get: { binding.wrappedValue.family },
                    set: {
                        var v = binding.wrappedValue
                        v.family = $0
                        binding.wrappedValue = v
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
                .onSubmit { persist() }
            } else {
                Text(binding.wrappedValue.family)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.75))
            }
            Spacer()
            Text("Aa")
                .font(.custom(firstFamily(binding.wrappedValue.family), size: sample))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func multilineEditor(_ label: String, _ binding: Binding<String>, mono: Bool = false, minHeight: CGFloat = 100) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(label)
            TextEditor(text: binding)
                .scrollContentBackground(.hidden)
                .font(mono ? .system(size: 12, design: .monospaced) : BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.88))
                .frame(minHeight: minHeight)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
                .onChange(of: binding.wrappedValue) { _, _ in persist() }
        }
    }

    private func referenceRow(_ ref: ReferenceManifest, linked: Bool, onToggle: @escaping () -> Void) -> some View {
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
            if isEditable {
                Button(linked ? "Unlink" : "Link", action: onToggle)
                    .buttonStyle(.plain)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(linked ? Color(red: 0.95, green: 0.55, blue: 0.55) : Palette.pastelBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(linked ? Color.red.opacity(0.10) : Palette.pastelBlue.opacity(0.12))
                    )
            } else if linked {
                Text("LINKED")
                    .font(BodyFont.system(size: 9, wght: 700))
                    .foregroundColor(Palette.pastelBlue)
            }
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

    // MARK: - Read-only blocks

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 700))
            .foregroundColor(Color(white: 0.60))
            .textCase(.uppercase)
            .tracking(0.5)
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

    private func listBlock(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.85))
            }
        }
    }

    private func multilineBlock(_ title: String, body: String, mono: Bool = false) -> some View {
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

    // MARK: - Mutations + bindings

    private func persist() {
        guard isEditable, let candidate = draft else { return }
        do {
            try store.updateStyle(candidate)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func duplicate() {
        guard let style = currentStyle else { return }
        do {
            let newId = try store.duplicateStyle(style)
            appState.currentRoute = .designStyleDetail(id: newId)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func toggleLink(_ ref: ReferenceManifest) {
        guard let id = draft?.id else { return }
        do {
            try store.toggleReferenceLink(referenceId: ref.id, styleId: id)
            draft = store.style(id: id)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func bindingForName() -> Binding<String> {
        Binding(
            get: { draft?.name ?? "" },
            set: {
                draft?.name = $0
            }
        )
    }

    private func bindingForDescription() -> Binding<String> {
        Binding(
            get: { draft?.description ?? "" },
            set: { draft?.description = $0.isEmpty ? nil : $0 }
        )
    }

    private func bindingForTags() -> Binding<String> {
        Binding(
            get: { (draft?.tags ?? []).joined(separator: ", ") },
            set: {
                let parts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                draft?.tags = parts.isEmpty ? nil : parts
            }
        )
    }

    private func bindingForColor(name: String, currentHex: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: currentHex) ?? .gray },
            set: { newColor in
                let hex = newColor.toHexString()
                writeColor(name: name, hex: hex)
                persist()
            }
        )
    }

    private func writeColor(name: String, hex: String) {
        guard var d = draft else { return }
        var c = d.tokens.color
        switch name {
        case "bg":         c.bg = hex
        case "surface":    c.surface = hex
        case "surface-2":  c.surface2 = hex
        case "fg":         c.fg = hex
        case "fg-muted":   c.fgMuted = hex
        case "accent":     c.accent = hex
        case "accent-2":   c.accent2 = hex
        case "success":    c.success = hex
        case "warn":       c.warn = hex
        case "danger":     c.danger = hex
        case "border":     c.border = hex
        case "overlay":    c.overlay = hex
        default:           c.extras[name] = hex
        }
        d.tokens.color = c
        draft = d
    }

    private func bindingForTypography(_ keyPath: WritableKeyPath<StyleTypographyTokens, StyleTypographyStack>) -> Binding<StyleTypographyStack> {
        Binding(
            get: { draft?.tokens.typography[keyPath: keyPath] ?? StyleTypographyStack(family: "Inter, sans-serif") },
            set: {
                draft?.tokens.typography[keyPath: keyPath] = $0
                persist()
            }
        )
    }

    private func bindingForBrandText(_ keyPath: WritableKeyPath<StyleBrand, String?>) -> Binding<String> {
        Binding(
            get: { draft?.brand?[keyPath: keyPath] ?? "" },
            set: {
                var brand = draft?.brand ?? StyleBrand()
                brand[keyPath: keyPath] = $0.isEmpty ? nil : $0
                draft?.brand = brand
            }
        )
    }

    private func bindingForBrandList(_ keyPath: WritableKeyPath<StyleBrand, [String]?>, default: [String]) -> Binding<String> {
        Binding(
            get: { (draft?.brand?[keyPath: keyPath] ?? []).joined(separator: "\n") },
            set: {
                let parts = $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                var brand = draft?.brand ?? StyleBrand()
                brand[keyPath: keyPath] = parts.isEmpty ? nil : parts
                draft?.brand = brand
            }
        )
    }

    private func bindingForImageryText(_ keyPath: WritableKeyPath<StyleImagery, String?>) -> Binding<String> {
        Binding(
            get: { draft?.imagery?[keyPath: keyPath] ?? "" },
            set: {
                var imagery = draft?.imagery ?? StyleImagery()
                imagery[keyPath: keyPath] = $0.isEmpty ? nil : $0
                draft?.imagery = imagery
            }
        )
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
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
}

// MARK: - Live preview card

/// Stylised facsimile of how the style reads when applied to a small
/// piece. Shows headline + body + button + image placeholder using the
/// style's actual color tokens and font stacks.
struct LivePreviewCard: View {
    let style: StyleManifest

    var body: some View {
        let bg = Color(hex: style.tokens.color.bg) ?? Palette.cardFill
        let fg = Color(hex: style.tokens.color.fg) ?? Palette.textPrimary
        let fgMuted = Color(hex: style.tokens.color.fgMuted ?? style.tokens.color.fg) ?? fg.opacity(0.6)
        let accent = Color(hex: style.tokens.color.accent) ?? Palette.pastelBlue
        let display = style.tokens.typography.display.family
        let body = style.tokens.typography.body.family
        return VStack(alignment: .leading, spacing: 10) {
            Text("Headline that anchors the page")
                .font(.custom(firstFamily(display), size: 17))
                .foregroundColor(fg)
            Text("Supporting line that reads in the body voice. Just enough copy to feel real.")
                .font(.custom(firstFamily(body), size: 11.5))
                .foregroundColor(fgMuted)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text("Primary")
                    .font(.custom(firstFamily(body), size: 11))
                    .foregroundColor(bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent)
                    )
                Text("Secondary")
                    .font(.custom(firstFamily(body), size: 11))
                    .foregroundColor(fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(fg.opacity(0.30), lineWidth: 0.5)
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: style.tokens.color.border ?? style.tokens.color.fg) ?? Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Color hex round-trip

extension Color {
    /// Returns a `#RRGGBB` hex string for the receiver. Drops alpha
    /// because the design tokens use a separate `overlay` field for
    /// translucent colors.
    func toHexString() -> String {
        let ns = NSColor(self)
        guard let srgb = ns.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((srgb.redComponent.clamped01() * 255).rounded())
        let g = Int((srgb.greenComponent.clamped01() * 255).rounded())
        let b = Int((srgb.blueComponent.clamped01() * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private extension CGFloat {
    func clamped01() -> CGFloat { Swift.max(0, Swift.min(1, self)) }
}
