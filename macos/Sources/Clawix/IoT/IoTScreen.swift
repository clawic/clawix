import SwiftUI

/// Top-level IoT screen. Routes from `SidebarRoute.iotHome`. Hosts the
/// five tabs that span the Home Assistant–style surface: Devices,
/// Scenes, Automations, Approvals, Add device. The tabs above the fold
/// share a single home (`IoTManager.currentHomeId`); multi-home users
/// can switch via the home selector pinned to the top-right.
@MainActor
struct IoTScreen: View {

    enum Tab: String, Hashable, CaseIterable {
        case devices = "Devices"
        case scenes = "Scenes"
        case automations = "Automations"
        case approvals = "Approvals"
        case discovery = "Add device"
    }

    @EnvironmentObject private var manager: IoTManager
    @AppStorage(ClawixPersistentSurfaceKeys.iotTab) private var tabRaw: String = Tab.devices.rawValue
    @State private var catastrophicApproval: ApprovalRecord?

    private var selectedTab: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: tabRaw) ?? .devices },
            set: { tabRaw = $0.rawValue },
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if case .ready = manager.state, let lastError = manager.lastError {
                    errorBanner(lastError)
                }
                tabContent
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if case .ready = manager.state {
                try? await manager.refreshAll()
            }
        }
        .onChange(of: manager.approvals) { _, approvals in
            // Auto-open the catastrophic modal when a new
            // restricted-risk approval lands. Constitution VII.4 marks
            // these as actions that interrupt the user.
            if let pending = approvals
                .filter({ $0.status == "pending" })
                .first(where: { $0.reason.lowercased().contains("restricted") }) {
                if catastrophicApproval?.id != pending.id {
                    catastrophicApproval = pending
                }
            }
        }
        .sheet(item: $catastrophicApproval) { approval in
            IoTCatastrophicApprovalModal(approval: approval)
                .environmentObject(manager)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Home")
                    .font(BodyFont.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: subtitle)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer()
            if manager.homes.count > 1 {
                Menu {
                    ForEach(manager.homes) { home in
                        Button {
                            Task { await manager.switchHome(home.id) }
                        } label: {
                            Text(verbatim: home.label)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: manager.homes.first(where: { $0.id == manager.currentHomeId })?.label ?? "—")
                            .font(BodyFont.system(size: 12, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Palette.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
            }
            SlidingSegmented(
                selection: selectedTab,
                options: Tab.allCases.map { ($0, $0.rawValue) },
                height: 28,
                fontSize: 11.5,
            )
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        switch manager.state {
        case .loading: return "Loading"
        case .bootstrapping: return "Connecting to daemon"
        case .ready:
            let thingCount = manager.things.count
            let approvalsBadge = manager.pendingApprovalsCount > 0
                ? " · \(manager.pendingApprovalsCount) pending approval\(manager.pendingApprovalsCount == 1 ? "" : "s")"
                : ""
            return "\(thingCount) device\(thingCount == 1 ? "" : "s")\(approvalsBadge)"
        case .failed(let reason): return reason
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(verbatim: message)
            .font(BodyFont.system(size: 11.5, weight: .medium))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.10))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch manager.state {
        case .ready:
            switch selectedTab.wrappedValue {
            case .devices: IoTThingsView()
            case .scenes: IoTScenesView()
            case .automations: IoTAutomationsView()
            case .approvals: IoTApprovalsView()
            case .discovery: IoTDiscoveryView()
            }
        case .loading, .bootstrapping:
            placeholder(text: "Connecting to the IoT service…", showsSpinner: true)
        case .failed(let reason):
            placeholder(text: reason, showsSpinner: false)
        }
    }

    @ViewBuilder
    private func placeholder(text: String, showsSpinner: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            if showsSpinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Palette.textSecondary)
            }
            Text(verbatim: text)
                .font(BodyFont.system(size: 13))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
