import SwiftUI

/// iOS template detail. Big preview + slot list + "Open in editor" CTA
/// that creates an EditorDocument and bubbles the id up so the parent
/// NavigationStack can push the editor.
struct DesignTemplateDetailView: View {
    let templateId: String
    var onOpenEditor: (String) -> Void

    @ObservedObject private var design: DesignStore = .shared
    @State private var selectedStyleId: String = "claw"
    @State private var selectedVariantId: String? = nil
    @State private var creationError: String?

    var body: some View {
        if let template = design.template(id: templateId) {
            VStack(spacing: 0) {
                header(template)
                Divider().opacity(0.18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        stylePicker
                        previewCard(template)
                        if template.variants.count > 1 {
                            variantPicker(template)
                        }
                        slotsBlock(template)
                        outputsBlock(template)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                createCTA(template)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
            .background(Palette.background.ignoresSafeArea())
            .onAppear {
                selectedVariantId = template.variants.first?.id
                if design.style(id: selectedStyleId) == nil {
                    selectedStyleId = design.styles.first?.id ?? "claw"
                }
            }
        } else {
            notFound
        }
    }

    private func header(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name)
                .font(BodyFont.manrope(size: 24, wght: 700))
                .foregroundColor(Palette.textPrimary)
            Text(template.description ?? "")
                .font(BodyFont.manrope(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.65))
            HStack(spacing: 6) {
                metaPill(template.category.displayName, icon: "rectangle.grid.2x2")
                metaPill(template.aspect.displayLabel, icon: "aspectratio")
                metaPill("\(template.slots.count) slots", icon: "square.dashed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func metaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(BodyFont.manrope(size: 11, wght: 500))
        }
        .foregroundColor(Color(white: 0.65))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(design.styles) { style in
                    Button {
                        selectedStyleId = style.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: style.tokens.color.accent) ?? Palette.unreadDot)
                                .frame(width: 10, height: 10)
                            Text(style.name)
                                .font(BodyFont.manrope(size: 12, wght: 500))
                                .foregroundColor(selectedStyleId == style.id ? Palette.textPrimary : Color(white: 0.65))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedStyleId == style.id ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func variantPicker(_ template: TemplateManifest) -> some View {
        HStack(spacing: 6) {
            ForEach(template.variants) { v in
                Button {
                    selectedVariantId = v.id
                } label: {
                    Text(v.label)
                        .font(BodyFont.manrope(size: 12, wght: 500))
                        .foregroundColor(selectedVariantId == v.id ? Palette.textPrimary : Color(white: 0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedVariantId == v.id ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func previewCard(_ template: TemplateManifest) -> some View {
        let style = design.style(id: selectedStyleId) ?? design.styles.first ?? DesignBuiltins.styles()[0]
        let bg = Color(hex: style.tokens.color.bg) ?? Palette.cardFill
        let fg = Color(hex: style.tokens.color.fg) ?? Palette.textPrimary
        let fgMuted = Color(hex: style.tokens.color.fgMuted ?? style.tokens.color.fg) ?? fg.opacity(0.6)
        let accent = Color(hex: style.tokens.color.accent) ?? Palette.unreadDot
        let ratio = template.aspect.size.width / template.aspect.size.height
        return ZStack(alignment: .topLeading) {
            bg
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
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fg.opacity(slot.kind == .quote ? 0.85 : 0.55))
                        .frame(height: slot.kind == .quote ? 10 : 5)
                }
                if let button = template.slots.first(where: { $0.kind == .button }) {
                    Text(button.label)
                        .font(.custom(firstFamily(style.tokens.typography.body.family), size: 11))
                        .foregroundColor(bg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(accent)
                        )
                }
                Spacer()
            }
            .padding(18)
        }
        .aspectRatio(CGFloat(ratio), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private func slotsBlock(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLOTS")
                .font(BodyFont.manrope(size: 11, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            ForEach(template.slots) { slot in
                HStack(spacing: 10) {
                    Image(systemName: slotIcon(slot.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.75))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.label)
                            .font(BodyFont.manrope(size: 13, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("\(slot.id) · \(slot.kind.rawValue)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private func outputsBlock(_ template: TemplateManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUTS")
                .font(BodyFont.manrope(size: 11, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            HStack(spacing: 6) {
                ForEach(template.outputs, id: \.self) { format in
                    Text(format.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
            }
        }
    }

    private func createCTA(_ template: TemplateManifest) -> some View {
        Button {
            Haptics.tap()
            createDocument(for: template)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 14, weight: .semibold))
                Text("Open in editor")
                    .font(BodyFont.manrope(size: 15, wght: 700))
            }
            .foregroundColor(Palette.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.textPrimary)
            )
        }
        .buttonStyle(.plain)
    }

    private func createDocument(for template: TemplateManifest) {
        let styleId = design.style(id: selectedStyleId) != nil ? selectedStyleId : (design.styles.first?.id ?? "claw")
        do {
            let document = try EditorStore.shared.create(
                name: template.name,
                template: template,
                styleId: styleId,
                variantId: selectedVariantId
            )
            onOpenEditor(document.id)
        } catch {
            creationError = error.localizedDescription
        }
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

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }

    private var notFound: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(Color(white: 0.45))
            Text("Template not found")
                .font(BodyFont.manrope(size: 14, wght: 500))
                .foregroundColor(Color(white: 0.70))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
    }
}
