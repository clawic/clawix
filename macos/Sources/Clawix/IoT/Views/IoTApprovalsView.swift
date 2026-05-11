import SwiftUI

/// Approvals tab. Queue of pending high-risk actions. Each row carries
/// approve / deny buttons. Catastrophic items also trigger the modal
/// sheet via `IoTScreen.onChange(of: approvals)`; here we surface them
/// uniformly for the user who prefers to triage from one place.
struct IoTApprovalsView: View {
    @EnvironmentObject private var manager: IoTManager
    @State private var inFlightId: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 4)
                }
                ForEach(manager.approvals) { approval in
                    ApprovalRow(
                        approval: approval,
                        isBusy: inFlightId == approval.id,
                        onApprove: { Task { await approve(approval) } },
                        onDeny: { Task { await deny(approval) } },
                    )
                }
                if manager.approvals.isEmpty {
                    Text(verbatim: "No approvals waiting.")
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textTertiary)
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .thinScrollers()
    }

    private func approve(_ approval: ApprovalRecord) async {
        inFlightId = approval.id
        defer { inFlightId = nil }
        do {
            _ = try await manager.approveApproval(approval)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deny(_ approval: ApprovalRecord) async {
        inFlightId = approval.id
        defer { inFlightId = nil }
        do {
            try await manager.denyApproval(approval)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ApprovalRow: View {
    let approval: ApprovalRecord
    let isBusy: Bool
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange.opacity(0.85))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: actionSummary)
                        .font(BodyFont.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Text(verbatim: approval.reason)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                    Text(verbatim: "Status: \(approval.status) · \(approval.createdAt)")
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: onDeny) {
                    Text(verbatim: "Deny")
                        .font(BodyFont.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(approval.status != "pending" || isBusy)

                Button(action: onApprove) {
                    HStack(spacing: 4) {
                        if isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(Palette.textPrimary)
                        }
                        Text(verbatim: "Approve")
                    }
                    .font(BodyFont.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.40))
                    )
                }
                .buttonStyle(.plain)
                .disabled(approval.status != "pending" || isBusy)
            }
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
    }

    private var actionSummary: String {
        let verb = approval.action.action
        let target = approval.action.selector ?? approval.action.targets?.first ?? approval.action.family ?? "device"
        return "\(verb.capitalized) on \(target)"
    }
}
