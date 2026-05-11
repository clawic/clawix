import SwiftUI

/// Blocking sheet for catastrophic-risk approvals (constitution VII.4:
/// catastrophic = the framework interrupts the user). Presented from
/// `IoTScreen` whenever a new `ApprovalRecord` with a restricted-risk
/// reason lands in the queue. The user can approve, deny, or open the
/// queue to inspect the full request shape before committing.
struct IoTCatastrophicApprovalModal: View {
    let approval: ApprovalRecord
    @EnvironmentObject private var manager: IoTManager
    @Environment(\.dismiss) private var dismiss
    @State private var inFlight = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.red.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Approval required")
                        .font(BodyFont.system(size: 15, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    Text(verbatim: "This action is rated catastrophic and needs your explicit approval before reaching the device.")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                row(label: "Action", value: approval.action.action)
                row(label: "Target", value: targetLabel)
                row(label: "Capability", value: approval.action.capability ?? "(default)")
                row(label: "Reason", value: approval.reason)
                row(label: "Created", value: approval.createdAt)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: "Later")
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                Button {
                    Task { await deny() }
                } label: {
                    Text(verbatim: "Deny")
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
                Button {
                    Task { await approve() }
                } label: {
                    HStack(spacing: 4) {
                        if inFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(Palette.textPrimary)
                        }
                        Text(verbatim: "Approve and run")
                    }
                    .font(BodyFont.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.50))
                    )
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 540)
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 88, alignment: .leading)
            Text(verbatim: value)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private var targetLabel: String {
        approval.action.selector
            ?? approval.action.targets?.first
            ?? approval.action.family
            ?? "(unknown)"
    }

    private func approve() async {
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await manager.approveApproval(approval)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deny() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await manager.denyApproval(approval)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
