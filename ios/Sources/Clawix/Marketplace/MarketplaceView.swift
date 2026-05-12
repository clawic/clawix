import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var store: ProfileStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.intents) { intent in
                        IntentCard(intent: intent) {
                            Task { await store.expressInterest(intentId: intent.intentId) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Palette.background)
            .navigationTitle("Marketplace")
            .task { if store.intents.isEmpty { await store.bootstrap() } }
            .refreshable { await store.refreshMarketplace() }
        }
    }
}

private struct IntentCard: View {
    let intent: ProfileClient.DiscoveredIntent
    let onInterested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(intent.vertical).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                Spacer()
                if let geo = intent.geoZone {
                    Text(geo).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.textSecondary)
                }
            }
            Text(title).font(.system(size: 15, weight: .semibold)).kerning(-0.2)
            if let summary = string(for: ["summary", "description", "body"]) {
                Text(summary).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(3)
            }
            HStack {
                if let owner = intent.ownerHandle {
                    Text("@\(owner.alias)").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button(action: onInterested) {
                    Text("Interested").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.white)
                        )
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.cardFill)
        )
    }

    private var title: String {
        string(for: ["title", "display_name", "headline"]) ?? intent.vertical
    }

    private func string(for keys: [String]) -> String? {
        for k in keys {
            if case .string(let s) = intent.fields[k] { return s }
        }
        return nil
    }
}
