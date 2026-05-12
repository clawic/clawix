import SwiftUI

enum IndexTab: String, CaseIterable, Identifiable, Hashable {
    case catalog
    case searches
    case monitors
    case runs
    case alerts

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .catalog: return "Catalog"
        case .searches: return "Searches"
        case .monitors: return "Monitors"
        case .runs: return "Runs"
        case .alerts: return "Alerts"
        }
    }
}

struct IndexScreen: View {
    @StateObject private var manager = IndexManager()
    @State private var activeTab: IndexTab = .catalog
    @State private var showCreateSearchSheet = false

    var body: some View {
        VStack(spacing: 0) {
            IndexHeaderBar(
                manager: manager,
                activeTab: $activeTab,
                onCreateSearch: { showCreateSearchSheet = true },
                onRefresh: { Task { await manager.refresh() } }
            )
            CardDivider()
            Group {
                switch manager.state {
                case .idle, .loading:
                    IndexLoadingView()
                case .error(let message):
                    IndexEmptyState(
                        title: "Index unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: message
                    )
                case .ready:
                    contentForActiveTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.001))
        .task {
            if manager.state == .idle {
                await manager.refresh()
            }
        }
        .sheet(isPresented: $showCreateSearchSheet) {
            SearchEditorSheet(manager: manager, onDismiss: { showCreateSearchSheet = false })
        }
    }

    @ViewBuilder
    private var contentForActiveTab: some View {
        switch activeTab {
        case .catalog:
            CatalogTabView(manager: manager)
        case .searches:
            SearchesTabView(manager: manager, onCreate: { showCreateSearchSheet = true })
        case .monitors:
            MonitorsTabView(manager: manager)
        case .runs:
            RunsTabView(manager: manager)
        case .alerts:
            AlertsTabView(manager: manager)
        }
    }
}

struct IndexEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            LucideIcon.auto(systemImage, size: 28)
                .foregroundColor(.white.opacity(0.30))
                .frame(width: 36, height: 36)
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text(description)
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct IndexHeaderBar: View {
    @ObservedObject var manager: IndexManager
    @Binding var activeTab: IndexTab
    let onCreateSearch: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    IndexIcon(size: 18)
                        .foregroundColor(.white.opacity(0.9))
                    Text("Index")
                        .font(BodyFont.system(size: 17, wght: 600))
                        .foregroundColor(.white)
                    if manager.unreadAlerts > 0 {
                        Text("\(manager.unreadAlerts)")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.9))
                            )
                    }
                }
                Spacer()
                Button(action: onCreateSearch) {
                    HStack(spacing: 6) {
                        LucideIcon.auto("plus", size: 12)
                        Text("New search")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: onRefresh) {
                    LucideIcon.auto("arrow.triangle.2.circlepath", size: 12)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack {
                IndexTabBar(activeTab: $activeTab, unreadAlerts: manager.unreadAlerts)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }
}

private struct IndexTabBar: View {
    @Binding var activeTab: IndexTab
    let unreadAlerts: Int

    var body: some View {
        SlidingSegmented<IndexTab>(
            selection: $activeTab,
            options: IndexTab.allCases.map { tab in
                if tab == .alerts && unreadAlerts > 0 {
                    return (tab, "\(tab.displayName) · \(unreadAlerts)")
                }
                return (tab, tab.displayName)
            },
            height: 30
        )
        .frame(width: 460)
    }
}

private struct IndexLoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white.opacity(0.7))
            Text("Loading Index…")
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
