import AppKit
import SwiftUI
import ClawixCore

struct HostsPage: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeshStore

    @State private var kindFilter: HostKindFilter = .all
    @State private var searchText: String = ""
    @State private var editorItem: HostEditorItem? = nil
    @State private var detailItem: HostDetailItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Hosts",
                subtitle: "Macs, iPhones, Linux servers and PCs registered with this Mac's mesh."
            )

            if let error = store.lastError {
                InfoBanner(text: error, kind: .error)
                    .padding(.bottom, 8)
            }

            thisMacSection

            SectionLabel(title: "Hosts")
            hostsCard

            SectionLabel(title: "Workspaces this Mac trusts")
            workspacesCard
        }
        .task {
            await store.refreshAll()
        }
        .sheet(item: $editorItem) { _ in
            HostEditorSheet(
                store: store,
                onClose: { editorItem = nil }
            )
        }
        .sheet(item: $detailItem) { item in
            HostDetailView(
                peer: item.peer,
                store: store,
                onClose: { detailItem = nil }
            )
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
                            HostEndpointRow(endpoint: ep)
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

    // MARK: - Hosts

    @ViewBuilder
    private var hostsCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                hostsHeader
                CardDivider()
                hostsToolbar
                CardDivider()
                hostsList
            }
        }
    }

    private var hostsHeader: some View {
        HStack {
            Text("\(visibleHosts.count) host\(visibleHosts.count == 1 ? "" : "s")")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            Button {
                editorItem = HostEditorItem()
            } label: {
                HStack(spacing: 5) {
                    LucideIcon(.plus, size: 11)
                    Text("Add host")
                        .font(BodyFont.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    Capsule(style: .continuous).fill(Color(red: 0.16, green: 0.46, blue: 0.98))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var hostsToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(HostKindFilter.allCases) { filter in
                    HostFilterChip(
                        filter: filter,
                        count: countFor(filter: filter),
                        active: kindFilter == filter
                    ) {
                        kindFilter = filter
                    }
                }
                Spacer()
            }
            searchField
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            LucideIcon(.search, size: 11)
                .foregroundColor(Palette.textTertiary)
            TextField("Search hosts", text: $searchText)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
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
    }

    @ViewBuilder
    private var hostsList: some View {
        if store.peers.isEmpty {
            HStack {
                Text("No hosts yet. Pair another Mac, or register a Linux server via SSH.")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        } else if visibleHosts.isEmpty {
            HStack {
                Text("No hosts match the current filter.")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visibleHosts.enumerated()), id: \.element.nodeId) { idx, peer in
                    HostRow(peer: peer) {
                        detailItem = HostDetailItem(peer: peer)
                    }
                    if idx < visibleHosts.count - 1 {
                        CardDivider()
                    }
                }
            }
        }
    }

    private var visibleHosts: [PeerRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.peers.filter { peer in
            guard kindFilter.matches(peer.inferredHostKind) else { return false }
            guard !query.isEmpty else { return true }
            if peer.displayName.lowercased().contains(query) { return true }
            if peer.nodeId.lowercased().contains(query) { return true }
            if peer.endpoints.contains(where: { $0.host.lowercased().contains(query) }) {
                return true
            }
            return false
        }
    }

    private func countFor(filter: HostKindFilter) -> Int {
        store.peers.filter { filter.matches($0.inferredHostKind) }.count
    }

    // MARK: - Workspaces

    @ViewBuilder
    private var workspacesCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if store.workspaces.isEmpty {
                    HStack {
                        Text("No allowed workspaces yet. Add a folder so peers can run jobs in it.")
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                } else {
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { idx, ws in
                        HostWorkspaceRow(workspace: ws)
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
        panel.message = "Choose a folder remote peers can run jobs in"
        panel.prompt = "Allow"
        let response = await MainActor.run { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        await store.addWorkspace(path: url.path)
    }
}

// MARK: - Kind filter

enum HostKindFilter: String, CaseIterable, Identifiable {
    case all
    case mac
    case ios
    case linuxServer
    case windowsPC
    case sbc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:         return "All"
        case .mac:         return "Macs"
        case .ios:         return "iOS"
        case .linuxServer: return "Servers"
        case .windowsPC:   return "PCs"
        case .sbc:         return "Boards"
        }
    }

    func matches(_ kind: HostKind) -> Bool {
        switch self {
        case .all:         return true
        case .mac:         return kind == .mac
        case .ios:         return kind == .ios || kind == .ipad
        case .linuxServer: return kind == .linuxServer || kind == .linuxDesktop
        case .windowsPC:   return kind == .windowsPC
        case .sbc:         return kind == .sbc
        }
    }
}

private struct HostFilterChip: View {
    let filter: HostKindFilter
    let count: Int
    let active: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(filter.label)
                    .font(BodyFont.system(size: 11.5, weight: active ? .semibold : .medium))
                    .foregroundColor(active ? Palette.textPrimary : Palette.textSecondary)
                Text("\(count)")
                    .font(BodyFont.system(size: 10.5, weight: .medium))
                    .foregroundColor(active ? Palette.textPrimary.opacity(0.7) : Palette.textTertiary)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(active ? 0.10 : 0.05))
                    )
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        active
                            ? Color.white.opacity(0.12)
                            : (hovered ? Color.white.opacity(0.07) : Color.white.opacity(0.04))
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Identifiable wrappers for sheets

struct HostEditorItem: Identifiable {
    let id = UUID()
}

struct HostDetailItem: Identifiable {
    let id: String
    let peer: PeerRecord
    init(peer: PeerRecord) {
        self.id = peer.nodeId
        self.peer = peer
    }
}

// MARK: - Host endpoint row (full detail)

struct HostEndpointRow: View {
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

// MARK: - Host row (clickable, opens detail)

struct HostRow: View {
    let peer: PeerRecord
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HostKindBadge(kind: peer.inferredHostKind)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(peer.displayName)
                            .font(BodyFont.system(size: 13, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        statusPill
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(peer.endpoints.prefix(2).enumerated()), id: \.offset) { _, ep in
                            HostEndpointChip(endpoint: ep)
                        }
                        if peer.endpoints.count > 2 {
                            Text("+\(peer.endpoints.count - 2)")
                                .font(BodyFont.system(size: 10.5))
                                .foregroundColor(Palette.textTertiary)
                        }
                        if peer.endpoints.isEmpty {
                            Text("No endpoints")
                                .font(BodyFont.system(size: 11))
                                .foregroundColor(Palette.textTertiary)
                        }
                    }
                }

                Spacer()

                profilePill
                LucideIcon(.chevronRight, size: 12)
                    .foregroundColor(Palette.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(hovered ? Color.white.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
}

// MARK: - Endpoint chip (compact)

struct HostEndpointChip: View {
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

// MARK: - Host kind badge (icon + bg)

struct HostKindBadge: View {
    let kind: HostKind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.18))
            iconView
                .foregroundColor(tint)
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var iconView: some View {
        switch kind {
        case .mac, .linuxDesktop, .windowsPC: LucideIcon(.laptop, size: 16)
        case .ios, .ipad:                     LucideIcon(.appWindow, size: 16)
        case .linuxServer:                    LucideIcon(.database, size: 16)
        case .sbc:                            LucideIcon(.braces, size: 16)
        }
    }

    private var tint: Color {
        switch kind {
        case .mac:          return Color(red: 0.50, green: 0.78, blue: 1.00)
        case .ios:          return Color(red: 0.66, green: 0.79, blue: 1.00)
        case .ipad:         return Color(red: 0.78, green: 0.74, blue: 1.00)
        case .linuxServer:  return Color(red: 0.42, green: 0.88, blue: 0.74)
        case .linuxDesktop: return Color(red: 0.55, green: 0.88, blue: 0.55)
        case .windowsPC:    return Color(red: 0.95, green: 0.78, blue: 0.55)
        case .sbc:          return Color(red: 0.94, green: 0.62, blue: 0.62)
        }
    }
}

// MARK: - Workspace row

struct HostWorkspaceRow: View {
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
