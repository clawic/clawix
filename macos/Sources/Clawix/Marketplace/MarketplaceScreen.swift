import SwiftUI

enum MarketplaceTab: String, CaseIterable, Identifiable, Hashable {
    case offers
    case wants
    case prospects
    case receipts
    case inbox

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .offers: return "My Offers"
        case .wants: return "My Wants"
        case .prospects: return "Prospects"
        case .receipts: return "Receipts"
        case .inbox: return "Inbox"
        }
    }
}

struct MarketplaceScreen: View {
    @StateObject private var manager = MarketplaceManager()
    @State private var activeTab: MarketplaceTab = .offers

    var body: some View {
        VStack(spacing: 0) {
            MarketplaceHeaderBar(manager: manager, activeTab: $activeTab)
            CardDivider()
            Group {
                switch manager.state {
                case .idle, .loading:
                    MarketplaceLoadingView()
                case .error(let message):
                    MarketplaceEmptyState(
                        title: "Marketplace unavailable",
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
    }

    @ViewBuilder
    private var contentForActiveTab: some View {
        switch activeTab {
        case .offers: MyOffersTab(manager: manager)
        case .wants: MyWantsTab(manager: manager)
        case .prospects: ProspectsTab(manager: manager)
        case .receipts: ReceiptsTab(manager: manager)
        case .inbox: InboxTab(manager: manager)
        }
    }
}

private struct MarketplaceHeaderBar: View {
    @ObservedObject var manager: MarketplaceManager
    @Binding var activeTab: MarketplaceTab

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    LucideIcon.auto("handshake", size: 18)
                        .foregroundColor(.white.opacity(0.9))
                    Text("Marketplace")
                        .font(BodyFont.system(size: 17, wght: 600))
                        .foregroundColor(.white)
                    let unread = manager.inbound.filter { $0.readAt == nil }.count
                    if unread > 0 {
                        Text("\(unread)")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.9)))
                    }
                }
                Spacer()
                Button(action: { Task { await manager.refresh() } }) {
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
                SlidingSegmented<MarketplaceTab>(
                    selection: $activeTab,
                    options: MarketplaceTab.allCases.map { tab in
                        if tab == .inbox {
                            let unread = manager.inbound.filter { $0.readAt == nil }.count
                            if unread > 0 {
                                return (tab, "\(tab.displayName) · \(unread)")
                            }
                        }
                        return (tab, tab.displayName)
                    },
                    height: 30
                )
                .frame(width: 520)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }
}

private struct MarketplaceLoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.regular).tint(.white.opacity(0.7))
            Text("Loading Marketplace…")
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarketplaceEmptyState: View {
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
            Text(description)
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tabs

private struct MyOffersTab: View {
    @ObservedObject var manager: MarketplaceManager
    var body: some View {
        IntentListView(intents: manager.myOffers, role: .offer)
    }
}

private struct MyWantsTab: View {
    @ObservedObject var manager: MarketplaceManager
    var body: some View {
        IntentListView(intents: manager.myWants, role: .want)
    }
}

private struct ProspectsTab: View {
    @ObservedObject var manager: MarketplaceManager
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if manager.peerLevels.isEmpty {
                MarketplaceEmptyState(
                    title: "No prospects yet",
                    systemImage: "users",
                    description: "When a peer reaches out to one of your offers, they appear here with their current trust level."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(manager.peerLevels) { peer in
                            ProspectRow(peer: peer)
                        }
                    }
                    .padding(16)
                }
                .thinScrollers()
            }
        }
    }
}

private struct ReceiptsTab: View {
    @ObservedObject var manager: MarketplaceManager
    var body: some View {
        if manager.receipts.isEmpty {
            MarketplaceEmptyState(
                title: "No match receipts",
                systemImage: "scroll",
                description: "Receipts are signed by both peers after a match. They are the protocol's final artefact; closing the deal happens outside."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                    }
                }
                .padding(16)
            }
            .thinScrollers()
        }
    }
}

private struct InboxTab: View {
    @ObservedObject var manager: MarketplaceManager
    var body: some View {
        if manager.inbound.isEmpty {
            MarketplaceEmptyState(
                title: "Inbox empty",
                systemImage: "inbox",
                description: "Encrypted inquiries from peers about your offers will land here."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(manager.inbound) { message in
                        InboundRow(message: message, onTapRead: {
                            Task { await manager.markRead(messageId: message.id) }
                        })
                    }
                }
                .padding(16)
            }
            .thinScrollers()
        }
    }
}

// MARK: - Rows

