import SwiftUI
import SecretsModels
import SecretsVault

/// Modal for creating a new secret. Two-column composition: a left
/// identity rail where the chosen `SecretKindIcon` is the visual hero
/// (the same hand-drawn line-art used in the secrets list, scaled up),
/// and a right column with the editable fields. Type and destination
/// folder live as inline menus under the icon, so the form column never
/// has to spell out "Folder" / "Type" rows: the rail already says it.
struct AddSecretSheet: View {
    @EnvironmentObject private var vault: SecretsManager
    @Binding var isPresented: Bool
    var onCreated: (EntityID) -> Void

    @State private var selectedVaultId: EntityID?
    @State private var kind: SecretKind = .apiKey
    @State private var internalName: String = ""
    @State private var title: String = ""
    @State private var primaryValue: String = ""
    @State private var notes: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false
    @State private var primaryRevealed: Bool = false

    private let kindOptions: [SecretKind] = [
        .apiKey, .passwordLogin, .oauthToken, .databaseUrl, .webhookSecret, .secureNote
    ]

    private var selectedVaultName: String {
        vault.vaults.first(where: { $0.id == selectedVaultId })?.name ?? "—"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 0) {
                identityRail
                    .frame(width: 188)
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                formColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            IconCircleButton(symbol: "xmark") {
                isPresented = false
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
        .frame(width: 620)
        .sheetStandardBackground(cornerRadius: 18)
        .onAppear {
            if selectedVaultId == nil {
                selectedVaultId = vault.vaults.first?.id
            }
        }
    }

    // MARK: - Identity rail (left)

    private var identityRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 18) {
                Spacer().frame(height: 6)

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                        .frame(width: 96, height: 96)
                    SecretKindIcon(
                        kind: kind,
                        size: 50,
                        lineWidth: 1.4,
                        color: Color(white: 0.93)
                    )
                }
                .animation(.easeOut(duration: 0.18), value: kind)

                VStack(spacing: 8) {
                    kindMenu
                    vaultMenu
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    LucideIcon(.key, size: 10)
                        .foregroundColor(Palette.textSecondary)
                    Text("Encrypted on this Mac")
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Text("Only you can decrypt with the master password.")
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Color(white: 0.42))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 22)
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
    }

    private var kindMenu: some View {
        Menu {
            ForEach(kindOptions, id: \.self) { option in
                Button(option.friendlyLabel) {
                    withAnimation(.easeOut(duration: 0.18)) { kind = option }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: kind.friendlyLabel)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                LucideIcon(.chevronDown, size: 9)
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var vaultMenu: some View {
        Menu {
            ForEach(vault.vaults, id: \.id) { v in
                Button(v.name) { selectedVaultId = v.id }
            }
        } label: {
            HStack(spacing: 5) {
                LucideIcon(.folder, size: 10)
                    .foregroundColor(Palette.textSecondary)
                Text(verbatim: selectedVaultName)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                LucideIcon(.chevronDown, size: 8)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Form column (right)

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New secret")
                .font(BodyFont.system(size: 18, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                stackedField(label: "Title") {
                    TextField("Service · main", text: $title)
                        .sheetTextFieldStyle()
                }
                stackedField(label: "Internal name") {
                    TextField("service_main", text: $internalName)
                        .sheetTextFieldStyle()
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                stackedField(label: primaryFieldLabel) {
                    ZStack(alignment: .trailing) {
                        Group {
                            if primaryRevealed {
                                TextField("paste secret value", text: $primaryValue)
                            } else {
                                SecureField("paste secret value", text: $primaryValue)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.96))
                        .padding(.leading, 14)
                        .padding(.trailing, 42)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                                )
                        )
                        IconCircleButton(symbol: primaryRevealed ? "eye.slash" : "eye") {
                            primaryRevealed.toggle()
                        }
                        .padding(.trailing, 5)
                    }
                }
                stackedField(label: "Notes (optional)") {
                    TextField("Free-form notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .sheetTextFieldStyle()
                }
            }

            Spacer(minLength: 22)

            footer
        }
        .padding(.top, 22)
        .padding(.leading, 26)
        .padding(.trailing, 26)
        .padding(.bottom, 22)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
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

    @ViewBuilder
    private func stackedField<Content: View>(
        label: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Color(white: 0.62))
            content()
        }
    }

    private var primaryFieldLabel: String {
        switch kind {
        case .apiKey: return "Token"
        case .passwordLogin: return "Password"
        case .oauthToken: return "Access token"
        case .secureNote: return "Note"
        case .databaseUrl: return "Connection URL"
        case .webhookSecret: return "Signing key"
        case .sshIdentity: return "Private key"
        case .envBundle: return "Value"
        case .structuredCredentials: return "Value"
        case .certificate: return "Private key"
        }
    }

    private var primaryFieldName: String {
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

    private var canSubmit: Bool {
        selectedVaultId != nil
            && !internalName.trimmingCharacters(in: .whitespaces).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !primaryValue.isEmpty
    }

    private func submit() {
        guard let store = vault.store,
              let vaultId = selectedVaultId,
              let chosenVault = vault.vaults.first(where: { $0.id == vaultId })
        else {
            withAnimation(.easeOut(duration: 0.18)) { error = "Pick a folder." }
            return
        }
        let trimmedName = internalName.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let primaryField = DraftField(
            name: primaryFieldName,
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
