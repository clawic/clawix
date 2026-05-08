import SwiftUI

enum SecretsScreenMode: Equatable {
    case home
    case audit
    case trash
}

struct SecretsScreen: View {
    @EnvironmentObject private var vault: VaultManager
    @State private var mode: SecretsScreenMode = .home

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch vault.state {
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.regular)
                    .tint(Color(white: 0.6))
            case .uninitialized:
                SecretsOnboardingView()
            case .locked, .unlocking:
                VaultLockScreen()
            case .unlocked:
                unlockedContent
            case .openFailed(let message):
                SecretsOpenFailedView(message: message)
            }
            if let report = vault.integrityReport, !report.isIntact {
                IntegrityFailedBanner()
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { vault.pendingApprovals.first != nil },
            set: { _ in }
        )) {
            if let pending = vault.pendingApprovals.first {
                AgentApprovalPromptView(
                    pending: pending,
                    onApprove: { vault.resolvePending(pending, outcome: .approved) },
                    onDeny: { vault.resolvePending(pending, outcome: .denied(reason: nil)) }
                )
            }
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        switch mode {
        case .home:
            SecretsHomeView(
                onOpenAudit: { mode = .audit },
                onOpenTrash: { mode = .trash }
            )
        case .audit:
            SecretsAuditView(onBack: { mode = .home })
        case .trash:
            SecretsTrashView(onBack: { mode = .home })
        }
    }
}

private struct SecretsOpenFailedView: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            SecretsIcon(size: 38, lineWidth: 1.5, color: Color.red.opacity(0.85))
            Text("Could not open the vault")
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(message)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .frame(maxWidth: 360)
        }
        .padding(40)
    }
}

private struct IntegrityFailedBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
            Text("Audit chain broken")
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.red.opacity(0.85))
        )
        .shadow(color: Color.red.opacity(0.3), radius: 12, y: 4)
    }
}
