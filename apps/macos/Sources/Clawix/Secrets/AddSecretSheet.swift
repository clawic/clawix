import SwiftUI
import SecretsModels
import SecretsVault

/// Minimum-viable form for v1: pick a vault, name, title, kind, and one
/// primary value (token / password / note). Multi-field editor with field
/// types and brand presets ships in step 9 of the plan.
struct AddSecretSheet: View {
    @EnvironmentObject private var vault: VaultManager
    @Binding var isPresented: Bool
    var onCreated: (EntityID) -> Void

    @State private var selectedVaultId: EntityID?
    @State private var kind: SecretKind = .apiKey
    @State private var internalName: String = ""
    @State private var title: String = ""
    @State private var primaryValue: String = ""
    @State private var primaryFieldName: String = "token"
    @State private var notes: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false
    @State private var primaryRevealed: Bool = false

    private let kindOptions: [SecretKind] = [
        .apiKey, .passwordLogin, .oauthToken, .secureNote, .databaseUrl, .webhookSecret
    ]

    private var vaultDropdownOptions: [(EntityID?, String)] {
        vault.vaults.map { (Optional<EntityID>.some($0.id), $0.name) }
    }

    private var kindDropdownOptions: [(SecretKind, String)] {
        kindOptions.map { ($0, $0.rawValue.replacingOccurrences(of: "_", with: " ")) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 14) {
                whereCard
                identityCard
                valueCard
            }

            footer
                .padding(.top, 14)
        }
        .frame(width: 520)
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .sheetStandardBackground(cornerRadius: 18)
        .onAppear {
            if selectedVaultId == nil {
                selectedVaultId = vault.vaults.first?.id
            }
            if primaryFieldName.isEmpty {
                primaryFieldName = defaultFieldName(for: kind)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("New secret")
                .font(BodyFont.system(size: 18, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            IconCircleButton(symbol: "xmark") {
                isPresented = false
            }
        }
    }

    // MARK: - Cards

    private var whereCard: some View {
        SettingsCard {
            SettingsRow {
                RowLabel(title: "Vault", detail: nil)
            } trailing: {
                SettingsDropdown(
                    options: vaultDropdownOptions,
                    selection: $selectedVaultId,
                    minWidth: 180
                )
            }
            CardDivider()
            SettingsRow {
                RowLabel(title: "Type", detail: nil)
            } trailing: {
                SettingsDropdown(
                    options: kindDropdownOptions,
                    selection: $kind,
                    minWidth: 180
                )
            }
            .onChange(of: kind) { _, newKind in
                withAnimation(.easeOut(duration: 0.18)) {
                    primaryFieldName = defaultFieldName(for: newKind)
                }
            }
        }
    }

    private var identityCard: some View {
        SettingsCard {
            stackedFieldRow(label: "Internal name") {
                TextField("e.g. service_main", text: $internalName)
                    .sheetTextFieldStyle()
            }
            CardDivider()
            stackedFieldRow(label: "Title") {
                TextField("Service · main", text: $title)
                    .sheetTextFieldStyle()
            }
        }
    }

    private var valueCard: some View {
        SettingsCard {
            stackedFieldRow(label: primaryFieldLabel) {
                ZStack(alignment: .trailing) {
                    Group {
                        if primaryRevealed {
                            TextField("paste secret value", text: $primaryValue)
                        } else {
                            SecureField("paste secret value", text: $primaryValue)
                        }
                    }
                    .secretFieldStyle()
                    IconCircleButton(symbol: primaryRevealed ? "eye.slash" : "eye") {
                        primaryRevealed.toggle()
                    }
                    .padding(.trailing, 6)
                }
            }
            CardDivider()
            stackedFieldRow(label: "Notes (optional)") {
                TextField("Free-form notes…", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .sheetTextFieldStyle()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            if let error {
                InfoBanner(text: error, kind: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                Spacer(minLength: 0)
            }
            Button("Cancel") { isPresented = false }
                .buttonStyle(SheetCancelButtonStyle())
            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.black)
                    }
                    Text("Create secret")
                }
            }
            .buttonStyle(SheetPrimaryButtonStyle(enabled: canSubmit && !isWorking))
            .disabled(!canSubmit || isWorking)
        }
    }

    // MARK: - Helpers

    private var primaryFieldLabel: String {
        primaryFieldName.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @ViewBuilder
    private func stackedFieldRow<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSubmit: Bool {
        selectedVaultId != nil
            && !internalName.trimmingCharacters(in: .whitespaces).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !primaryValue.isEmpty
    }

    private func defaultFieldName(for kind: SecretKind) -> String {
        switch kind {
        case .apiKey: return "token"
        case .passwordLogin: return "password"
        case .oauthToken: return "access_token"
        case .secureNote: return "content"
        case .databaseUrl: return "password"
        case .webhookSecret: return "hmac_key"
        case .sshIdentity: return "private_key"
        case .envBundle: return "value"
        case .structuredCredentials: return "value"
        case .certificate: return "private_key"
        }
    }

    private func submit() {
        guard let store = vault.store,
              let vaultId = selectedVaultId,
              let chosenVault = vault.vaults.first(where: { $0.id == vaultId })
        else {
            withAnimation(.easeOut(duration: 0.18)) {
                error = "Pick a vault."
            }
            return
        }
        let trimmedName = internalName.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let primaryField = DraftField(
            name: primaryFieldName.isEmpty ? defaultFieldName(for: kind) : primaryFieldName,
            fieldKind: kind == .secureNote ? .note : .password,
            placement: kind == .apiKey ? .header : .none,
            isSecret: true,
            isConcealed: true,
            secretValue: primaryValue,
            sortOrder: 0
        )
        let draft = DraftSecret(
            kind: kind,
            internalName: trimmedName,
            title: trimmedTitle,
            fields: [primaryField],
            notes: notes.isEmpty ? nil : notes
        )
        withAnimation(.easeOut(duration: 0.18)) { error = nil }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let secret = try store.createSecret(in: chosenVault, draft: draft)
                onCreated(secret.id)
                isPresented = false
            } catch {
                let message = String(describing: error)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.error = message
                    }
                }
            }
        }
    }
}

// MARK: - Secret-field style

/// Same shape as `sheetTextFieldStyle` but the hairline stroke gets a
/// faint orange tint so the user immediately reads the field as
/// "this holds a secret value", distinct from the neutral name/title
/// fields above it.
private struct SecretFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 14, wght: 500))
            .foregroundColor(Color(white: 0.96))
            .padding(.leading, 14)
            .padding(.trailing, 38)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 0.6)
                    )
            )
    }
}

private extension View {
    func secretFieldStyle() -> some View {
        modifier(SecretFieldStyle())
    }
}
