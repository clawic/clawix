import SwiftUI

/// Single landing screen for the Design surface on iOS. Hosts a
/// segmented control across Styles / Templates / References plus a
/// `NavigationLink` into the editor for each saved EditorDocument.
struct DesignHubView: View {
    var onOpenEditor: (String) -> Void

    @ObservedObject private var design: DesignStore = .shared
    @ObservedObject private var editor: EditorStore = .shared
    @State private var tab: Tab = .styles

    enum Tab: String, CaseIterable, Identifiable {
        case styles, templates, references, documents
        var id: String { rawValue }
        var label: String {
            switch self {
            case .styles: return "Styles"
            case .templates: return "Templates"
            case .references: return "References"
            case .documents: return "Drafts"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Divider().opacity(0.18)
            ZStack {
                ScrollView {
                    Group {
                        switch tab {
                        case .styles:     stylesPane
                        case .templates:  templatesPane
                        case .references: referencesPane
                        case .documents:  draftsPane
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                }
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Palette.background, Palette.background.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                    .allowsHitTesting(false)
                    Spacer()
                    LinearGradient(
                        colors: [Palette.background.opacity(0), Palette.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 56)
                    .allowsHitTesting(false)
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Design")
                .font(BodyFont.system(size: 30, wght: 700))
                .foregroundColor(Palette.textPrimary)
            Text("Styles, templates and references shared with the desktop.")
                .font(BodyFont.system(size: 14, wght: 400))
                .foregroundColor(Color(white: 0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var tabStrip: some View {
        // Horizontal carousel of glass chips. Items have their own
        // leading/trailing padding so the strip dies at the screen
        // edge instead of clipping on a container inset.
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, entry in
                        let count = countFor(entry)
                        Button {
                            Haptics.selection()
                            withAnimation(.easeOut(duration: 0.18)) { tab = entry }
                        } label: {
                            HStack(spacing: 6) {
                                Text(entry.label)
                                    .font(BodyFont.system(size: 13.5, wght: 600))
                                Text("\(count)")
                                    .font(BodyFont.system(size: 11.5, wght: 600))
                                    .foregroundColor(Color(white: 0.50))
                            }
                            .foregroundColor(tab == entry ? Palette.textPrimary : Color(white: 0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassCapsule()
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(tab == entry ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, index == 0 ? 18 : 0)
                        .padding(.trailing, index == Tab.allCases.count - 1 ? 18 : 0)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func countFor(_ tab: Tab) -> Int {
        switch tab {
        case .styles: return design.styles.count
        case .templates: return design.templates.count
        case .references: return design.references.count
        case .documents: return editor.documents.count
        }
    }

    // MARK: - Panes

    private var stylesPane: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14, alignment: .top)], spacing: 14) {
            ForEach(design.styles) { style in
                NavigationLink(value: DesignNavValue.styleDetail(id: style.id)) {
                    StyleSummaryCard(style: style)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var templatesPane: some View {
        let groups = design.templatesByCategory()
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(groups, id: \.0) { category, list in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(category.displayName) · \(list.count)")
                        .font(BodyFont.system(size: 13, wght: 700))
                        .foregroundColor(Color(white: 0.65))
                        .tracking(0.3)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(list) { template in
                            NavigationLink(value: DesignNavValue.templateDetail(id: template.id)) {
                                TemplateSummaryCard(template: template, previewStyle: previewStyle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var referencesPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if design.references.isEmpty {
                emptyState(
                    icon: "books.vertical",
                    title: "No references yet",
                    detail: "Add inspiration on macOS or open this hub on the desktop. Drag-and-drop ingestion on iOS lands with the next release."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(design.references) { ref in
                        ReferenceSummaryCard(reference: ref)
                    }
                }
            }
        }
    }

    private var draftsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editor.documents.isEmpty {
                emptyState(
                    icon: "wand.and.rays",
                    title: "No drafts yet",
                    detail: "Open any template and tap \"Open in editor\" to start one."
                )
            } else {
                ForEach(editor.documents) { document in
                    Button {
                        Haptics.tap()
                        onOpenEditor(document.id)
                    } label: {
                        DraftRow(document: document, design: design)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func previewStyle() -> StyleManifest {
        design.style(id: "claw") ?? design.styles.first ?? DesignBuiltins.styles()[0]
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.45))
            Text(title)
                .font(BodyFont.system(size: 15, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(detail)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

/// Navigation values consumed by the parent NavigationStack. The hub
/// pushes these via NavigationLink; the parent matches on them.
enum DesignNavValue: Hashable {
    case styleDetail(id: String)
    case templateDetail(id: String)
}

// MARK: - Card primitives

struct StyleSummaryCard: View {
    let style: StyleManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(style.tokens.color.allNamed.prefix(7), id: \.0) { _, hex in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(style.name)
                        .font(BodyFont.system(size: 15, wght: 600))
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
                        .font(BodyFont.system(size: 12, wght: 400))
                        .foregroundColor(Color(white: 0.60))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }
}

struct TemplateSummaryCard: View {
    let template: TemplateManifest
    let previewStyle: StyleManifest

    var body: some View {
        let bg = Color(hex: previewStyle.tokens.color.bg) ?? Palette.cardFill
        let fg = Color(hex: previewStyle.tokens.color.fg) ?? Palette.textPrimary
        let accent = Color(hex: previewStyle.tokens.color.accent) ?? Palette.unreadDot
        let ratio = template.aspect.size.width / template.aspect.size.height
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bg)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent.opacity(0.95))
                        .frame(width: 32, height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fg.opacity(0.85))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fg.opacity(0.55))
                        .frame(width: 70, height: 4)
                    Spacer()
                }
                .padding(10)
            }
            .aspectRatio(CGFloat(ratio), contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            Text(template.name)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
            Text(template.aspect.displayLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }
}

struct ReferenceSummaryCard: View {
    let reference: ReferenceManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Color(white: 0.65))
            }
            .frame(height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(reference.name)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text(reference.type.displayName)
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Color(white: 0.55))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }

    private var icon: String {
        switch reference.type {
        case .web:        return "globe"
        case .pdf:        return "doc.richtext"
        case .image:      return "photo"
        case .video:      return "play.rectangle"
        case .screenshot: return "camera.viewfinder"
        case .snippet:    return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct DraftRow: View {
    let document: EditorDocument
    let design: DesignStore

    var body: some View {
        let style = design.style(id: document.styleId) ?? design.styles.first
        let template = design.template(id: document.templateId)
        return HStack(spacing: 12) {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.unreadDot)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.unreadDot.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if let template = template {
                    Text("\(template.name) · \(style?.name ?? document.styleId)")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color(white: 0.60))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.50))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Hex color init

extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard let value = UInt64(raw, radix: 16) else { return nil }
        let r: Double; let g: Double; let b: Double; var a: Double = 1.0
        switch raw.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
