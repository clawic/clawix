import AIProviders
import SwiftUI

/// Sheet for the "Add API key account" flow. The OAuth equivalent is
/// `OAuthSignInSheet`.
struct AddAccountSheet: View {
    let provider: ProviderDefinition
    let onSaved: (ProviderAccount) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIAccountStoreObservable.shared

    @State private var label: String = ""
    @State private var apiKey: String = ""
    @State private var revealed: Bool = false
    @State private var customBaseURL: String = ""
    @State private var saveError: String?

    private var resolvedBaseURL: URL? {
        let trimmed = customBaseURL.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return URL(string: trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProviderBrandIcon(brand: provider.brand, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add account")
                        .font(BodyFont.system(size: 16, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    Text(provider.displayName)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(.bottom, 18)

            SettingsCard {
                labelField
                CardDivider()
                apiKeyField
                if provider.supportsCustomBaseURL {
                    CardDivider()
                    baseURLField
                }
            }

            HStack(spacing: 10) {
                TestConnectionButton(
                    providerId: provider.id,
                    apiKey: apiKey,
                    baseURL: resolvedBaseURL
                )
                Spacer()
                if let docs = provider.docsURL.absoluteString as String? {
                    Link("Get API key", destination: provider.docsURL)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    let _ = docs
                }
            }
            .padding(.top, 14)

            if let saveError {
                InfoBanner(text: saveError, kind: .error)
                    .padding(.top, 12)
            }

            Spacer(minLength: 24)

            HStack(spacing: 8) {
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
                                .fill(saveDisabled ? Color.white.opacity(0.06) : Color(red: 0.16, green: 0.46, blue: 0.98))
                        )
                }
                .buttonStyle(.plain)
                .disabled(saveDisabled)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Palette.background)
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Label")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            TextField("Personal", text: $label)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(14)
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.id == .ollama ? "API key (optional)" : "API key")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                IconCircleButton(symbol: revealed ? "eye-off" : "eye") {
                    revealed.toggle()
                }
            }
            Group {
                if revealed {
                    TextField("sk-...", text: $apiKey)
                } else {
                    SecureField("sk-...", text: $apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 13))
            .foregroundColor(Palette.textPrimary)
        }
        .padding(14)
    }

    private var baseURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Base URL (optional)")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            TextField(provider.defaultBaseURL?.absoluteString ?? "https://example.com/v1", text: $customBaseURL)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(14)
    }

    private var saveDisabled: Bool {
        if provider.id == .ollama || provider.id == .openAICompatibleCustom {
            return false
        }
        return apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        let authMethod: AuthMethod = trimmed.isEmpty ? .none : .apiKey
        let draft = ProviderAccountDraft(
            providerId: provider.id,
            label: label,
            authMethod: authMethod,
            apiKey: trimmed.isEmpty ? nil : trimmed,
            baseURLOverride: resolvedBaseURL
        )
        if let saved = store.create(draft) {
            onSaved(saved)
            dismiss()
        } else {
            saveError = store.lastError ?? "Couldn't save the account."
        }
    }
}
