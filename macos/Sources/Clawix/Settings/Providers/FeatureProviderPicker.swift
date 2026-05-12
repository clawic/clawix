import AIProviders
import SwiftUI

/// Reusable dropdown that features (Enhancement, STT cloud, etc.)
/// embed to let the user pick which `(provider, account, model)` to
/// route through. Filters the catalog by `capability` and lists only
/// enabled providers/accounts.
struct FeatureProviderPicker: View {
    let featureId: FeatureRouting.FeatureID
    let capability: Capability

    @StateObject private var store = AIAccountStoreObservable.shared
    @State private var isOpen = false
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let resolved = FeatureRouting.resolve(
            feature: featureId,
            capability: capability,
            store: AIAccountSecretsStore.shared
        )
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                if let resolved {
                    ProviderBrandIcon(
                        brand: ProviderCatalog.definition(for: resolved.account.providerId)?.brand
                            ?? ProviderBrand(monogram: "?", colorHex: "#888"),
                        size: 18
                    )
                    Text(label(for: resolved.account, model: resolved.model))
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("Pick a provider…")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                LucideIcon.auto("chevron-down", size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(white: 0.135))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen) { popoverContent }
    }

    private var popoverContent: some View {
        let groups = pickerGroups()
        return VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                Text("No accounts configured for \(capability.rawValue).")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
            }
            ForEach(groups, id: \.providerId) { group in
                Text(group.displayName)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ForEach(group.entries, id: \.id) { entry in
                    Button {
                        FeatureRouting.setSelection(
                            feature: featureId,
                            accountId: entry.account.id,
                            modelId: entry.model.id
                        )
                        isOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.account.label) · \(entry.model.displayName)")
                                    .font(BodyFont.system(size: 12.5))
                                    .foregroundColor(Palette.textPrimary)
                                Text(entry.model.id)
                                    .font(BodyFont.system(size: 10.5, wght: 500).monospaced())
                                    .foregroundColor(Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().padding(.vertical, 4)
            Button {
                isOpen = false
                appState.settingsCategory = .modelProviders
            } label: {
                HStack(spacing: 6) {
                    LucideIcon.auto("settings", size: 11)
                    Text("Manage providers…")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 280, idealWidth: 320)
    }

    private struct Group {
        let providerId: ProviderID
        let displayName: String
        let entries: [Entry]
    }

    private struct Entry {
        let id: String
        let account: ProviderAccount
        let model: ModelDefinition
    }

    private func pickerGroups() -> [Group] {
        ProviderCatalog.all.compactMap { definition -> Group? in
            guard FeatureRouting.isProviderEnabled(definition.id) else { return nil }
            let accounts = store.accounts(for: definition.id).filter { $0.isEnabled }
            guard !accounts.isEmpty else { return nil }
            let models = definition.models.filter { $0.capabilities.contains(capability) }
            guard !models.isEmpty else { return nil }
            var entries: [Entry] = []
            for account in accounts {
                for model in models {
                    entries.append(Entry(
                        id: "\(account.id.uuidString)-\(model.id)",
                        account: account,
                        model: model
                    ))
                }
            }
            return Group(providerId: definition.id, displayName: definition.displayName, entries: entries)
        }
    }

    private func label(for account: ProviderAccount, model: ModelDefinition) -> String {
        let provider = ProviderCatalog.definition(for: account.providerId)?.displayName ?? account.providerId.rawValue
        return "\(provider) · \(account.label) · \(model.displayName)"
    }
}
