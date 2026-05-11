import SwiftUI

/// Outstanding approval-gate request originating from a running agent.
/// The daemon mints one of these every time an agent with autonomy <
/// `act_full` tries to execute an action that the autonomy slider or
/// the per-action override says "always ask". The sheet shows the
/// action, the agent, and a short detail blurb; the user resolves with
/// allow / deny / always-allow / always-deny so the runtime can plug
/// the response back through `BridgeProtocol.agentApprovalResponse`.
struct AgentApprovalRequest: Identifiable, Equatable {
    var id: String = UUID().uuidString
    /// `agent.id` of the agent that requested approval.
    var agentId: String
    /// Short canonical name of the gated action (e.g. `git.push`,
    /// `shell.rm`, `network.send`). Used both for the headline and as
    /// the key the runtime stores the user's persistent choice under.
    var action: String
    /// Free-form context the agent emitted alongside the request (the
    /// command it wants to run, the URL it wants to hit, etc.).
    var detail: String
}

enum AgentApprovalDecision: String {
    case allow
    case deny
    case allowAlways
    case denyAlways
}

struct AgentApprovalRequestSheet: View {
    let request: AgentApprovalRequest
    let onDecide: (AgentApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approval required")
                        .font(BodyFont.system(size: 14, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text("Agent \(request.agentId) wants to run \(request.action).")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
            }
            if !request.detail.isEmpty {
                ScrollView {
                    Text(request.detail)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 80, maxHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .thinScrollers()
            }
            HStack(spacing: 8) {
                IconChipButton(symbol: "xmark", label: "Deny") {
                    onDecide(.deny)
                }
                IconChipButton(symbol: "xmark.octagon", label: "Always deny") {
                    onDecide(.denyAlways)
                }
                Spacer()
                IconChipButton(symbol: "checkmark", label: "Allow always") {
                    onDecide(.allowAlways)
                }
                IconChipButton(symbol: "checkmark.circle", label: "Allow", isPrimary: true) {
                    onDecide(.allow)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
