import AIProviders
import SwiftUI

/// List of `ProviderAccount` rows for one provider, plus the CTA
/// buttons (Add API key, Sign in with…). Lives inside the detail
/// pane.
struct AccountListSection: View {
    let provider: ProviderDefinition
    let accounts: [ProviderAccount]
    let onAddAPIKey: () -> Void
    let onSignIn: (OAuthFlavor) -> Void
    let onSignInDeviceCode: (DeviceCodeFlavor) -> Void
    let onEdit: (ProviderAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Accounts")
            if accounts.isEmpty {
                SettingsCard {
                    HStack(spacing: 10) {
                        LucideIcon.auto("info", size: 12)
                            .foregroundColor(Palette.textSecondary)
                        Text(emptyMessage)
                            .font(BodyFont.system(size: 12))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(14)
                }
            } else {
                SettingsCard {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { idx, account in
                        if idx > 0 { CardDivider() }
                        AccountRow(
                            account: account,
                            provider: provider,
                            onEdit: { onEdit(account) }
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(provider.authMethods.indices, id: \.self) { idx in
                    button(for: provider.authMethods[idx])
                }
                Spacer()
            }
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private func button(for method: AuthMethod) -> some View {
        switch method {
        case .apiKey:
            primaryButton(icon: "key", title: "Add API key", action: onAddAPIKey)
        case .oauth(let flavor):
            primaryButton(icon: "log-in", title: "Sign in with \(provider.displayName)") {
                onSignIn(flavor)
            }
        case .deviceCode(let flavor):
            primaryButton(icon: "log-in", title: "Sign in with \(provider.displayName)") {
                onSignInDeviceCode(flavor)
            }
        case .none:
            primaryButton(icon: "plus", title: "Add local connection", action: onAddAPIKey)
        }
    }

    private func primaryButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon.auto(icon, size: 11)
                Text(title)
                    .font(BodyFont.system(size: 12, wght: 600))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.16, green: 0.46, blue: 0.98))
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyMessage: String {
        switch provider.authMethods.first {
        case .oauth, .deviceCode:
            return "No accounts yet. Sign in to start using this provider."
        default:
            return "No accounts yet. Add an API key to start using this provider."
        }
    }
}

private struct AccountRow: View {
    let account: ProviderAccount
    let provider: ProviderDefinition
    let onEdit: () -> Void

    @State private var hovered = false
    @StateObject private var store = AIAccountStoreObservable.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.label)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 8)

            PillToggle(isOn: Binding(
                get: { account.isEnabled },
                set: { store.setEnabled(id: account.id, enabled: $0) }
            ))

            Button(action: onEdit) {
                LucideIcon.auto("pencil", size: 11)
                    .foregroundColor(Palette.textSecondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hovered ? Color.white.opacity(0.05) : .clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var detailText: String {
        let auth: String
        switch account.authMethod {
        case .apiKey: auth = "API key"
        case .oauth: auth = account.accountEmail ?? "OAuth"
        case .deviceCode: auth = account.accountEmail ?? "Signed in"
        case .none: auth = "Local"
        }
        if let lastUsed = account.lastUsedAt {
            return "\(auth) · \(relativeDate(lastUsed))"
        }
        return auth
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
