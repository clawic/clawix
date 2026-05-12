import SwiftUI

struct FeedView: View {
    @ObservedObject var store: ProfileStore
    @AppStorage("clawix.feed.displayMode") private var rawMode: String = "list"

    enum Mode: String, CaseIterable, Identifiable {
        case list, grid, story
        var id: String { rawValue }
        var label: String {
            switch self { case .list: "List"; case .grid: "Grid"; case .story: "Story" }
        }
    }

    private var mode: Mode { Mode(rawValue: rawMode) ?? .list }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeToggle.padding(.horizontal, 16).padding(.vertical, 10)
                content
            }
            .navigationTitle("Feed")
            .background(Palette.background)
            .task { if store.feed.isEmpty { await store.bootstrap() } }
            .refreshable { await store.refreshFeed() }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { m in
                Button(action: { rawMode = m.rawValue }) {
                    Text(m.label).font(.system(size: 13, weight: m == mode ? .semibold : .regular))
                        .kerning(-0.2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(m == mode ? Color.white.opacity(0.12) : .clear)
                        )
                        .foregroundStyle(m == mode ? Palette.textPrimary : Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 8) {
                LucideIcon(.triangleAlert, size: 22)
                Text(message).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            switch mode {
            case .list: list
            case .grid: grid
            case .story: story
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.feed) { entry in
                    FeedRow(entry: entry).padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().background(Palette.borderSubtle)
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(store.feed) { entry in FeedTile(entry: entry) }
            }
            .padding(16)
        }
    }

    private var story: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(store.feed) { entry in FeedStory(entry: entry) }
            }
        }
    }
}

private struct FeedRow: View {
    let entry: ProfileClient.FeedEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HandleAvatar(alias: entry.owner.handle.alias, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("@\(entry.owner.handle.alias)").font(.system(size: 14, weight: .semibold)).kerning(-0.2)
                    Text(".\(entry.owner.handle.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(entry.vertical).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                if let title = previewString(entry.preview, keys: ["title", "headline", "display_name"]) {
                    Text(title).font(.system(size: 14, weight: .semibold)).kerning(-0.2)
                }
                if let body = previewString(entry.preview, keys: ["body", "summary", "text"]) {
                    Text(body).font(.system(size: 13)).foregroundStyle(Palette.textPrimary.opacity(0.9))
                        .lineLimit(4)
                }
            }
        }
    }
}

private struct FeedTile: View {
    let entry: ProfileClient.FeedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                LucideIcon(.image, size: 26).foregroundStyle(Palette.textSecondary)
            }
            .frame(height: 160)
            HStack(spacing: 6) {
                HandleAvatar(alias: entry.owner.handle.alias, size: 22)
                Text("@\(entry.owner.handle.alias)").font(.system(size: 12, weight: .medium)).kerning(-0.2)
                Spacer()
            }
            if let title = previewString(entry.preview, keys: ["title", "headline", "display_name"]) {
                Text(title).font(.system(size: 13, weight: .semibold)).kerning(-0.2).lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.cardFill)
        )
    }
}

private struct FeedStory: View {
    let entry: ProfileClient.FeedEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.white.opacity(0.05))
                .frame(height: 540)
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom,
            )
            .frame(height: 200)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HandleAvatar(alias: entry.owner.handle.alias, size: 26)
                    Text("@\(entry.owner.handle.alias)").font(.system(size: 13, weight: .semibold)).kerning(-0.2).foregroundStyle(.white)
                }
                if let title = previewString(entry.preview, keys: ["title", "headline", "display_name"]) {
                    Text(title).font(.system(size: 16, weight: .semibold)).kerning(-0.2).foregroundStyle(.white)
                }
                if let body = previewString(entry.preview, keys: ["body", "summary", "text"]) {
                    Text(body).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)).lineLimit(4)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 28)
        }
    }
}

private struct HandleAvatar: View {
    let alias: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(Color.white.opacity(0.08))
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

private func previewString(_ preview: [String: AnyValue], keys: [String]) -> String? {
    for k in keys {
        if case .string(let s) = preview[k] { return s }
    }
    return nil
}
