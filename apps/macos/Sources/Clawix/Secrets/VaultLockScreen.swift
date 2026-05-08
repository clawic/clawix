import SwiftUI

struct VaultLockScreen: View {
    @EnvironmentObject private var vault: VaultManager
    @State private var password: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false
    @State private var showRecovery: Bool = false
    @State private var shakeCount: CGFloat = 0
    @State private var recoveryHovered: Bool = false

    private let columnWidth: CGFloat = 380

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                SecretsIcon(size: 44, lineWidth: 1.6, color: Palette.textPrimary, isLocked: true)
                    .padding(.bottom, 22)

                Text("Vault locked")
                    .font(BodyFont.system(size: 20, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.bottom, 6)

                Text("Enter your master password to unlock the secrets vault.")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: columnWidth)
                    .padding(.bottom, 24)

                SecureField("Master password", text: $password, onCommit: unlock)
                    .sheetTextFieldStyle()
                    .frame(width: columnWidth)
                    .modifier(ShakeEffect(animatableData: shakeCount))
                    .padding(.bottom, 12)

                if let error {
                    InfoBanner(text: error, kind: .error)
                        .frame(width: columnWidth)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                Button(action: unlock) {
                    HStack(spacing: 8) {
                        if isWorking || vault.state == .unlocking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(.black)
                        }
                        Text(vault.state == .unlocking ? "Unlocking…" : "Unlock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SheetPrimaryButtonStyle(enabled: !password.isEmpty && !isWorking && vault.state != .unlocking))
                .frame(width: columnWidth)
                .disabled(password.isEmpty || isWorking || vault.state == .unlocking)
                .padding(.bottom, 14)

                Button {
                    showRecovery = true
                } label: {
                    Text("Use recovery phrase")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(recoveryHovered ? Palette.textPrimary : Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .onHover { recoveryHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: recoveryHovered)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showRecovery) {
            RecoveryPhraseSheet(isPresented: $showRecovery)
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) { error = nil }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await vault.unlock(masterPassword: password)
                password = ""
            } catch {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.error = "Wrong password. Try again, or use the recovery phrase."
                }
                withAnimation(.linear(duration: 0.32)) {
                    shakeCount += 1
                }
            }
        }
    }
}

/// Horizontal sinusoidal shake driven by an animatable CGFloat counter.
/// Bumping `shakeCount` by 1 produces a single 3-oscillation shake.
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 6
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