private enum IntentRoleHint { case offer, want }

private struct IntentListView: View {
    let intents: [ClawJSMarketplaceClient.Intent]
    let role: IntentRoleHint
    var body: some View {
        if intents.isEmpty {
            MarketplaceEmptyState(
                title: role == .offer ? "No offers published" : "No active searches",
                systemImage: role == .offer ? "tag" : "search",
                description: role == .offer
                    ? "Publish your first offer through a vertical (e.g. real-estate). Until you do, peers cannot find you."
                    : "Define what you are looking for to receive matches from other peers."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(intents) { intent in
                        IntentRow(intent: intent)
                    }
                }
                .padding(16)
            }
            .thinScrollers()
        }
    }
}

private struct IntentRow: View {
    let intent: ClawJSMarketplaceClient.Intent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(intent.vertical)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(.white.opacity(0.55))
                    Text("·")
                        .foregroundColor(.white.opacity(0.30))
                    Text(intent.status)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(intent.status == "published" ? .green.opacity(0.75) : .white.opacity(0.45))
                    if intent.provenance == "native" {
                        Text("verified")
                            .font(BodyFont.system(size: 10, wght: 600))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule(style: .continuous).fill(Color.green.opacity(0.30)))
                    } else {
                        Text("observed")
                            .font(BodyFont.system(size: 10, wght: 600))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule(style: .continuous).fill(Color.gray.opacity(0.30)))
                    }
                }
                let title = intent.payload.string("title") ?? intent.payload.string("summary") ?? intent.id
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 600))
                    .foregroundColor(.white.opacity(0.92))
                if let summary = intent.payload.string("summary") {
                    Text(summary)
                        .font(BodyFont.system(size: 12, wght: 400))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let geo = intent.payload.string("geo_zone") {
                        Tag(text: geo, color: .blue)
                    }
                    if let price = intent.payload.number("price_eur") {
                        Tag(text: "€\(Int(price))", color: .orange)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct ProspectRow: View {
    let peer: ClawJSMarketplaceClient.PeerLevel
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Text("L\(peer.currentLevel)")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white.opacity(0.88))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(peer.peerPubkey.prefix(16)) + "…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(.white.opacity(0.88))
                Text("Last update " + peer.lastUpdatedAt.prefix(16))
                    .font(BodyFont.system(size: 11, wght: 400))
                    .foregroundColor(.white.opacity(0.50))
            }
            Spacer()
            ProgressView(value: Double(peer.currentLevel) / 5.0)
                .progressViewStyle(.linear)
                .frame(width: 120)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct ReceiptRow: View {
    let receipt: ClawJSMarketplaceClient.MatchReceipt
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon.auto("scroll", size: 16)
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(receipt.status)
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(receiptColor(receipt.status))
                    Text("·")
                        .foregroundColor(.white.opacity(0.30))
                    Text("level \(receipt.reachedLevel)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text("Peer " + receipt.peerRolePubkey.prefix(16) + "…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(.white.opacity(0.88))
                if !receipt.fieldsRevealed.isEmpty {
                    Text("Revealed: " + receipt.fieldsRevealed.joined(separator: ", "))
                        .font(BodyFont.system(size: 11, wght: 400))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func receiptColor(_ status: String) -> Color {
        switch status {
        case "signed": return .green.opacity(0.85)
        case "awaiting_human_approval", "proposed_by_peer": return .orange.opacity(0.85)
        case "rejected", "expired": return .red.opacity(0.70)
        default: return .white.opacity(0.70)
        }
    }
}

private struct InboundRow: View {
    let message: ClawJSMarketplaceClient.InboundMessage
    let onTapRead: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.readAt == nil ? Color.orange.opacity(0.85) : Color.white.opacity(0.20))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.kind)
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(.white.opacity(0.75))
                    Text("·")
                        .foregroundColor(.white.opacity(0.30))
                    Text(message.receivedAt.prefix(16))
                        .font(BodyFont.system(size: 11, wght: 400))
                        .foregroundColor(.white.opacity(0.50))
                }
                Text(String(message.senderPubkey.prefix(20)) + "…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(.white.opacity(0.88))
                if let text = message.plaintext.string("text") {
                    Text(text)
                        .font(BodyFont.system(size: 12, wght: 400))
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(3)
                }
            }
            Spacer()
            if message.readAt == nil {
                Button("Mark read", action: onTapRead)
                    .buttonStyle(.plain)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(message.readAt == nil ? 0.06 : 0.03))
        )
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 10, wght: 600))
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(color.opacity(0.30)))
    }
}
