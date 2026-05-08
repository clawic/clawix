import SwiftUI
import SecretsCrypto

struct RecoveryPhraseSheet: View {
    @EnvironmentObject private var vault: VaultManager
    @Binding var isPresented: Bool

    enum Stage: Equatable {
        case enterPhrase
        case enterNewPassword
        case done(newPhrase: [String])
    }

    @State private var stage: Stage = .enterPhrase
    @State private var phraseText: String = ""
    @State private var newPassword: String = ""
    @State private var newPasswordConfirm: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .enterPhrase:
                phraseStage
            case .enterNewPassword:
                newPasswordStage
            case .done(let newPhrase):
                doneStage(newPhrase)
            }
        }
        .frame(width: 480)
        .padding(.vertical, 22)
        .padding(.horizontal, 22)
        .background(Color(white: 0.07))
    }

    @ViewBuilder
    private var phraseStage: some View {
        VStack(spacing: 14) {
            HStack {
                SecretsIcon(size: 24, lineWidth: 1.4, color: Palette.textPrimary, isLocked: false)
                Text("Recover with your phrase")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                closeButton
            }
            Text("Paste the 24 words you wrote down when you set up the vault. Words can be separated by spaces, line breaks, or commas.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VaultCard {
                VStack(spacing: 12) {
                    TextEditor(text: $phraseText)
                        .scrollContentBackground(.hidden)
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                        .frame(height: 130)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )

                    if let error {
                        VaultErrorLine(text: error)
                    }

                    VaultPrimaryButton(
                        title: "Recover",
                        isLoading: isWorking,
                        isEnabled: !phraseText.isEmpty
                    ) {
                        recover()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var newPasswordStage: some View {
        VStack(spacing: 14) {
            HStack {
                SecretsIcon(size: 24, lineWidth: 1.4, color: Palette.textPrimary, isLocked: true)
                Text("Choose a new master password")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                closeButton
            }
            Text("Recovery succeeded. Pick a new master password now. The next screen will give you a new recovery phrase; the old one will no longer work.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VaultCard {
                VStack(spacing: 12) {
                    VaultPasswordField(placeholder: "New master password", text: $newPassword)
                    VaultPasswordField(placeholder: "Confirm new password", text: $newPasswordConfirm)
                    if let error { VaultErrorLine(text: error) }
                    VaultPrimaryButton(
                        title: "Save and continue",
                        isLoading: isWorking,
                        isEnabled: newPassword.count >= 8 && newPassword == newPasswordConfirm
                    ) {
                        rotate()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func doneStage(_ newPhrase: [String]) -> some View {
        VStack(spacing: 14) {
            HStack {
                SecretsIcon(size: 24, lineWidth: 1.4, color: Color.green.opacity(0.85), isLocked: false)
                Text("Save your new recovery phrase")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                closeButton
            }
            Text("Write these 24 words down. The previous phrase no longer works. Clawix will not show this again.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VaultCard {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(newPhrase.enumerated()), id: \.offset) { idx, word in
                            HStack(spacing: 6) {
                                Text("\(idx + 1).")
                                    .font(BodyFont.system(size: 11, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                                    .frame(width: 22, alignment: .trailing)
                                Text(word)
                                    .font(BodyFont.system(size: 12.5, wght: 600))
                                    .foregroundColor(Palette.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                    }
                    HStack(spacing: 10) {
                        VaultSecondaryButton(title: "Copy to clipboard") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(newPhrase.joined(separator: " "), forType: .string)
                        }
                        VaultPrimaryButton(title: "Done") {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func recover() {
        let words = RecoveryPhrase.normalize(phraseText)
        guard words.count == RecoveryPhrase.wordCount else {
            error = "Expected \(RecoveryPhrase.wordCount) words, got \(words.count)."
            return
        }
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await vault.recover(phrase: words)
                stage = .enterNewPassword
            } catch {
                self.error = "Could not recover: \(error)"
            }
        }
    }

    private func rotate() {
        guard newPassword == newPasswordConfirm, newPassword.count >= 8 else {
            error = "Passwords don't match or are too short."
            return
        }
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let phrase = try await vault.changePassword(newPassword: newPassword)
                stage = .done(newPhrase: phrase)
            } catch {
                self.error = "Could not change password: \(error)"
            }
        }
    }
}
