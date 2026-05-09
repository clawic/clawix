import AppKit
import SwiftUI
import ClawixCore

// Settings page for the Remote Agent Mesh. Three top-level cards:
//
//   • This Mac — the local node identity (display name, node id, the
//     LAN/Tailscale/loopback endpoints peers can reach us on).
//   • Pair with another Mac — host + http port + token + permission
//     profile, posts to /mesh/link.
//   • Paired Macs — list of `PeerRecord`s with permission profile,
//     endpoints, last-seen timestamp, revoked flag, and a per-peer
//     "remote workspace" path the user wants outbound jobs to default
//     to.
//   • Workspaces this Mac trusts — local allowlist that incoming
//     remote jobs can target. Add via folder picker.
//
// Pure SwiftUI on top of the existing `SettingsKit` primitives so the
// chrome (cards, dividers, dropdowns, sliding segmented) matches the
// rest of the Settings surface.
struct MachinesPage: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeshStore

    @State private var pairingHost: String = ""
    @State private var pairingPort: String = "7779"
    @State private var pairingToken: String = ""
    @State private var pairingProfile: PeerPermissionProfile = .scoped
    @State private var pairingInFlight = false
    @State private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Machines",
                subtitle: "Pair this Mac with other Macs running Clawix and run jobs across them."
            )

            if let error = store.lastError {
                InfoBanner(text: error, kind: .error)
                    .padding(.bottom, 8)
            }

            thisMacSection

            SectionLabel(title: "Pair with another Mac")
            pairingCard

            SectionLabel(title: "Paired Macs")
            peersCard

            SectionLabel(title: "Workspaces this Mac trusts")
            workspacesCard
        }
        .task {
            await store.refreshAll()
        }
    }

    // MARK: - This Mac

    @ViewBuilder
    private var thisMacSection: some View {
        SettingsCard {
            if let identity = store.identity {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(identity.displayName)
                                .font(BodyFont.system(size: 14, weight: .semibold))
                                .foregroundColor(Palette.textPrimary)
                            Text("Node id: \(identity.nodeId)")
                                .font(BodyFont.system(size: 11.5))
                                .foregroundColor(Palette.textSecondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        IconChipButton(symbol: "arrow.triangle.2.circlepath", label: "Refresh") {
                            Task { await store.refreshAll() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    CardDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endpoints")
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                        ForEach(Array(identity.endpoints.enumerated()), id: \.offset) { _, ep in
                            EndpointRow(endpoint: ep)
                        }
                        if identity.endpoints.isEmpty {
                            Text("No reachable endpoints yet — start the bridge from Settings → General.")
                                .font(BodyFont.system(size: 11.5))
                                .foregroundColor(Palette.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            } else {
                HStack {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                        Text("Loading this Mac's identity…")
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textSecondary)
                    } else {
                        Text("Daemon unreachable. Start the bridge from Settings → General.")
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                if let result = store.lastPairingResult {
                    Group {
                        switch result {
                        case .success(let name):
                            InfoBanner(text: "Linked with \(name)", kind: .ok)
                        case .failure(let message):
                            InfoBanner(text: message, kind: .error)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }

                pairingField(label: "Host", placeholder: "192.168.1.20 or my-mac.local", text: $pairingHost)
                CardDivider()
                pairingField(label: "HTTP port", placeholder: "7779", text: $pairingPort)
                CardDivider()
                pairingField(label: "Pairing token", placeholder: "Token from the other Mac", text: $pairingToken, secure: true)
                CardDivider()

                SettingsRow {
                    RowLabel(title: "Trust profile",
                             detail: "Scoped is the safest default. Switch to full trust only for Macs you fully control.")
                } trailing: {
                    SlidingSegmented(
                        selection: $pairingProfile,
                        options: [
                            (.scoped, "Scoped"),
                            (.fullTrust, "Full trust"),
                            (.askPerTask, "Ask")
                        ]
                    )
                    .frame(width: 280)
                }
                CardDivider()

                HStack {
                    Spacer()
                    Button {
                        Task { await runPairing() }
                    } label: {
                        HStack(spacing: 6) {
                            if pairingInFlight {
                                ProgressView().controlSize(.small)
                            }
                            Text(pairingInFlight ? "Linking…" : "Link with this Mac")
                                .font(BodyFont.system(size: 12.5, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous).fill(Color(red: 0.16, green: 0.46, blue: 0.98))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPair)
                    .opacity(canPair ? 1 : 0.4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var canPair: Bool {
        !pairingInFlight
            && !pairingHost.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(pairingPort) != nil
            && !pairingToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runPairing() async {
        pairingInFlight = true
        defer { pairingInFlight = false }
        let host = pairingHost.trimmingCharacters(in: .whitespaces)
        let token = pairingToken.trimmingCharacters(in: .whitespaces)
        let port = Int(pairingPort) ?? 7779
        await store.pair(host: host, httpPort: port, token: token, profile: pairingProfile)
        if case .success = store.lastPairingResult {
            pairingHost = ""
            pairingToken = ""
        }
    }

    @ViewBuilder
    private func pairingField(label: String, placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        SettingsRow {
            RowLabel(title: LocalizedStringKey(label), detail: nil)
        } trailing: {
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12.5))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 8)
            .frame(width: 280, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Peers

    @ViewBuilder
    private var peersCard: some View {
        SettingsCard {
            if store.peers.isEmpty {
                HStack {
                    Text("No paired Macs yet. Use the form above to link one.")
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.peers.enumerated()), id: \.element.nodeId) { idx, peer in
                        PeerRow(peer: peer)
                        if idx < store.peers.count - 1 {
                            CardDivider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Workspaces

    @ViewBuilder
    private var workspacesCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if store.workspaces.isEmpty {
                    HStack {
                        Text("No allowed workspaces yet. Add a folder so paired Macs can run jobs in it.")
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                } else {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { idx, ws in
                        WorkspaceRow(workspace: ws)
                        if idx < store.workspaces.count - 1 {
                            CardDivider()
                        }
                    }
                }
                CardDivider()
                HStack {
                    Spacer()
                    IconChipButton(symbol: "folder", label: "Add folder…", isPrimary: true) {
                        Task { await pickAndAddWorkspace() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func pickAndAddWorkspace() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder remote Macs can run jobs in"
        panel.prompt = "Allow"
        let response = await MainActor.run { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        await store.addWorkspace(path: url.path)
    }
}

// MARK: - Endpoint row

private struct EndpointRow: View {
    let endpoint: RemoteEndpoint

    var body: some View {
        HStack(spacing: 8) {
            kindPill
            Text("\(endpoint.host):\(endpoint.httpPort)")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .textSelection(.enabled)
            Spacer()
            Text("ws \(endpoint.bridgePort)")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
        }
    }

    private var kindPill: some View {
        Text(endpoint.kind.uppercased())
            .font(BodyFont.system(size: 9.5, weight: .bold))
            .tracking(0.5)
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

// MARK: - Peer row

private struct PeerRow: View {
    @EnvironmentObject var store: MeshStore
    let peer: PeerRecord

    @State private var workspaceDraft: String = ""
    @State private var workspaceFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(peer.displayName)
                            .font(BodyFont.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        statusPill
                    }
                    Text(peer.nodeId)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer()
                profilePill
            }

            HStack(spacing: 6) {
                ForEach(Array(peer.endpoints.prefix(3).enumerated()), id: \.offset) { _, ep in
                    EndpointMini(endpoint: ep)
                }
                if peer.endpoints.count > 3 {
                    Text("+\(peer.endpoints.count - 3)")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                }
                Spacer()
                if let lastSeen = peer.lastSeenAt {
                    Text("Last seen \(Self.relativeTimeFormatter.localizedString(for: lastSeen, relativeTo: Date()))")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                }
            }

            HStack(spacing: 8) {
                LucideIcon(.folder, size: 12)
                    .foregroundColor(Palette.textSecondary)
                TextField(
                    "Default remote workspace path on this Mac",
                    text: $workspaceDraft,
                    onCommit: { commitWorkspace() }
                )
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .onAppear {
                    workspaceDraft = store.remoteWorkspace(for: peer.nodeId)
                }
                .onSubmit { commitWorkspace() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func commitWorkspace() {
        store.setRemoteWorkspace(workspaceDraft, for: peer.nodeId)
    }

    private var statusPill: some View {
        Group {
            if peer.revokedAt != nil {
                pill(text: "Revoked", color: .red.opacity(0.65))
            } else if isOnline {
                pill(text: "Online", color: .green.opacity(0.65))
            } else {
                pill(text: "Offline", color: .gray.opacity(0.55))
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
        return pill(text: label, color: Color.white.opacity(0.10))
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(BodyFont.system(size: 10.5, weight: .semibold))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(
                Capsule(style: .continuous).fill(color)
            )
    }

    private var isOnline: Bool {
        guard let lastSeen = peer.lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeen) < 120
    }

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Compact endpoint chip used in peer rows

private struct EndpointMini: View {
    let endpoint: RemoteEndpoint
    var body: some View {
        Text("\(endpoint.kind) \(endpoint.host)")
            .font(BodyFont.system(size: 10.5, weight: .medium))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}

// MARK: - Workspace row

private struct WorkspaceRow: View {
    let workspace: RemoteWorkspace

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LucideIcon(.folder, size: 13)
                .foregroundColor(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.label)
                    .font(BodyFont.system(size: 12.5, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(workspace.path)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
