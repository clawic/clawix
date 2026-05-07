import SwiftUI
import AppKit

/// Logged-out screen. Replaces the chat / settings content area when the
/// runtime CLI has no stored credentials. Drives login from the
/// primary button and lets the user cancel an in-flight OAuth flow.
struct LoginGateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LoginCard()
                    .frame(maxWidth: 460)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Card

private struct LoginCard: View {
    @EnvironmentObject var appState: AppState

    private var inProgress: Bool { appState.auth.loginInProgress }
    private var error: String? { appState.auth.loginError }
    private var hasBinary: Bool { appState.clawixBinary != nil }

    var body: some View {
        VStack(spacing: 26) {
            BrandMark()

            VStack(spacing: 10) {
                Text("Sign in")
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Sign in to recover access to your chats and projects.")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                PrimaryLoginButton(
                    inProgress: inProgress,
                    enabled: hasBinary,
                    onTap: { appState.startBackendLogin() }
                )
                if inProgress {
                    HStack(spacing: 8) {
                        Text("We've opened the browser. Come back here when you've confirmed.")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: { appState.auth.cancelLogin() }) {
                        Text("Cancel")
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(Color(white: 0.78))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error {
                Text(error)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !hasBinary {
                Text("Could not locate the required binary. Set its path under Settings → Advanced settings.")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 38)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 18)
    }
}

// MARK: - Brand mark

private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                )
                .frame(width: 56, height: 56)

            Text(">_")
                .font(BodyFont.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.92))
                .offset(x: -1)
        }
    }
}

// MARK: - Primary button

private struct PrimaryLoginButton: View {
    let inProgress: Bool
    let enabled: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: { if !inProgress, enabled { onTap() } }) {
            HStack(spacing: 10) {
                if inProgress {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(.black)
                    Text("Waiting for confirmation…")
                } else {
                    Image(systemName: "arrow.right.to.line")
                        .font(BodyFont.system(size: 13, weight: .semibold))
                    Text("Sign in")
                }
            }
            .font(BodyFont.system(size: 13.5, wght: 700))
            .foregroundColor(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || inProgress)
        .opacity(enabled ? 1 : 0.55)
        .onHover { hovered = $0 }
    }

    private var buttonFill: Color {
        if !enabled { return Color(white: 0.55) }
        if hovered  { return Color(white: 1.0) }
        return Color(white: 0.94)
    }
}
