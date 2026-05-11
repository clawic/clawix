import SwiftUI

/// "Templates" landing screen. Grid of preview cards grouped by
/// category (Presentations, Cards, Posters, Social, etc.). Click a card
/// to open the template detail view in the center pane.
struct TemplatesHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var query: String = ""
    @State private var selectedCategory: TemplateCategory? = nil

    private var visibleCategories: [(TemplateCategory, [TemplateManifest])] {
        let groups = store.templatesByCategory()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return groups.compactMap { (category, list) -> (TemplateCategory, [TemplateManifest])? in
            if let selectedCategory, selectedCategory != category { return nil }
            let filtered = trimmed.isEmpty
                ? list
                : list.filter {
                    let haystack = "\($0.name) \($0.description ?? "") \(($0.tags ?? []).joined(separator: " "))".lowercased()
                    return haystack.contains(trimmed)
                }
            return filtered.isEmpty ? nil : (category, filtered)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 12)
            categoryStrip
                .padding(.horizontal, 32)
                .padding(.bottom, 14)
            Divider().opacity(0.18)
            ScrollView {
                if visibleCategories.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(visibleCategories, id: \.0) { category, list in
                            categorySection(category: category, list: list)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Templates")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Parametrised pieces by category. Render any template with any style to get the finished artifact.")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                TextField("Search templates", text: $query)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.94))
                    .frame(width: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", active: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(TemplateCategory.allCases) { category in
                    let count = store.templates.filter { $0.category == category }.count
                    if count > 0 {
                        categoryChip(label: "\(category.displayName) (\(count))", active: selectedCategory == category) {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        }
                    }
                }
            }
        }
    }

    private func categoryChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(active ? Palette.textPrimary : Color(white: 0.65))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                )
        }
        .buttonStyle(.plain)
    }

    private func categorySection(category: TemplateCategory, list: [TemplateManifest]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(category.displayName)
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(list.count)")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Color(white: 0.50))
            }
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14, alignment: .top)
            ], spacing: 14) {
                ForEach(list) { template in
                    TemplateCard(template: template,
                                 previewStyle: previewStyle()) {
                        appState.currentRoute = .designTemplateDetail(id: template.id)
                    }
                }
            }
        }
    }

    private func previewStyle() -> StyleManifest {
        store.style(id: "claw") ?? store.style(id: "studio") ?? store.styles.first ?? StyleManifest(
            schemaVersion: 1, id: "fallback", name: "fallback",
            tokens: DesignBuiltins.styles().first!.tokens,
            createdAt: "", updatedAt: ""
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("No templates match")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Text("Try a different search or clear the category filter.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.50))
        }
    }
}

private struct TemplateCard: View {
    let template: TemplateManifest
    let previewStyle: StyleManifest
    let onOpen: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                miniPreview
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(template.aspect.displayLabel)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                        Text("·")
                            .foregroundColor(Color(white: 0.40))
                        Text("\(template.slots.count) slots")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered ? Palette.cardHover : Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var miniPreview: some View {
        let bg = Color(hex: previewStyle.tokens.color.bg) ?? Palette.cardFill
        let fg = Color(hex: previewStyle.tokens.color.fg) ?? Palette.textPrimary
        let accent = Color(hex: previewStyle.tokens.color.accent) ?? Palette.pastelBlue
        let aspectSize = template.aspect.size
        let ratio = aspectSize.width / aspectSize.height
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bg)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent.opacity(0.95))
                    .frame(width: 36, height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fg.opacity(0.85))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fg.opacity(0.55))
                    .frame(width: 80, height: 4)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fg.opacity(0.35))
                            .frame(height: 4)
                    }
                }
            }
            .padding(10)
        }
        .aspectRatio(CGFloat(ratio), contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
