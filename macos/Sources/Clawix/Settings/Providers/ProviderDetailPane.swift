import AIProviders
import SwiftUI

/// Right-hand-side pane shown when the user has selected one provider
/// from the list. Hosts the master toggle, the accounts section, and
/// the catalog of models.
struct ProviderDetailPane: View {
    let provider: ProviderDefinition
    let onBack: () -> Void

    @StateObject private var store = AIAccountStoreObservable.shared
    @State private var addAPIKeyPresented = false
    @State private var oauthPresented: OAuthFlavorBox?
    @State private var devicePresented: DeviceCodeFlavorBox?
    @State private var editingAccount: ProviderAccount?

    @AppStorage private var providerEnabled: Bool

    init(provider: ProviderDefinition, onBack: @escaping () -> Void) {
        self.provider = provider
        self.onBack = onBack
        self._providerEnabled = AppStorage(
            wrappedValue: true,
            FeatureRouting.providerEnabledKey(provider.id)
        )
    }

    private var accounts: [ProviderAccount] {
        store.accounts(for: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbHeader
            providerHeader
            mainToggle
            AccountListSection(
                provider: provider,
                accounts: accounts,
                onAddAPIKey: { addAPIKeyPresented = true },
                onSignIn: { oauthPresented = OAuthFlavorBox(flavor: $0) },
                onSignInDeviceCode: { devicePresented = DeviceCodeFlavorBox(flavor: $0) },
                onEdit: { editingAccount = $0 }
            )
            .padding(.top, 8)
            ProviderModelsSection(provider: provider)
                .padding(.top, 12)
            if let notes = provider.notes {
                InfoBanner(text: notes, kind: .ok)
                    .padding(.top, 16)
            }
        }
        .sheet(isPresented: $addAPIKeyPresented) {
            AddAccountSheet(provider: provider) { _ in
                store.refresh()
            }
        }
        .sheet(item: $oauthPresented) { box in
            OAuthSignInSheet(provider: provider, flavor: box.flavor)
        }
        .sheet(item: $devicePresented) { box in
            DeviceCodeSignInSheet(provider: provider, flavor: box.flavor)
        }
        .sheet(item: $editingAccount) { account in
            EditAccountSheet(account: account, provider: provider)
        }
    }

    private var breadcrumbHeader: some View {
        Button(action: onBack) {
            HStack(spacing: 6) {
                LucideIcon.auto("chevron-left", size: 11)
                Text("Model Providers")
                    .font(BodyFont.system(size: 12, wght: 500))
            }
            .foregroundColor(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    private var providerHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderBrandIcon(brand: provider.brand, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(provider.tagline)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
                Link("Documentation", destination: provider.docsURL)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.bottom, 22)
    }

    private var mainToggle: some View {
        SettingsCard {
            ToggleRow(
                title: "Enable provider",
                detail: "When off, this provider is hidden from feature dropdowns even if accounts are configured.",
                isOn: $providerEnabled
            )
        }
        .padding(.bottom, 8)
    }
}

// SwiftUI `.sheet(item:)` needs `Identifiable`. We'd add the
// conformance to the AIProviders types directly, but the compiler
// rightly warns about retroactive conformance on imported types
// (it'd silently break if the package later adopts Identifiable).
// Wrapping in tiny local IdBox structs avoids the warning.
private struct OAuthFlavorBox: Identifiable, Equatable {
    let flavor: OAuthFlavor
    var id: String { flavor.rawValue }
}
private struct DeviceCodeFlavorBox: Identifiable, Equatable {
    let flavor: DeviceCodeFlavor
    var id: String { flavor.rawValue }
}
