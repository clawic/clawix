import SwiftUI

struct VaultLockScreen: View {
    @EnvironmentObject private var vault: VaultManager
    @State private var password: String = ""
    @State private var error: String?
    @State private var isWorking: Bool = false
    @State private var showRecovery: Bool = false
    @State private var shakeCount: CGFloat = 0
    @State private var recoveryHovered: Bool = false
    @State private var showPassword: Bool = false
    @FocusState private var passwordFocused: Bool

    private let columnWidth: CGFloat = 380

    private var isUnlocking: Bool {
        isWorking || vault.state == .unlocking
    }

    private var canUnlock: Bool {
        !password.isEmpty && !isUnlocking
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                SecretsIcon(size: 44, lineWidth: 1.6, color: Palette.textPrimary, isLocked: true)
                    .padding(.bottom, 22)

                Text("Secrets locked")
                    .font(BodyFont.system(size: 20, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.bottom, 6)

                Text("Enter your master password to unlock the Secrets.")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: columnWidth)
                    .padding(.bottom, 24)

                VaultUnlockPasswordField(
                    password: $password,
                    showPassword: $showPassword,
                    focused: $passwordFocused,
                    onSubmit: unlock
                )
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
                        if isUnlocking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(canUnlock ? .black : Color(white: 0.55))
                        }
                        Text(vault.state == .unlocking ? "Unlocking…" : "Unlock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(VaultUnlockButtonStyle(enabled: canUnlock))
                .frame(width: columnWidth)
                .disabled(!canUnlock)
                .padding(.bottom, 14)
                .animation(.easeOut(duration: 0.18), value: canUnlock)

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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                passwordFocused = true
            }
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
                await MainActor.run {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.generic, performanceTime: .now)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        passwordFocused = true
                    }
                }
            }
        }
    }
}

/// Password field with focus-aware chrome and an inline reveal toggle.
/// The visual shell is shared between secure and plain modes so toggling
/// the eye doesn't pop the layout. Focus animates the fill and stroke a
/// touch brighter so the user gets a clear "you're typing here" cue.
private struct VaultUnlockPasswordField: View {
    @Binding var password: String
    @Binding var showPassword: Bool
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    @State private var revealHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if showPassword {
                    TextField("Master password", text: $password)
                        .focused(focused)
                        .onSubmit(onSubmit)
                } else {
                    SecureField("Master password", text: $password)
                        .focused(focused)
                        .onSubmit(onSubmit)
                }
            }
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 14, wght: 500))
            .foregroundColor(Color(white: 0.96))

            Button {
                showPassword.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    focused.wrappedValue = true
                }
            } label: {
                LucideIcon.auto(showPassword ? "eye.slash" : "eye", size: 14)
                    .foregroundColor(Color(white: revealHovered ? 0.95 : 0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { revealHovered = $0 }
            .help(showPassword ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(focused.wrappedValue ? 0.085 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(focused.wrappedValue ? 0.22 : 0.10),
                                lineWidth: focused.wrappedValue ? 0.8 : 0.6)
                )
        )
        .animation(.easeOut(duration: 0.15), value: focused.wrappedValue)
    }
}

/// Local CTA style for Secrets unlock screen. The disabled state is
/// rendered as a subtle dark capsule (matching the field) instead of a
/// 45%-opacity white pill, which read as washed-out gray. The button only
/// "lights up" once there is a password to submit.
private struct VaultUnlockButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        VaultUnlockButtonLabel(configuration: configuration, enabled: enabled)
    }
}

private struct VaultUnlockButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let enabled: Bool
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(BodyFont.system(size: 13.5, wght: 600))
            .foregroundColor(enabled ? .black : Color(white: 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(stroke, lineWidth: 0.6)
                    )
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .animation(.easeOut(duration: 0.18), value: enabled)
    }

    private var fill: Color {
        guard enabled else { return Color.white.opacity(0.06) }
        if configuration.isPressed { return Color(white: 0.82) }
        return hovered ? Color.white : Color(white: 0.97)
    }

    private var stroke: Color {
        enabled ? Color.clear : Color.white.opacity(0.10)
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
