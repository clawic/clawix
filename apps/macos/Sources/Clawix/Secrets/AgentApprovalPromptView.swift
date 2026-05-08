import SwiftUI
import SecretsModels
import SecretsProxyCore
import SecretsVault

/// Floating sheet shown over `SecretsScreen` when the proxy bridge has
/// queued an activation request from an agent. Presents the agent name,
/// the secret it wants to use, the capability, the reason, the duration,
/// and any scope the agent declared. The user can approve or deny; the
/// helper binary unblocks with the resulting token or error.
struct AgentApprovalPromptView: View {
    @ObservedObject var pending: PendingApprovalRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var denyReason: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            VaultCard {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Agent", value: pending.request.agent)
                    detailRow(label: "Secret", value: pending.request.secretInternalName)
                    detailRow(label: "Capability", value: pending.request.capability)
                    detailRow(label: "Window", value: "\(pending.request.durationMinutes) minutes")
                    if !pending.request.scope.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scope")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(pending.request.scope.sorted(by: { $0.key < $1.key }), id: \.key) { (k, v) in
                                    Text("\(k) = \(v)")
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(Palette.textPrimary)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason from the agent")
                    .font(BodyFont.system(size: 11.5, wght: 700))
                    .foregroundColor(Palette.textSecondary)
                ScrollView {
                    Text(pending.request.reason)
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .thinScrollers()
                .frame(maxHeight: 80)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .padding(.top, 14)

            Text("Approving issues a one-time token bound to this agent + capability for the window above. You can revoke it at any time from the Activity tab.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary)
                .padding(.top, 10)

            HStack(spacing: 10) {
                VaultSecondaryButton(title: "Deny", action: onDeny)
                Spacer()
                Button(action: onApprove) {
                    Text("Approve · issue token")
                        .font(BodyFont.system(size: 12, wght: 700))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.green.opacity(0.78))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .frame(width: 480)
        .padding(22)
        .background(Color(white: 0.07))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(.key, size: 12.5)
                .foregroundColor(Color.orange.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent activation requested")
                    .font(BodyFont.system(size: 16, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Text("An agent is asking permission to use a sensitive capability of one of your secrets.")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Spacer()
        }
    }
}
