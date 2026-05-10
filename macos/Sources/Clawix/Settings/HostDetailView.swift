import SwiftUI
import ClawixCore

struct HostDetailView: View {
    let peer: PeerRecord
    @ObservedObject var store: MeshStore
    let onClose: () -> Void

    @State private var workspaceDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    endpointsCard
                    capabilitiesCard
                    workspaceCard
                    metadataCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
            .thinScrollers()
            .frame(maxHeight: 520)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .frame(width: 560)
        .sheetStandardBackground()
        .onAppear {
            workspaceDraft = store.remoteWorkspace(for: peer.nodeId)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HostKindBadge(kind: peer.inferredHostKind)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.displayName)
                    .font(BodyFont.system(size: 17, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 6) {
                    Text(peer.inferredHostKind.displayLabel)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                    Text("·")
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textTertiary)
                    profilePill
                    statusPill
                }
                Text(peer.nodeId)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var statusPill: some View {
        Group {
            if peer.revokedAt != nil {
                pill("Revoked", color: .red.opacity(0.65))
            } else if isOnline {
                pill("Online", color: .green.opacity(0.65))
            } else {
                pill("Offline", color: .gray.opacity(0.55))
            }
        }
    }

    private var profilePill: some View {
        let label: String
        switch peer.permissionProfile {
        case .scoped:    label = "Scoped"
        case .fullTrust: label = "Full trust"
        case .askPerTask: label = "Ask"
        }
        return pill(label, color: Color.white.opacity(0.10))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(BodyFont.system(size: 10.5, weight: .semibold))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(Capsule(style: .continuous).fill(color))
    }

    private var isOnline: Bool {
        guard let lastSeen = peer.lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeen) < 120
    }

    // MARK: - Endpoints

    private var endpointsCard: some View {
        DetailCard(title: "Endpoints") {
            if peer.endpoints.isEmpty {
                Text("No endpoints reported.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(peer.endpoints.enumerated()), id: \.offset) { _, ep in
                        HostEndpointRow(endpoint: ep)
                    }
                }
            }
        }
    }

    // MARK: - Capabilities

    private var capabilitiesCard: some View {
        DetailCard(title: "Capabilities") {
            if peer.capabilities.isEmpty {
                Text("No capabilities advertised.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(peer.capabilities, id: \.self) { cap in
                        Text(cap)
                            .font(BodyFont.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                            )
                    }
                }
            }
        }
    }

    // MARK: - Workspace

    private var workspaceCard: some View {
        DetailCard(title: "Default remote workspace") {
            HStack(spacing: 8) {
                LucideIcon(.folder, size: 13)
                    .foregroundColor(Palette.textSecondary)
                TextField(
                    "Folder on \(peer.displayName) the agent should default to",
                    text: $workspaceDraft,
                    onCommit: { commitWorkspace() }
                )
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .onSubmit { commitWorkspace() }
            }
        }
    }

    private func commitWorkspace() {
        store.setRemoteWorkspace(workspaceDraft, for: peer.nodeId)
    }

    // MARK: - Metadata

    private var metadataCard: some View {
        DetailCard(title: "Metadata") {
            VStack(alignment: .leading, spacing: 6) {
                metadataRow("Node id", peer.nodeId, monospaced: true)
                metadataRow("Signing key", peer.signingPublicKey, monospaced: true)
                metadataRow("Agreement key", peer.agreementPublicKey, monospaced: true)
                if let lastSeen = peer.lastSeenAt {
                    metadataRow("Last seen", Self.dateFormatter.string(from: lastSeen))
                } else {
                    metadataRow("Last seen", "Never")
                }
                if let revoked = peer.revokedAt {
                    metadataRow("Revoked at", Self.dateFormatter.string(from: revoked))
                }
            }
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(monospaced
                    ? .system(size: 11.5, weight: .regular, design: .monospaced)
                    : BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SheetPrimaryButtonStyle(enabled: true))
        }
    }
}

// MARK: - Detail card primitive

private struct DetailCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

