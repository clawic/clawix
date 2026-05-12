import SwiftUI

/// Home screen for the Life surface. Shown when the user taps the
/// section header in the sidebar (route `.lifeHome`). Renders the 80
/// verticals grouped by category as a grid of cards.
struct LifeHomeScreen: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = LifeManager.shared

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ForEach(LifeCategory.allCases, id: \.self) { category in
                    let entries = LifeRegistry.entries(in: category)
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.leading, 4)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(entries) { entry in
                                    LifeVerticalCard(entry: entry, enabled: manager.enabledVerticalIds.contains(entry.id)) {
                                        appState.navigate(to: .lifeVertical(id: entry.id))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Palette.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thinScrollers()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Life")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Button("Configure") {
                appState.navigate(to: .lifeSettings)
            }
            .buttonStyle(.plain)
            .foregroundColor(Palette.textSecondary)
        }
    }
}

private struct LifeVerticalCard: View {
    let entry: LifeRegistryEntry
    let enabled: Bool
    let onTap: () -> Void

    @State private var hover: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    if entry.healthkitMapping {
                        Text("HK")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                    Spacer()
                    if !enabled {
                        Text("OFF")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.05 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
