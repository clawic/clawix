import SwiftUI
import SecretsModels
import SecretsVault
struct SecretsHomeView: View {
    @EnvironmentObject private var vault: VaultManager
    @State private var selectedSecretId: EntityID?
    @State private var showAddSheet: Bool = false
    @State private var listFilter: ListFilter = .all
    var onOpenAudit: () -> Void = {}
    var onOpenTrash: () -> Void = {}

    enum ListFilter: Hashable { case all, stale }

    private var staleCount: Int { vault.staleSecrets(olderThanDays: 90).count }

    private var visibleSecrets: [SecretRecord] {
        switch listFilter {
        case .all:   return vault.secrets
        case .stale: return vault.staleSecrets(olderThanDays: 90)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            HStack(spacing: 0) {
                listPane
                    .frame(width: 280)
                CardDivider()
                    .frame(width: 1)
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showAddSheet) {
            AddSecretSheet(isPresented: $showAddSheet, onCreated: { id in
                vault.reload()
                selectedSecretId = id
            })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Secrets")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.34, green: 0.78, blue: 0.55))
                        .frame(width: 6, height: 6)
                    Text(verbatim: "\(vault.secrets.count) secret\(vault.secrets.count == 1 ? "" : "s") · vault unlocked")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer()
            IconChipButton(symbol: "list.bullet.rectangle", label: "Activity", action: onOpenAudit)
            IconChipButton(symbol: "trash", label: "Trash", action: onOpenTrash)
            IconChipButton(symbol: "lock", action: { vault.lock() })
            IconChipButton(
                symbol: "plus",
                label: "New secret",
                isPrimary: true,
                action: { showAddSheet = true }
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            filterStrip
            if visibleSecrets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(visibleSecrets, id: \.id) { secret in
                            SecretListRow(
                                secret: secret,
                                isSelected: selectedSecretId == secret.id
                            ) {
                                selectedSecretId = secret.id
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .thinScrollers()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filterStrip: some View {
        let options: [(ListFilter, String)] = [
            (.all,   "All"),
            (.stale, "Stale 90d")
        ]
        let visibleCount = visibleSecrets.count
        let totalCount = vault.secrets.count
        let stale = staleCount
        let caption: String = {
            switch listFilter {
            case .all:   return "\(visibleCount) of \(totalCount)"
            case .stale: return "\(stale) of \(totalCount) · idle > 90d"
            }
        }()
        return VStack(spacing: 6) {
            SlidingSegmented(
                selection: $listFilter,
                options: options,
                height: 28,
                fontSize: 11.5
            )
            HStack(spacing: 0) {
                Text(verbatim: caption)
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textSecondary.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 28)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 64, height: 64)
                SecretsIcon(size: 32, lineWidth: 1.5, color: Palette.textSecondary, isLocked: false)
            }
            VStack(spacing: 4) {
                Text("No secrets yet")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Add your first API key, login, or note. They'll show up here.")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
            Button {
                showAddSheet = true
            } label: {
                Text("Add your first secret")
            }
            .buttonStyle(SheetPrimaryButtonStyle(enabled: true))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        Group {
            if let id = selectedSecretId, let secret = vault.secrets.first(where: { $0.id == id }) {
                SecretDetailPane(secret: secret)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .softNudge(y: 4)))
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Pick a secret to inspect")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(selectedSecretId)
        .animation(.easeOut(duration: 0.18), value: selectedSecretId)
    }
}

// MARK: - List row

private struct SecretListRow: View {
    let secret: SecretRecord
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                SecretKindIcon(kind: secret.kind, size: 18, lineWidth: 1.3, color: Color(white: 0.86))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(verbatim: secret.title)
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                        if secret.isCompromised {
                            LucideIcon(.shieldAlert, size: 10)
                                .foregroundColor(Color.red.opacity(0.85))
                        }
                    }
                    Text(verbatim: secret.kind.friendlyLabel)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovering || isSelected))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}
