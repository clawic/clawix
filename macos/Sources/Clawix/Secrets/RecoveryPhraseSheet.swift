import SwiftUI
import SecretsCrypto

struct RecoveryPhraseSheet: View {
    @EnvironmentObject private var vault: SecretsManager
    @Binding var isPresented: Bool

    enum Stage: Equatable {
        case enterPhrase
        case enterNewPassword
        case done(SecretsManager.EmergencyKit)
    }

    @State private var stage: Stage = .enterPhrase
    @State private var phraseText: String = ""
    @State private var newPassword: String = ""
    @State private var newPasswordConfirm: String = ""
    @State private var pendingRecoveryPhrase: [String] = []
    @State private var error: String?
    @State private var isWorking: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .enterPhrase:
                phraseStage
            case .enterNewPassword:
                newPasswordStage
            case .done(let kit):
                doneStage(kit)
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
            Text("Paste the 24 words you wrote down when you set up Secrets. Words can be separated by spaces, line breaks, or commas.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            SecretsCard {
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
                        SecretsErrorLine(text: error)
                    }

                    SecretsPrimaryButton(
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
            Text("Pick a new master password now. The next screen will give you a new Emergency Kit; the old recovery phrase and Secret Key will no longer work.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            SecretsCard {
                VStack(spacing: 12) {
                    SecretsPasswordField(placeholder: "New master password", text: $newPassword)
                    SecretsPasswordField(placeholder: "Confirm new password", text: $newPasswordConfirm)
                    if let error { SecretsErrorLine(text: error) }
                    SecretsPrimaryButton(
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
    private func doneStage(_ kit: SecretsManager.EmergencyKit) -> some View {
        VStack(spacing: 14) {
            HStack {
                SecretsIcon(size: 24, lineWidth: 1.4, color: Color.green.opacity(0.85), isLocked: false)
                Text("Save your new Emergency Kit")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                closeButton
            }
            Text("Write down the Secret Key and 24 recovery words. The previous Emergency Kit no longer works. Clawix will not show this again.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            SecretsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Secret Key")
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                    Text(kit.secretKey)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(kit.recoveryPhrase.enumerated()), id: \.offset) { idx, word in
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
                        SecretsSecondaryButton(title: "Copy to clipboard") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(
                                "Secret Key: \(kit.secretKey)\nRecovery phrase: \(kit.recoveryPhrase.joined(separator: " "))",
                                forType: .string
                            )
                        }
                        SecretsPrimaryButton(title: "Done") {
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
            LucideIcon(.x, size: 11)
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
        pendingRecoveryPhrase = words
        stage = .enterNewPassword
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
                let kit = try await vault.recover(phrase: pendingRecoveryPhrase, newPassword: newPassword)
                stage = .done(kit)
            } catch {
                self.error = "Could not recover: \(error)"
            }
        }
    }
}
