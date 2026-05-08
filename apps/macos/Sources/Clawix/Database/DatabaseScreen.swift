import SwiftUI

/// Database screen: parameterized by route. In `.databaseHome` shows
/// the 3-pane admin (collections sidebar + collection view + detail);
/// in `.databaseCollection(name)` shows a 2-pane curated view (no
/// collections sidebar) for that single collection with its curated
/// tabs.
struct DatabaseScreen: View {
    let mode: Mode

    enum Mode: Equatable {
        case admin
        case curated(collectionName: String)
    }

    @EnvironmentObject private var manager: DatabaseManager
    @State private var selectedCollection: String?

    var body: some View {
        Group {
            switch manager.state {
            case .loading, .bootstrapping:
                bootstrapPlaceholder
            case .failed(let reason):
                failedPlaceholder(reason: reason)
            case .ready:
                content
            }
        }
        .background(Palette.background)
    }

    private var bootstrapPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to database service…")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedPlaceholder(reason: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text("Database service is unavailable")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(reason)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await manager.bootstrap() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .curated(let name):
            if let collection = manager.collection(named: name) {
                CollectionView(collection: collection, showsCuratedTabs: true)
            } else {
                Text("Collection \(name) not found")
                    .foregroundColor(Palette.textSecondary)
            }
        case .admin:
            HStack(spacing: 0) {
                CollectionsListSidebar(selectedCollection: $selectedCollection)
                    .frame(width: 240)
                Divider().background(Color.white.opacity(0.07))
                if let name = selectedCollection ?? manager.collections.first?.name,
                   let collection = manager.collection(named: name) {
                    CollectionView(collection: collection, showsCuratedTabs: false)
                } else {
                    VStack {
                        Text("Pick a collection from the left.")
                            .foregroundColor(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                if selectedCollection == nil {
                    selectedCollection = manager.collections.first?.name
                }
            }
        }
    }
}
