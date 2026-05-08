import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("Search")

            // Search field
            HStack(spacing: 8) {
                SearchIcon(size: 13)
                    .foregroundColor(Palette.textTertiary)
                TextField("Search in conversations…", text: $appState.searchQuery)
                    .font(BodyFont.system(size: 14, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onChange(of: appState.searchQuery) { _, q in
                        appState.performSearch(q)
                    }
                    .accessibilityLabel("Search field")
                if !appState.searchQuery.isEmpty {
                    Button {
                        appState.searchQuery = ""
                        appState.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(fieldFocused ? Color(white: 0.35) : Palette.border, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 24)
            .onAppear { fieldFocused = true }

            Spacer().frame(height: 14)

            if !appState.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(appState.searchResults, id: \.self) { result in
                            SearchResultRow(text: result)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .thinScrollers()
            } else if appState.searchQuery.isEmpty {
                emptyState(String(localized: "Type to search your conversations", bundle: AppLocale.bundle, locale: AppLocale.current),
                           icon: "magnifyingglass")
            } else {
                emptyState(L10n.noSearchResults(query: appState.searchQuery), icon: "questionmark.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct SearchResultRow: View {
    let text: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            FileChipIcon(size: 13)
                .foregroundColor(Palette.textTertiary)
            Text(text)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? Palette.cardHover : Palette.cardFill)
        )
        .onHover { hovered = $0 }
        .accessibilityLabel(text)
    }

}

// MARK: - Shared helpers used by panel views

func pageHeader(_ title: LocalizedStringKey) -> some View {
    Text(title)
        .font(BodyFont.system(size: 20, weight: .semibold))
        .foregroundColor(Palette.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
}

/// String-based variant for cases where the title is computed at runtime.
func pageHeaderString(_ title: String) -> some View {
    Text(title)
        .font(BodyFont.system(size: 20, weight: .semibold))
        .foregroundColor(Palette.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
}

func emptyState(_ message: String, icon: String) -> some View {
    VStack(spacing: 10) {
        Spacer()
        Group {
            if icon == "magnifyingglass" {
                SearchIcon(size: 28)
            } else {
                Image(systemName: icon)
                    .font(BodyFont.system(size: 28))
            }
        }
        .foregroundColor(Palette.textTertiary)
        Text(message)
            .font(BodyFont.system(size: 13, wght: 500))
            .foregroundColor(Palette.textTertiary)
            .multilineTextAlignment(.center)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(40)
}
