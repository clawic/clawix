import SwiftUI
import SecretsModels
import SecretsVault

struct GrantsTab: View {
    @EnvironmentObject private var vault: SecretsManager
    let secret: SecretRecord
    let onChanged: () -> Void
    @State private var error: String?
    @State private var grantsForSecret: [AgentGrantRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { SecretsErrorLine(text: error) }
            if grantsForSecret.isEmpty {
                Text("No agent grants for this secret yet.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                Text("Grants are created via `claw secrets grants issue`. Approving the prompt issues a one-time token bound to a specific capability.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            } else {
                ForEach(grantsForSecret, id: \.id) { grant in
                    grantRow(grant)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: vault.activeGrants) { _, _ in reload() }
    }

    private func grantRow(_ grant: AgentGrantRecord) -> some View {
        let now = Clock.now()
        let expired = grant.expiresAt <= now
        let revoked = grant.revokedAt != nil
        let active = !expired && !revoked
        let badge = active ? "ACTIVE" : (revoked ? "REVOKED" : "EXPIRED")
        let badgeColor: Color = active ? .green.opacity(0.7) : (revoked ? .red.opacity(0.7) : Color(white: 0.45))
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(badge)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(badgeColor))
                    Text(grant.agent)
                        .font(BodyFont.system(size: 13, wght: 700))
                        .foregroundColor(Palette.textPrimary)
                    Text(grant.capability.rawValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                }
                Text(grant.reason)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
                Text("created \(grant.createdAt.asDate.formatted(.relative(presentation: .numeric))) · expires \(grant.expiresAt.asDate.formatted(.relative(presentation: .numeric))) · used \(grant.usedCount)x")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer()
            if active {
                Button { revoke(grant) } label: {
                    Text("Revoke")
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Color.red.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.red.opacity(0.3), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func reload() {
        grantsForSecret = vault.activeGrants.filter { $0.secretId == secret.id }
        if grantsForSecret.isEmpty, let store = vault.grants {
            // Show inactive (revoked / expired) too if there are no active.
            let all = (try? store.listAll(limit: 50)) ?? []
            grantsForSecret = all.filter { $0.secretId == secret.id }
        }
    }

    private func revoke(_ grant: AgentGrantRecord) {
        guard let grants = vault.grants else { return }
        do {
            _ = try grants.revoke(grantId: grant.id)
            vault.reloadGrants()
            reload()
            onChanged()
        } catch {
            self.error = String(describing: error)
        }
    }
}
