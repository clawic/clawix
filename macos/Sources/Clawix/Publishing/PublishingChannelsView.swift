import SwiftUI

/// Lists every channel family the registry knows about, grouped by
/// `ChannelGroup`. Families with a real adapter (`bluesky`, `mastodon`,
/// `devnull`) expose a "Connect" CTA that opens `PublishingConnectSheet`;
/// skeleton families are marked "Coming soon" and are non-interactive.
/// Connected accounts surface a "Connected - @handle" badge on the right;
/// the menu on that badge offers "Probe" and "Disconnect".
struct PublishingChannelsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var manager: PublishingManager
    @State private var connectFamily: ClawJSPublishingClient.Family?

    private static let connectableFamilies: Set<String> = ["bluesky", "mastodon", "devnull"]

    private var grouped: [(group: String, families: [ClawJSPublishingClient.Family])] {
        let order = [
            "social", "chat", "long_form", "forum", "forum_federated",
            "feed", "email", "video", "audio", "event", "dev", "doc", "generic",
        ]
        let byGroup = Dictionary(grouping: manager.families, by: { $0.group })
        return order.compactMap { key in
            guard let entries = byGroup[key], !entries.isEmpty else { return nil }
            return (key, entries.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch manager.state {
            case .ready:
                content
            case .bootstrapping, .idle:
                placeholder("Loading channels...")
            case .unavailable(let reason):
                placeholder(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .sheet(item: $connectFamily) { family in
            PublishingConnectSheet(family: family) { connectFamily = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(grouped, id: \.group) { entry in
                    Text(verbatim: groupName(entry.group))
                        .font(BodyFont.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(entry.families) { family in
                            row(for: family)
                            if family.id != entry.families.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .padding(.horizontal, 18)
                    )
                }
            }
            .padding(.vertical, 18)
        }
        .thinScrollers()
    }

    @ViewBuilder
    private func row(for family: ClawJSPublishingClient.Family) -> some View {
        let connectedAccount = manager.channels.first { $0.familyId == family.id }
        let canConnect = Self.connectableFamilies.contains(family.id)
        HStack(alignment: .center, spacing: 12) {
            iconBubble(for: family.group)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: family.name)
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: family.group.replacingOccurrences(of: "_", with: " "))
                    .font(BodyFont.system(size: 10.5, weight: .medium))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 12)
            if let account = connectedAccount {
                connectedBadge(account: account)
            } else if canConnect {
                Button {
                    connectFamily = family
                } label: {
                    Text(verbatim: "Connect")
                        .font(BodyFont.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                        )
                        .foregroundColor(Palette.textPrimary)
                }
                .buttonStyle(.plain)
            } else {
                Text(verbatim: "Coming soon")
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                    .foregroundColor(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func systemIconName(for group: String) -> String {
        switch group {
        case "social":           return "megaphone"
        case "chat":             return "bubble.left"
        case "long_form":        return "book"
        case "forum",
             "forum_federated": return "bubble.left.and.bubble.right"
        case "feed":             return "list.bullet"
        case "email":            return "envelope"
        case "video":            return "video"
        case "audio":            return "waveform"
        case "event":            return "calendar"
        case "dev":              return "chevron.left.forwardslash.chevron.right"
        case "doc":              return "doc.text"
        default:                 return "circle.grid.2x2"
        }
    }

    @ViewBuilder
    private func iconBubble(for group: String) -> some View {
        Image(systemName: systemIconName(for: group))
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Palette.textPrimary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }

    @ViewBuilder
    private func connectedBadge(account: ClawJSPublishingClient.ChannelAccount) -> some View {
        Menu {
            Button("Probe health") {
                Task { await manager.probe(account: account) }
            }
            Button("Disconnect", role: .destructive) {
                Task { await manager.disconnect(account: account) }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(account.authorized ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(verbatim: handleLabel(account))
                    .font(BodyFont.system(size: 11, weight: .medium))
                    .foregroundColor(Color.green.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.green.opacity(0.18))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func handleLabel(_ account: ClawJSPublishingClient.ChannelAccount) -> String {
        if let handle = account.handle, !handle.isEmpty {
            return "Connected - @\(handle)"
        }
        return "Connected - \(account.displayName)"
    }

    private func groupName(_ raw: String) -> String {
        switch raw {
        case "social":          return "Social"
        case "chat":            return "Chat"
        case "long_form":       return "Long form"
        case "forum":           return "Forum"
        case "forum_federated": return "Federated forum"
        case "feed":            return "Feed"
        case "email":           return "Email"
        case "video":           return "Video"
        case "audio":           return "Audio"
        case "event":           return "Event"
        case "dev":             return "Developer"
        case "doc":             return "Documentation"
        default:                return raw.capitalized
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "megaphone")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Palette.textTertiary)
            Text(verbatim: message)
                .font(BodyFont.system(size: 12.5, weight: .medium))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if case .unavailable = manager.state {
                Button("Retry") {
                    Task { @MainActor in
                        await ClawJSServiceManager.shared.restart(.publishing)
                    }
                }
                .buttonStyle(.borderless)
                .font(BodyFont.system(size: 12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
