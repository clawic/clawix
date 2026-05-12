import SwiftUI

enum FeedDisplayMode: String, CaseIterable, RawRepresentable {
    case list
    case grid
    case story

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        case .story: return "Story"
        }
    }
}

struct FeedScreen: View {
    @ObservedObject var manager: ProfileManager
    @AppStorage("clawix.feed.displayMode") private var rawMode: String = FeedDisplayMode.list.rawValue
    @State private var verticalFilter: String?

    private var mode: FeedDisplayMode {
        get { FeedDisplayMode(rawValue: rawMode) ?? .list }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.textSecondary.opacity(0.2))
            content
        }
        .background(Color.black)
        .task { await manager.bootstrap() }
        .onChange(of: manager.feedKeywords) { _, _ in
            Task { await manager.refreshFeed() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Feed").font(.system(size: 18, weight: .semibold)).kerning(-0.4)
            Spacer()
            SearchField(text: $manager.feedKeywords, placeholder: "Search peers, posts, tags")
                .frame(width: 280)
            SlidingSegmented(
                selection: Binding(get: { mode }, set: { rawMode = $0.rawValue }),
                options: FeedDisplayMode.allCases.map { ($0, $0.label) },
                height: 28,
            )
            .frame(width: 220)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch manager.loadState {
        case .idle, .loading:
            VStack { ProgressView() }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            VStack(spacing: 8) {
                LucideIcon(.triangleAlert, size: 24)
                Text(msg).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            switch mode {
            case .list: feedList
            case .grid: feedGrid
            case .story: feedStory
            }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.feedEntries) { entry in
                    FeedCardList(entry: entry).padding(.horizontal, 18).padding(.vertical, 10)
                    Divider().background(Palette.textSecondary.opacity(0.1))
                }
            }
        }
        .thinScrollers()
    }

    private var feedGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(manager.feedEntries) { entry in
                    FeedCardGrid(entry: entry)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    private var feedStory: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.feedEntries) { entry in
                    FeedCardStory(entry: entry)
                }
            }
        }
        .thinScrollers()
    }
}

// MARK: - Cards

private struct FeedCardList: View {
    let entry: ClawJSProfileClient.FeedEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HandleAvatar(alias: entry.owner.handle.alias)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("@\(entry.owner.handle.alias)").font(.system(size: 13.5, weight: .semibold)).kerning(-0.2)
                    Text(".\(entry.owner.handle.fingerprint)").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(entry.vertical).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                FeedPreviewText(preview: entry.preview)
            }
        }
    }
}

private struct FeedCardGrid: View {
    let entry: ClawJSProfileClient.FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeedPreviewMedia(preview: entry.preview)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 6) {
                HandleAvatar(alias: entry.owner.handle.alias, size: 24)
                Text("@\(entry.owner.handle.alias)").font(.system(size: 12, weight: .medium)).kerning(-0.2)
                Spacer()
            }
            FeedPreviewText(preview: entry.preview, maxLines: 3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct FeedCardStory: View {
    let entry: ClawJSProfileClient.FeedEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FeedPreviewMedia(preview: entry.preview)
                .frame(height: 520)
                .clipped()
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom,
            )
            .frame(height: 240)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HandleAvatar(alias: entry.owner.handle.alias, size: 28)
                    Text("@\(entry.owner.handle.alias)").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                        .foregroundStyle(.white)
                }
                FeedPreviewText(preview: entry.preview, maxLines: 4)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Inline pieces

private struct HandleAvatar: View {
    let alias: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(Color.white.opacity(0.06))
            Text(initials).font(.system(size: size * 0.42, weight: .semibold)).kerning(-0.4)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let parts = alias.split(separator: "_").flatMap { $0.split(separator: "-") }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(alias.prefix(2)).uppercased()
    }
}

private struct FeedPreviewText: View {
    let preview: [String: AnyJSON]
    var maxLines: Int = 4

    var body: some View {
        if let title = stringValue(for: ["title", "display_name", "headline"]) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).kerning(-0.2)
                if let body = stringValue(for: ["body", "summary", "text", "about"]) {
                    Text(body).font(.system(size: 12.5)).kerning(-0.1)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(maxLines)
                }
            }
        } else if let body = stringValue(for: ["body", "summary", "text", "about"]) {
            Text(body).font(.system(size: 13)).kerning(-0.1).lineLimit(maxLines)
        }
    }

    private func stringValue(for keys: [String]) -> String? {
        for k in keys {
            if case .string(let s) = preview[k] { return s }
        }
        return nil
    }
}

private struct FeedPreviewMedia: View {
    let preview: [String: AnyJSON]

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.04))
            .overlay(
                VStack(spacing: 6) {
                    LucideIcon(.image, size: 22)
                    Text("Media preview").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
            )
    }
}

private struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            LucideIcon(.search, size: 12).foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5),
        )
    }
}
