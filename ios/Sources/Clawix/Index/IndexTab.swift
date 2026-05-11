import SwiftUI

/// iOS entry for the Index surface. v1 ships the visual scaffold + a
/// "Coming soon" empty state — Index data is read through the daemon
/// bridge proxy, which is being wired up in a follow-up. The view
/// uses iOS 26 Liquid Glass chrome so when the daemon proxy lands the
/// surface is already on-brand.
struct IndexTab: View {
    @State private var selectedTab: TopTab = .catalog

    enum TopTab: String, CaseIterable, Identifiable, Hashable {
        case catalog, searches, monitors, alerts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .catalog: return "Catalog"
            case .searches: return "Searches"
            case .monitors: return "Monitors"
            case .alerts: return "Alerts"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                tabRow
                Spacer()
                comingSoon
                Spacer()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Index")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TopTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.title)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    private var comingSoon: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange.opacity(0.45), .pink.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                Image(systemName: "books.vertical")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(.white.opacity(0.95))
            }
            Text("Index on iPhone is coming")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text("v1 ships on the desktop. The daemon proxy that pipes types, entities, monitors and alerts to your phone is rolling out next. Open Clawix on Mac to start capturing.")
                .font(.system(size: 13.5))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

#Preview {
    IndexTab().preferredColorScheme(.dark)
}
