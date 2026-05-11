import SwiftUI

/// Detail view for one Template. Shows a rendered preview using the
/// currently chosen style plus the list of slots, variants and supported
/// output formats. Read-only in Phase 2.
struct TemplateDetailView: View {
    let templateId: String
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var selectedStyleId: String = "claw"
    @State private var selectedVariantId: String? = nil

    private var template: TemplateManifest? { store.template(id: templateId) }

    var body: some View {
        if let template {
            VStack(alignment: .leading, spacing: 0) {
                header(template)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 14)
                Divider().opacity(0.18)
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        previewColumn(template)
                            .frame(minWidth: 360, maxWidth: 540)
                        detailColumn(template)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollers()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.background)
            .onAppear {
                selectedVariantId = template.variants.first?.id
                if store.style(id: selectedStyleId) == nil {
                    selectedStyleId = store.styles.first?.id ?? "claw"
                }
            }
        } else {
            notFound
        }
    }

    private func header(_ template: TemplateManifest) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                appState.currentRoute = .designTemplatesHome
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Templates")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                }
                .foregroundColor(Color(white: 0.60))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(BodyFont.system(size: 24, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(template.description ?? "")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.65))
                HStack(spacing: 8) {
                    metaPill(template.category.displayName, icon: "rectangle.grid.2x2")
                    metaPill(template.aspect.displayLabel, icon: "aspectratio")
                    metaPill("\(template.slots.count) slots", icon: "square.dashed")
                    metaPill("\(template.variants.count) variants", icon: "square.stack")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(BodyFont.system(size: 11, wght: 500))
        }
        .foregroundColor(Color(white: 0.65))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func previewColumn(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Preview")
            stylePicker
            TemplatePreviewCard(template: template,
                                style: store.style(id: selectedStyleId) ?? store.styles.first ?? fallbackStyle(),
                                variantId: selectedVariantId)
            if template.variants.count > 1 {
                variantPicker(template)
            }
        }
    }

    private func detailColumn(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            slotsBlock(template)
            outputsBlock(template)
            tagsBlock(template)
        }
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.styles) { style in
                    Button {
                        selectedStyleId = style.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: style.tokens.color.accent) ?? Palette.pastelBlue)
                                .frame(width: 10, height: 10)
                            Text(style.name)
                                .font(BodyFont.system(size: 12, wght: 500))
                                .foregroundColor(selectedStyleId == style.id ? Palette.textPrimary : Color(white: 0.65))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedStyleId == style.id ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func variantPicker(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Variant")
            HStack(spacing: 8) {
                ForEach(template.variants) { variant in
                    Button {
                        selectedVariantId = variant.id
                    } label: {
                        Text(variant.label)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(selectedVariantId == variant.id ? Palette.textPrimary : Color(white: 0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selectedVariantId == variant.id ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func slotsBlock(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Slots")
            VStack(spacing: 8) {
                ForEach(template.slots) { slot in
                    HStack(spacing: 10) {
                        Image(systemName: slotIcon(slot.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(white: 0.75))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(slot.label)
                                    .font(BodyFont.system(size: 13, wght: 500))
                                    .foregroundColor(Palette.textPrimary)
                                if slot.required == true {
                                    Text("REQUIRED")
                                        .font(BodyFont.system(size: 8.5, wght: 700))
                                        .foregroundColor(Palette.pastelBlue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(Palette.pastelBlue.opacity(0.18))
                                        )
                                }
                            }
                            HStack(spacing: 6) {
                                Text(slot.id)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(white: 0.55))
                                Text("·")
                                    .foregroundColor(Color(white: 0.40))
                                Text(slot.kind.rawValue)
                                    .font(BodyFont.system(size: 11, wght: 500))
                                    .foregroundColor(Color(white: 0.55))
                                if let maxLength = slot.maxLength {
                                    Text("·")
                                        .foregroundColor(Color(white: 0.40))
                                    Text("max \(maxLength) chars")
                                        .font(BodyFont.system(size: 11, wght: 500))
                                        .foregroundColor(Color(white: 0.55))
                                }
                                if let maxItems = slot.maxItems {
                                    Text("·")
                                        .foregroundColor(Color(white: 0.40))
                                    Text("max \(maxItems) items")
                                        .font(BodyFont.system(size: 11, wght: 500))
                                        .foregroundColor(Color(white: 0.55))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.cardFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.border, lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    private func outputsBlock(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Outputs")
            HStack(spacing: 8) {
                ForEach(template.outputs, id: \.self) { format in
                    HStack(spacing: 4) {
                        Image(systemName: outputIcon(format))
                            .font(.system(size: 11, weight: .semibold))
                        Text(format.uppercased())
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(Color(white: 0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    private func tagsBlock(_ template: TemplateManifest) -> some View {
        Group {
            if let tags = template.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Tags")
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
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 700))
            .foregroundColor(Color(white: 0.60))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func slotIcon(_ kind: TemplateSlotKind) -> String {
        switch kind {
        case .heading:    return "textformat.size.larger"
        case .subheading: return "textformat.size"
        case .body:       return "text.alignleft"
        case .list:       return "list.bullet"
        case .quote:      return "quote.opening"
        case .metric:     return "chart.bar"
        case .image:      return "photo"
        case .logo:       return "sparkles"
        case .button:     return "rectangle.fill"
        case .divider:    return "minus"
        case .shape:      return "circle.dashed"
        case .table:      return "tablecells"
        }
    }

    private func outputIcon(_ format: String) -> String {
        switch format {
        case "html": return "globe"
        case "pdf":  return "doc.richtext"
        case "png":  return "photo"
        case "svg":  return "scribble"
        case "pptx": return "rectangle.on.rectangle"
        default:     return "doc"
        }
    }

    private func fallbackStyle() -> StyleManifest {
        StyleManifest(
            schemaVersion: 1, id: "fallback", name: "fallback",
            tokens: DesignBuiltins.styles().first!.tokens,
            createdAt: "", updatedAt: ""
        )
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("Template not found")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Button("Back to templates") {
                appState.currentRoute = .designTemplatesHome
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

/// Larger version of the mini-preview used inside template cards.
/// Renders a stylised facsimile (color/typography from the style;
/// layout primitives from the template's slots) since the actual
/// renderer lives in ClawJS and is reached for full-fidelity rendering
/// from Phase 4 onward.
private struct TemplatePreviewCard: View {
    let template: TemplateManifest
    let style: StyleManifest
    let variantId: String?

    var body: some View {
        let bg = Color(hex: style.tokens.color.bg) ?? Palette.cardFill
        let fg = Color(hex: style.tokens.color.fg) ?? Palette.textPrimary
        let fgMuted = Color(hex: style.tokens.color.fgMuted ?? style.tokens.color.fg) ?? fg.opacity(0.6)
        let accent = Color(hex: style.tokens.color.accent) ?? Palette.pastelBlue
        let size = template.aspect.size
        let ratio = size.width / size.height
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                bg
                content(template: template, fg: fg, fgMuted: fgMuted, accent: accent)
                    .padding(20)
            }
            .aspectRatio(CGFloat(ratio), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func content(template: TemplateManifest, fg: Color, fgMuted: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = template.slots.first(where: { $0.kind == .heading }) {
                Text(heading.label)
                    .font(.custom(firstFamily(style.tokens.typography.display.family), size: 22))
                    .foregroundColor(fg)
                    .lineLimit(2)
            }
            if let sub = template.slots.first(where: { $0.kind == .subheading }) {
                Text(sub.label)
                    .font(.custom(firstFamily(style.tokens.typography.body.family), size: 13))
                    .foregroundColor(fgMuted)
                    .lineLimit(2)
            }
            ForEach(template.slots.filter { [.body, .list, .quote].contains($0.kind) }.prefix(2), id: \.id) { slot in
                if slot.kind == .list {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<min(3, slot.maxItems ?? 3), id: \.self) { _ in
                            HStack(spacing: 6) {
                                Circle().fill(accent).frame(width: 4, height: 4)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(fg.opacity(0.65))
                                    .frame(height: 5)
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fg.opacity(slot.kind == .quote ? 0.85 : 0.55))
                        .frame(height: slot.kind == .quote ? 10 : 5)
                }
            }
            if let button = template.slots.first(where: { $0.kind == .button }) {
                Text(button.label)
                    .font(.custom(firstFamily(style.tokens.typography.body.family), size: 11))
                    .foregroundColor(Color(hex: style.tokens.color.bg) ?? .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accent)
                    )
            }
            Spacer()
        }
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }
}
