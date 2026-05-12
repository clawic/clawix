import SwiftUI

struct SecretsOnboardingView: View {
    @EnvironmentObject private var vault: VaultManager

    enum Step: Equatable {
        case password
        case showPhrase(phrase: [String])
        case verifyPhrase(phrase: [String])
        case done
    }

    @State private var step: Step = .password
    @State private var password: String = ""
    @State private var passwordConfirm: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false

    var body: some View {
        VaultUI.centered(480) {
            VStack(spacing: 16) {
                switch step {
                case .password:
                    passwordStep
                case .showPhrase(let phrase):
                    showPhraseStep(phrase)
                case .verifyPhrase(let phrase):
                    verifyPhraseStep(phrase)
                case .done:
                    doneStep
                }
            }
        }
    }

    // MARK: Step 1 - master password

    @ViewBuilder
    private var passwordStep: some View {
        SecretsIcon(size: 36, lineWidth: 1.5, color: Palette.textPrimary, isLocked: true)
        VStack(spacing: 4) {
            Text("Set up your Secrets")
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Choose a master password. It protects everything in Secrets. Clawix never stores it; if you forget it, you'll need the recovery phrase you'll see in the next step.")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }

        VaultCard {
            VStack(spacing: 12) {
                VaultPasswordField(placeholder: "Master password", text: $password)
                VaultPasswordField(placeholder: "Confirm master password", text: $passwordConfirm)
                if let error {
                    VaultErrorLine(text: error)
                }
                strengthIndicator
                VaultPrimaryButton(
                    title: "Continue",
                    isLoading: isWorking,
                    isEnabled: canSubmitPassword
                ) {
                    submitPassword()
                }
            }
        }
    }

    private var strengthIndicator: some View {
        let level = passwordStrength(password)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(i < level.score ? level.color : Color.white.opacity(0.06))
                        .frame(height: 3)
                }
            }
            Text(level.label)
                .font(BodyFont.system(size: 10.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    private var canSubmitPassword: Bool {
        password.count >= 8
            && password == passwordConfirm
            && passwordStrength(password).score >= 2
    }

    private func submitPassword() {
        guard canSubmitPassword else {
            error = "Password is too weak or doesn't match the confirmation."
            return
        }
        error = nil
        isWorking = true
        Task {
            do {
                let phrase = try await vault.setUp(masterPassword: password)
                isWorking = false
                step = .showPhrase(phrase: phrase)
            } catch {
                isWorking = false
                self.error = "Could not set up Secrets: \(error)"
            }
        }
    }

    // MARK: Step 2 - show recovery phrase

    @ViewBuilder
    private func showPhraseStep(_ phrase: [String]) -> some View {
        VStack(spacing: 4) {
            Text("Save your recovery phrase")
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Write down these 24 words in order and keep them somewhere safe. They are the only way to recover Secrets if you forget your master password. Clawix will not show them again.")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }

        VaultCard {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(Array(phrase.enumerated()), id: \.offset) { idx, word in
                        recoveryWordCell(index: idx + 1, word: word)
                    }
                }
                Divider().background(Color.white.opacity(0.05))
                HStack(spacing: 10) {
                    VaultSecondaryButton(title: "Copy to clipboard") {
                        copyPhrase(phrase)
                    }
                    VaultPrimaryButton(title: "I've written it down") {
                        step = .verifyPhrase(phrase: phrase)
                    }
                }
            }
        }
    }

    private func recoveryWordCell(index: Int, word: String) -> some View {
        HStack(spacing: 6) {
            Text("\(index).")
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

    private func copyPhrase(_ phrase: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(phrase.joined(separator: " "), forType: .string)
    }

    // MARK: Step 3 - verify a few words

    @ViewBuilder
    private func verifyPhraseStep(_ phrase: [String]) -> some View {
        VerifyPhrasePanel(
            phrase: phrase,
            onSuccess: { step = .done },
            onBack: { step = .showPhrase(phrase: phrase) }
        )
    }

    // MARK: Step 4 - done

    @ViewBuilder
    private var doneStep: some View {
        SecretsIcon(size: 36, lineWidth: 1.5, color: Color.green.opacity(0.85), isLocked: false)
        VStack(spacing: 4) {
            Text("Secrets ready")
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Your Secrets is set up and unlocked. Codex can now use clawix-secrets-proxy to read placeholders without ever seeing the literal value.")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Strength heuristic

private struct StrengthLevel {
    let score: Int
    let label: String
    let color: Color
}

private func passwordStrength(_ password: String) -> StrengthLevel {
    if password.isEmpty { return StrengthLevel(score: 0, label: " ", color: .gray) }
    var score = 0
    if password.count >= 8 { score += 1 }
    if password.count >= 14 { score += 1 }
    let categories: [(CharacterSet) -> Bool] = [
        { set in password.unicodeScalars.contains(where: set.contains) }
    ]
    let lower = CharacterSet.lowercaseLetters
    let upper = CharacterSet.uppercaseLetters
    let digit = CharacterSet.decimalDigits
    let symbol = CharacterSet.punctuationCharacters
        .union(.symbols)
    var classes = 0
    if categories[0](lower) { classes += 1 }
    if categories[0](upper) { classes += 1 }
    if categories[0](digit) { classes += 1 }
    if categories[0](symbol) { classes += 1 }
    if classes >= 2 { score += 1 }
    if classes >= 3 { score += 1 }
    score = min(score, 4)
    let labels = ["Very weak", "Weak", "OK", "Strong", "Very strong"]
    let colors: [Color] = [
        .red.opacity(0.7),
        .orange.opacity(0.8),
        .yellow.opacity(0.8),
        .green.opacity(0.7),
        .green.opacity(0.85)
    ]
    return StrengthLevel(score: score, label: labels[score], color: colors[score])
}

// MARK: - Verify phrase panel

private struct VerifyPhrasePanel: View {
    let phrase: [String]
    let onSuccess: () -> Void
    let onBack: () -> Void

    @State private var indices: [Int] = []
    @State private var inputs: [String] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 4) {
            Text("Confirm your recovery phrase")
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Type the words at these positions to confirm you wrote them down correctly.")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }

        VaultCard {
            VStack(spacing: 12) {
                ForEach(Array(indices.enumerated()), id: \.offset) { rowIndex, wordIndex in
                    HStack(spacing: 10) {
                        Text("Word #\(wordIndex + 1)")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .frame(width: 78, alignment: .leading)
                        TextField("", text: Binding(
                            get: { inputs[safe: rowIndex] ?? "" },
                            set: { newValue in
                                while inputs.count <= rowIndex { inputs.append("") }
                                inputs[rowIndex] = newValue
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                    }
                }
                if let error { VaultErrorLine(text: error) }
                HStack(spacing: 10) {
                    VaultSecondaryButton(title: "Back to phrase", action: onBack)
                    VaultPrimaryButton(title: "Confirm and finish", isEnabled: canSubmit) {
                        verify()
                    }
                }
            }
        }
        .onAppear { primeIndices() }
    }

    private var canSubmit: Bool {
        inputs.count == indices.count && inputs.allSatisfy { !$0.isEmpty }
    }

    private func primeIndices() {
        guard indices.isEmpty else { return }
        var pool = Array(0..<phrase.count)
        var picks: [Int] = []
        for _ in 0..<6 {
            guard !pool.isEmpty else { break }
            let i = Int.random(in: 0..<pool.count)
            picks.append(pool.remove(at: i))
        }
        indices = picks.sorted()
        inputs = Array(repeating: "", count: indices.count)
    }

    private func verify() {
        for (rowIndex, wordIndex) in indices.enumerated() {
            let typed = (inputs[safe: rowIndex] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if typed != phrase[wordIndex] {
                error = "Word #\(wordIndex + 1) doesn't match what we showed you. Go back and double-check."
                return
            }
        }
        error = nil
        onSuccess()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
