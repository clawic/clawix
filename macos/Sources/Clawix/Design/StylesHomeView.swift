import SwiftUI

/// "Styles" landing screen. Grid of moodboard cards (palette swatches +
/// typography preview + brand voice excerpt). Click a card to open the
/// detail view in the center pane.
struct StylesHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var query: String = ""

    private var filteredStyles: [StyleManifest] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return store.styles }
        return store.styles.filter { style in
            let haystack = "\(style.name) \(style.description ?? "") \((style.tags ?? []).joined(separator: " "))".lowercased()
            return haystack.contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 14)
            Divider().opacity(0.18)
            ScrollView {
                if filteredStyles.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 18, alignment: .top)
                    ], spacing: 18) {
                        ForEach(filteredStyles) { style in
                            StyleCard(style: style) {
                                appState.currentRoute = .designStyleDetail(id: style.id)
                            }
                        }
                    }
                    .padding(32)
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
                Text("Styles")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Saved design recipes. Each style codes color, typography, voice and imagery for reuse across any artifact.")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                TextField("Search styles", text: $query)
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "paintpalette")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("No styles match")
                .font(BodyFont.system(size: 15, wght: 500))
                .foregroundColor(Color(white: 0.70))
            Text("Try a different search term, or remove the filter.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.50))
        }
    }
}

private struct StyleCard: View {
    let style: StyleManifest
    let onOpen: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                paletteStrip
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(style.name)
                            .font(BodyFont.system(size: 15, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                        if style.builtin == true {
                            Text("BUILTIN")
                                .font(BodyFont.system(size: 9, wght: 700))
                                .foregroundColor(Color(white: 0.45))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        Spacer(minLength: 0)
                    }
                    if let desc = style.description {
                        Text(desc)
                            .font(BodyFont.system(size: 12, wght: 400))
                            .foregroundColor(Color(white: 0.60))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                typographyPreview
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovered ? Palette.cardHover : Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var paletteStrip: some View {
        let colors = style.tokens.color.allNamed
        return HStack(spacing: 4) {
            ForEach(colors.prefix(7), id: \.0) { name, hex in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: hex) ?? Color.gray)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .help("\(name) · \(hex)")
            }
        }
    }

    private var typographyPreview: some View {
        let display = style.tokens.typography.display.family
        let body = style.tokens.typography.body.family
        return VStack(alignment: .leading, spacing: 2) {
            Text("Aa")
                .font(.custom(firstFamily(display), size: 22))
                .foregroundColor(Palette.textPrimary)
            Text("Body sample — a quick brown fox jumps")
                .font(.custom(firstFamily(body), size: 11))
                .foregroundColor(Color(white: 0.55))
                .lineLimit(1)
        }
    }

    private func firstFamily(_ stack: String) -> String {
        let raw = stack.split(separator: ",").first.map { String($0) } ?? stack
        return raw.replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
    }
}
