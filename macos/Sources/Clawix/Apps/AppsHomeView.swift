import SwiftUI

/// "All apps" landing screen the user reaches from the sidebar Apps
/// section header. Renders the catalog as a grid with filters by
/// project + tag and an inline search box. Each card opens the app
/// in the center pane on click.
struct AppsHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared

    @State private var query: String = ""
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedTag: String = ""
    @State private var sortMode: AppsSortMode = .recent
    @State private var pendingDelete: AppRecord?

    enum AppsSortMode: String, CaseIterable, Identifiable {
        case recent
        case name
        case created

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recent:  return "Recently used"
            case .name:    return "Name"
            case .created: return "Date created"
            }
        }
    }

    private var allTags: [String] {
        let bag = Set(appsStore.apps.flatMap(\.tags))
        return bag.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredApps: [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = appsStore.apps.filter { record in
            if let pid = selectedProjectId, record.projectId != pid { return false }
            if !selectedTag.isEmpty, !record.tags.contains(selectedTag) { return false }
            if !trimmed.isEmpty {
                let haystack = "\(record.name) \(record.description) \(record.tags.joined(separator: " "))".lowercased()
                if !haystack.contains(trimmed) { return false }
            }
            return true
        }
        switch sortMode {
        case .recent:
            return base.sorted(by: { (lhs, rhs) in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                let l = lhs.lastOpenedAt ?? .distantPast
                let r = rhs.lastOpenedAt ?? .distantPast
                if l != r { return l > r }
                return lhs.createdAt > rhs.createdAt
            })
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .created:
            return base.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filterBar
                .padding(.horizontal, 32)
                .padding(.bottom, 18)
            Divider()
                .opacity(0.2)
            ScrollView {
                if filteredApps.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
                    ], spacing: 18) {
                        ForEach(filteredApps) { record in
                            AppCard(record: record) {
                                appState.currentRoute = .app(record.id)
                            } onDelete: {
                                pendingDelete = record
                            }
                        }
                    }
                    .padding(32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    try? appsStore.delete(record)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Mini apps your agent has built")
                    .font(BodyFont.system(size: 13.5, wght: 400))
                    .foregroundColor(Color(white: 0.62))
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundColor(Color(white: 0.92))
                    .frame(width: 200)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            sortMenu
            projectMenu
            tagMenu
            Spacer()
            Text("\(filteredApps.count) of \(appsStore.apps.count)")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.55))
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AppsSortMode.allCases) { mode in
                Button(mode.label) { sortMode = mode }
            }
        } label: {
            FilterChipLabel(text: "Sort: \(sortMode.label)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var projectMenu: some View {
        Menu {
            Button("All projects") { selectedProjectId = nil }
            Divider()
            ForEach(appState.projects) { project in
                Button(project.name) { selectedProjectId = project.id }
            }
        } label: {
            let label = selectedProjectId.flatMap { pid in
                appState.projects.first(where: { $0.id == pid })?.name
            } ?? "All projects"
            FilterChipLabel(text: "Project: \(label)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tagMenu: some View {
        Menu {
            Button("All tags") { selectedTag = "" }
            Divider()
            ForEach(allTags, id: \.self) { tag in
                Button(tag) { selectedTag = tag }
            }
        } label: {
            FilterChipLabel(text: selectedTag.isEmpty ? "Tag: All" : "Tag: \(selectedTag)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundColor(Color(white: 0.45))
            Text(appsStore.apps.isEmpty
                 ? "No apps yet"
                 : "No apps match your filters")
                .font(BodyFont.system(size: 15, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(appsStore.apps.isEmpty
                 ? "Ask the agent: \"Build me a mini app that…\""
                 : "Try clearing the search or filter.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

private struct FilterChipLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(BodyFont.system(size: 12.5, wght: 500))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(Color(white: 0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }
}

private struct AppCard: View {
    let record: AppRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered: Bool = false
    @ObservedObject private var appsStore: AppsStore = .shared

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    iconTile
                        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
                    if record.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name)
                        .font(BodyFont.system(size: 14, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    if !record.description.isEmpty {
                        Text(record.description)
                            .font(BodyFont.system(size: 12.5, wght: 400))
                            .foregroundColor(Color(white: 0.6))
                            .lineLimit(2)
                    }
                    if !record.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(record.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(BodyFont.system(size: 10.5, wght: 500))
                                    .foregroundColor(Color(white: 0.7))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.06))
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(hovered ? 0.20 : 0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(record.pinned ? "Unpin from sidebar" : "Pin to sidebar") {
                appsStore.togglePinned(record)
            }
            Divider()
            Button("Delete app", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var iconTile: some View {
        let bg = AppCard.tileColor(record: record)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [bg.opacity(0.92), bg.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
            if !record.icon.isEmpty {
                Text(record.icon)
                    .font(.system(size: 36))
            } else {
                Text(initials(for: record.name))
                    .font(BodyFont.system(size: 26, wght: 700))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    static func tileColor(record: AppRecord) -> Color {
        if let parsed = Color(appsHex: record.accentColor) {
            return parsed
        }
        // Deterministic color from slug so the catalog has visual variety.
        var hash: UInt64 = 0
        for byte in record.slug.utf8 { hash = hash &* 131 &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.55)
    }
}
