import SwiftUI

/// marketplace/2.0.0 marketplace surface. Replaces the legacy `/v1/marketplace/intents` view
/// with the new `/v1/marketplace/discovered-intents` and `/v1/profile/blocks`
/// flows. The legacy `MarketplaceScreen` is kept available behind a
/// settings toggle while users migrate.
struct MarketplaceScreenV2: View {
    @ObservedObject var manager: ProfileManager
    @State private var selectedTab: Tab = .discover

    enum Tab: String, CaseIterable {
        case discover, myListings, inquiries

        var label: String {
            switch self {
            case .discover: return "Discover"
            case .myListings: return "My listings"
            case .inquiries: return "Inquiries"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .background(Color.black)
        .task {
            await manager.bootstrap()
            await manager.refreshMarketplace()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Marketplace").font(.system(size: 18, weight: .semibold)).kerning(-0.4)
            Spacer()
            SlidingSegmented(
                selection: $selectedTab,
                options: Tab.allCases.map { ($0, $0.label) },
                height: 28,
            )
            .frame(width: 280)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .discover: discoverTab
        case .myListings: listingsTab
        case .inquiries: inquiriesTab
        }
    }

    private var discoverTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(manager.marketplaceIntents) { intent in
                    DiscoveredIntentCard(intent: intent) {
                        Task { _ = try? await manager.expressInterest(intentId: intent.intentId) }
                    }
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    private var listingsTab: some View {
        let listings = manager.ownBlocks.filter { isMarketplaceVertical($0.vertical) }
        return ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(listings) { block in
                    OwnListingRow(block: block)
                }
                if listings.isEmpty {
                    Text("No listings yet. Use the Profile editor to publish one.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    private var inquiriesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(manager.chatThreads) { thread in
                    HStack(spacing: 8) {
                        LucideIcon(.inbox, size: 13).foregroundStyle(Palette.textSecondary)
                        Text("@\(thread.peer.handle.alias)").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(String(thread.unreadCount)).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    private func isMarketplaceVertical(_ id: String) -> Bool {
        ["item/v1", "service-offer/v1", "real-estate/v1", "vehicle/v1", "meetup/v1"].contains(id)
    }
}

private struct DiscoveredIntentCard: View {
    let intent: ClawJSProfileClient.DiscoveredIntent
    let onInterested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(intent.vertical).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                Spacer()
                if let geo = intent.geoZone {
                    Text(geo).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.textSecondary)
                }
            }
            Text(title).font(.system(size: 13.5, weight: .semibold)).kerning(-0.2).lineLimit(2)
            if let summary = stringValue(for: ["summary", "description", "body"]) {
                Text(summary).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(3)
            }
            Spacer(minLength: 4)
            HStack {
                if let owner = intent.ownerHandle {
                    Text("@\(owner.alias)").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button("Interested") { onInterested() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var title: String {
        stringValue(for: ["title", "display_name", "headline"]) ?? intent.vertical
    }

    private func stringValue(for keys: [String]) -> String? {
        for k in keys {
            if case .string(let s) = intent.fields[k] { return s }
        }
        return nil
    }
}

private struct OwnListingRow: View {
    let block: ClawJSProfileClient.Block

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.vertical).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Text(title).font(.system(size: 13, weight: .medium)).kerning(-0.2)
            }
            Spacer()
            Text("v\(block.version)").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var title: String {
        guard let overlay = block.overlay ?? block.content else { return block.blockId }
        for k in ["title", "display_name", "headline", "body"] {
            if case .string(let s) = overlay[k] { return s }
        }
        return block.blockId
    }
}
