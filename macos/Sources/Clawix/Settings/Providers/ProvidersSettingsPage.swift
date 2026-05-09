import AIProviders
import SwiftUI

/// Settings → Model Providers page. Master/detail in-place: when a
/// provider row is tapped, the detail pane replaces the list.
struct ProvidersSettingsPage: View {
    @StateObject private var store = AIAccountStoreObservable.shared
    @State private var query: String = ""
    @State private var filter: Filter = .all
    @State private var selectedProviderId: ProviderID?

    private enum Filter: String, CaseIterable {
        case all
        case configured
        case empty
        case disabled
        var label: String {
            switch self {
            case .all: return "All"
            case .configured: return "Configured"
            case .empty: return "Empty"
            case .disabled: return "Disabled"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selected = selectedProviderId,
               let definition = ProviderCatalog.definition(for: selected) {
                ProviderDetailPane(provider: definition) {
                    selectedProviderId = nil
                }
            } else {
                listContent
            }
        }
        .onAppear { store.refresh() }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Model Providers",
                subtitle: "Connect API keys or sign in to providers your features will use."
            )

            HStack(spacing: 8) {
                searchField
                Spacer(minLength: 8)
            }
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    FilterChip(label: f.label, active: filter == f) { filter = f }
                }
                Spacer()
            }
            .padding(.bottom, 14)

            SettingsCard {
                let visible = filteredProviders
                if visible.isEmpty {
                    HStack {
                        Text(query.isEmpty ? "No providers match." : "No providers match \"\(query)\".")
                            .font(BodyFont.system(size: 12))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(14)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, definition in
                        if idx > 0 { CardDivider() }
                        ProviderListRow(
                            provider: definition,
                            accountCount: store.accounts(for: definition.id).count,
                            isEnabled: FeatureRouting.isProviderEnabled(definition.id),
                            onTap: { selectedProviderId = definition.id }
                        )
                    }
                }
            }

            if let error = store.lastError {
                InfoBanner(text: error, kind: .error)
                    .padding(.top, 12)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            LucideIcon.auto("search", size: 12)
                .foregroundColor(Palette.textSecondary)
            TextField("Search providers", text: $query)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.105))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: 260)
    }

    private var filteredProviders: [ProviderDefinition] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ProviderCatalog.all.filter { definition in
            let count = store.accounts(for: definition.id).count
            let isEnabled = FeatureRouting.isProviderEnabled(definition.id)
            switch filter {
            case .all: break
            case .configured: if count == 0 { return false }
            case .empty: if count != 0 { return false }
            case .disabled: if isEnabled { return false }
            }
            if trimmedQuery.isEmpty { return true }
            return definition.displayName.lowercased().contains(trimmedQuery)
                || definition.id.rawValue.contains(trimmedQuery)
                || definition.tagline.lowercased().contains(trimmedQuery)
        }
    }
}
