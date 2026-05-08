import SwiftUI
import SecretsModels
import SecretsVault

struct SecretsTrashView: View {
    @EnvironmentObject private var vault: VaultManager
    @EnvironmentObject private var appState: AppState
    let onBack: () -> Void

    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconChipButton(
                symbol: "chevron.left",
                label: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Trash")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: "\(vault.trashedSecrets.count) item\(vault.trashedSecrets.count == 1 ? "" : "s") · auto-purged after 30 days")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var content: some View {
        Group {
            if let error {
                errorState(error)
            } else if vault.trashedSecrets.isEmpty {
                emptyState
            } else {
                listState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            InfoBanner(text: message, kind: .error)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 64, height: 64)
                Image(systemName: "trash")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(Palette.textSecondary)
            }
            VStack(spacing: 4) {
                Text("Trash is empty")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Secrets you delete land here for 30 days. Restore them, or delete them forever.")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var listState: some View {
        ScrollView {
            SettingsCard {
                ForEach(Array(vault.trashedSecrets.enumerated()), id: \.element.id) { idx, secret in
                    if idx > 0 {
                        CardDivider()
                    }
                    TrashRow(
                        secret: secret,
                        onRestore: { restore(secret) },
                        onDeleteForever: { requestDeleteForever(secret) }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .thinScrollers()
    }

    private func requestDeleteForever(_ secret: SecretRecord) {
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Delete forever?",
            body: LocalizedStringKey("'\(secret.title)' will be permanently destroyed. The action is recorded in the activity log but the value cannot be recovered."),
            confirmLabel: "Delete forever",
            isDestructive: true,
            onConfirm: { deleteForever(secret) }
        )
    }

    private func restore(_ secret: SecretRecord) {
        guard let store = vault.store else { return }
        do {
            try store.restoreSecret(id: secret.id)
            withAnimation(.easeOut(duration: 0.18)) {
                vault.reload()
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func deleteForever(_ secret: SecretRecord) {
        guard let store = vault.store else { return }
        do {
            // Mark trashedAt to a very old timestamp and immediately purge.
            let cutoff = Clock.now() + 1
            _ = try store.purgeTrashed(olderThan: cutoff)
            withAnimation(.easeOut(duration: 0.18)) {
                vault.reload()
            }
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct TrashRow: View {
    let secret: SecretRecord
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            SecretsIcon(size: 18, lineWidth: 1.3, color: Palette.textSecondary, isLocked: true)
                .opacity(0.65)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: secret.title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                if let trashedAt = secret.trashedAt {
                    Text(verbatim: "Trashed \(EventRow.formatter.localizedString(for: trashedAt.asDate, relativeTo: Date())) · \(secret.kind.rawValue.replacingOccurrences(of: "_", with: " "))")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer(minLength: 12)
            Button("Restore", action: onRestore)
                .buttonStyle(SheetCancelButtonStyle())
            Button("Delete forever", action: onDeleteForever)
                .buttonStyle(SheetDestructiveButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(MenuRowHover(active: hovered))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}
