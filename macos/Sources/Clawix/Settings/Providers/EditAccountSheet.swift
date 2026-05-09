import AIProviders
import SwiftUI

/// Sheet for editing an existing account: label rename, base URL
/// override toggle, manual delete. The credential value is not editable
/// inline — to rotate it the user deletes and recreates.
struct EditAccountSheet: View {
    let account: ProviderAccount
    let provider: ProviderDefinition

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIAccountStoreObservable.shared

    @State private var label: String
    @State private var baseURL: String

    init(account: ProviderAccount, provider: ProviderDefinition) {
        self.account = account
        self.provider = provider
        _label = State(initialValue: account.label)
        _baseURL = State(initialValue: account.baseURLOverride?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProviderBrandIcon(brand: provider.brand, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit account")
                        .font(BodyFont.system(size: 16, weight: .semibold))
                    Text(provider.displayName)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(.bottom, 16)

            SettingsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                    TextField("Personal", text: $label)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 13))
                }
                .padding(14)
                if provider.supportsCustomBaseURL {
                    CardDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Base URL")
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                        TextField(provider.defaultBaseURL?.absoluteString ?? "https://example.com/v1",
                                  text: $baseURL)
                            .textFieldStyle(.plain)
                            .font(BodyFont.system(size: 13))
                    }
                    .padding(14)
                }
            }

            Button(role: .destructive, action: deleteAccount) {
                HStack(spacing: 6) {
                    LucideIcon.auto("trash-2", size: 11)
                    Text("Delete account")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Color.red.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            Spacer(minLength: 16)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                Button(action: save) {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.16, green: 0.46, blue: 0.98))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Palette.background)
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if trimmedLabel != account.label && !trimmedLabel.isEmpty {
            store.updateLabel(id: account.id, label: trimmedLabel)
        }
        if provider.supportsCustomBaseURL {
            let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
            let newURL: URL? = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
            if newURL != account.baseURLOverride {
                store.setBaseURL(id: account.id, url: newURL)
            }
        }
        dismiss()
    }

    private func deleteAccount() {
        store.delete(id: account.id)
        dismiss()
    }
}
