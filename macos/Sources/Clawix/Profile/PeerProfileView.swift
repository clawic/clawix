import SwiftUI

struct PeerProfileView: View {
    let peer: ClawJSProfileClient.PeerDirectoryEntry
    @ObservedObject var manager: ProfileManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider().background(Color.white.opacity(0.06))
                feedSection
            }
            .padding(20)
        }
        .thinScrollers()
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Text(initials).font(.system(size: 22, weight: .semibold)).kerning(-0.4)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(peer.handle.alias)").font(.system(size: 18, weight: .semibold)).kerning(-0.4)
                Text("." + peer.handle.fingerprint).font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary).textSelection(.enabled)
                if peer.trustedLocally {
                    HStack(spacing: 4) {
                        LucideIcon(.badgeCheck, size: 11)
                        Text("Locally trusted").font(.system(size: 11)).kerning(-0.1)
                    }
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Message") { /* opens P2PChatScreen filtered to peer */ }
                    .buttonStyle(.borderedProminent)
                Button("Add to group") { /* group picker popup */ }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible blocks").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
            let entries = manager.feedEntries.filter { $0.owner.handle.fingerprint == peer.handle.fingerprint }
            if entries.isEmpty {
                Text("Nothing visible at your current audience tier.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.vertical).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        Text(previewString(entry: entry)).font(.system(size: 13)).lineLimit(3)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
    }

    private var initials: String {
        let parts = peer.handle.alias.split(separator: "_").flatMap { $0.split(separator: "-") }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(peer.handle.alias.prefix(2)).uppercased()
    }

    private func previewString(entry: ClawJSProfileClient.FeedEntry) -> String {
        for key in ["title", "display_name", "headline", "body", "summary"] {
            if case .string(let s) = entry.preview[key] { return s }
        }
        return "(preview unavailable)"
    }
}
