import SwiftUI
import ClawixCore

// Home surface. Two-section scroll over a pure-black canvas with
// floating Liquid Glass chrome:
//
//   - Top bar (floating, Liquid Glass): connection-status pill on
//     the left, then a morphing cluster on the right that swaps
//     between [search · menu icons] and [search field · close]
//     depending on whether the user has tapped the magnifier.
//   - Title block "Clawix" + connection subtitle.
//   - "Projects" section: chats grouped by their `cwd` (the working
//     directory the agent is operating in on the Mac). Folder rows,
//     prefix five, "See all" sheet for the rest.
//   - "Chats" section: bare-text rows à la ChatGPT iOS, with the
//     same swipe-to-delete gesture and active-turn indicator the
//     previous list had.
//
// All section animation is driven by `withAnimation(...)` on the
// search toggle so the morph reads as one Liquid-Glass change.

struct ChatListView: View {
    @Bindable var store: BridgeStore
    let onOpen: (String) -> Void
    let onOpenProject: (String) -> Void
    let onUnpair: () -> Void

    @State private var searchActive: Bool = false
    @State private var searchText: String = ""
    @State private var showAllProjects = false
    @FocusState private var searchFocused: Bool

    private let visibleProjectCount = 5

    private var visibleChats: [WireChat] {
        store.chats
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let l = lhs.lastMessageAt ?? lhs.createdAt
                let r = rhs.lastMessageAt ?? rhs.createdAt
                return l > r
            }
    }

    private var projects: [DerivedProject] {
        DerivedProject.from(chats: visibleChats)
    }

    private var isSearching: Bool {
        searchActive && !searchText.isEmpty
    }

    private var filteredChats: [WireChat] {
        guard isSearching else { return visibleChats }
        let q = searchText.lowercased()
        return visibleChats.filter { chat in
            chat.title.lowercased().contains(q)
            || (chat.lastMessagePreview?.lowercased().contains(q) ?? false)
            || (chat.cwd?.lowercased().contains(q) ?? false)
        }
    }

    private var filteredProjects: [DerivedProject] {
        guard isSearching else { return projects }
        let q = searchText.lowercased()
        return projects.filter { $0.name.lowercased().contains(q) || $0.cwd.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !isSearching {
                    titleBlock
                        .padding(.horizontal, AppLayout.screenHorizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                } else {
                    Color.clear.frame(height: 8)
                }

                if isSearching {
                    searchResults
                } else {
                    projectsSection
                    chatsSection
                }

                Color.clear.frame(height: 80)
            }
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAllProjects) {
            AllProjectsSheet(
                projects: projects,
                onSelect: { project in
                    showAllProjects = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onOpenProject(project.cwd)
                    }
                },
                onDismiss: { showAllProjects = false }
            )
        }
    }

    // MARK: Top bar (floating glass)

    private var topBar: some View {
        HStack(spacing: 10) {
            if !searchActive {
                statusPill
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
            }

            Spacer(minLength: 0)

            if searchActive {
                searchFieldPill
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            } else {
                HStack(spacing: 6) {
                    GlassIconButton(action: {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            searchActive = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            searchFocused = true
                        }
                    }) {
                        SearchIcon(size: 18)
                    }
                    GlassIconButton(systemName: "personalhotspot.slash", action: onUnpair)
                }
                .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: searchActive)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            connectionDot
            Text(connectionShort)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.topBarPillHeight)
        .glassCapsule()
    }

    private var searchFieldPill: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 16)
                .foregroundStyle(Palette.textSecondary)
            TextField("Search", text: $searchText)
                .font(.system(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .tint(Color.white)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFocused)
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    searchActive = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: AppLayout.topBarPillHeight)
        .glassCapsule()
    }

    private var connectionDot: some View {
        let color: Color
        switch store.connection {
        case .connected: color = Color(red: 0.30, green: 0.78, blue: 0.45)
        case .connecting: color = Color(red: 0.95, green: 0.78, blue: 0.30)
        case .error:      color = Color(red: 0.85, green: 0.30, blue: 0.30)
        case .unpaired:   color = Palette.textTertiary
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func connectedSubtitle(macName: String, route: BridgeStore.Route?) -> String {
        switch route {
        case .tailscale: return "Connected to \(macName) via Tailscale"
        case .lan, .none: return "Connected to \(macName)"
        }
    }

    private var connectionShort: String {
        switch store.connection {
        case .unpaired:
            return "Not paired"
        case .connecting:
            return "Connecting"
        case .connected(let macName, let route):
            let base = macName ?? "Connected"
            return route == .tailscale ? "\(base) · TS" : base
        case .error:
            return "Disconnected"
        }
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clawix")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            if case .connected(let macName, let route) = store.connection, let macName {
                Text(connectedSubtitle(macName: macName, route: route))
                    .font(Typography.secondaryFont)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    // MARK: Projects section

    @ViewBuilder
    private var projectsSection: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Projects")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 4)

                ForEach(projects.prefix(visibleProjectCount)) { project in
                    Button {
                        onOpenProject(project.cwd)
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                }

                if projects.count > visibleProjectCount {
                    Button {
                        showAllProjects = true
                    } label: {
                        HStack {
                            Text("See all")
                                .font(Typography.secondaryFont)
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, AppLayout.screenHorizontalPadding)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 18)
        }
    }

    // MARK: Chats section

    @ViewBuilder
    private var chatsSection: some View {
        if !visibleChats.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Chats")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 6)

                ForEach(Array(visibleChats.enumerated()), id: \.element.id) { index, chat in
                    chatRowButton(chat)
                    if index < visibleChats.count - 1 {
                        Rectangle()
                            .fill(Palette.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, AppLayout.screenHorizontalPadding)
                    }
                }
            }
        }
    }

    // MARK: Search results

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !filteredProjects.isEmpty {
                sectionHeader("Projects")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 4)
                ForEach(filteredProjects) { project in
                    Button {
                        onOpenProject(project.cwd)
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 18)
            }

            if !filteredChats.isEmpty {
                sectionHeader("Chats")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 6)
                ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                    chatRowButton(chat)
                    if index < filteredChats.count - 1 {
                        Rectangle()
                            .fill(Palette.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, AppLayout.screenHorizontalPadding)
                    }
                }
            }

            if filteredProjects.isEmpty && filteredChats.isEmpty {
                VStack(spacing: 8) {
                    SearchIcon(size: 32)
                        .foregroundStyle(Palette.textTertiary)
                    Text("No matches for \"\(searchText)\"")
                        .font(Typography.secondaryFont)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, 8)
    }

    private func chatRowButton(_ chat: WireChat) -> some View {
        Button {
            onOpen(chat.id)
        } label: {
            ChatRow(chat: chat)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Derived project (chats grouped by cwd)

struct DerivedProject: Identifiable, Hashable {
    let cwd: String
    let chats: [WireChat]
    var id: String { cwd }
    var name: String {
        let comp = (cwd as NSString).lastPathComponent
        return comp.isEmpty ? cwd : comp
    }
    var lastActivity: Date {
        chats.map { $0.lastMessageAt ?? $0.createdAt }.max() ?? .distantPast
    }
    var hasActiveTurn: Bool {
        chats.contains(where: { $0.hasActiveTurn })
    }

    // `WireChat` is Equatable but not Hashable, so we collapse the
    // identity to the cwd (which is what defines a project here).
    static func == (lhs: DerivedProject, rhs: DerivedProject) -> Bool {
        lhs.cwd == rhs.cwd
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(cwd)
    }

    static func from(chats: [WireChat]) -> [DerivedProject] {
        let grouped = Dictionary(grouping: chats.compactMap { chat -> (String, WireChat)? in
            guard let cwd = chat.cwd, !cwd.isEmpty else { return nil }
            return (cwd, chat)
        }, by: { $0.0 })
        let projects = grouped.map { (cwd, pairs) in
            DerivedProject(cwd: cwd, chats: pairs.map { $0.1 })
        }
        return projects.sorted { $0.lastActivity > $1.lastActivity }
    }
}

// MARK: - Project row

private struct ProjectRow: View {
    let project: DerivedProject

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.cardFill)
                    .frame(width: 38, height: 38)
                FolderClosedIcon(size: 18)
                    .foregroundStyle(Palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(project.chats.count) chat\(project.chats.count == 1 ? "" : "s")")
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if project.hasActiveTurn {
                Circle()
                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                    .frame(width: 6, height: 6)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Chat row

struct ChatRow: View {
    let chat: WireChat

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if chat.isPinned {
                        PinIcon(size: 11)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(chat.title)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                if let preview = chat.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(Typography.secondaryFont)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                if chat.hasActiveTurn || chat.branch != nil {
                    HStack(spacing: 8) {
                        if chat.hasActiveTurn {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                                    .frame(width: 6, height: 6)
                                Text("Working")
                                    .font(Typography.captionFont)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                        if let branch = chat.branch {
                            HStack(spacing: 4) {
                                BranchIcon(size: 11)
                                    .foregroundStyle(Palette.textTertiary)
                                Text(branch)
                                    .font(Typography.captionFont)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Text(timeLabel)
                .font(Typography.captionFont)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 14)
    }

    private var timeLabel: String {
        let date = chat.lastMessageAt ?? chat.createdAt
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        let days = Int(interval / 86_400)
        if days < 7 { return "\(days)d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - All projects sheet

private struct AllProjectsSheet: View {
    let projects: [DerivedProject]
    let onSelect: (DerivedProject) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 12)
                        ForEach(projects) { project in
                            Button {
                                onSelect(project)
                            } label: {
                                ProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                        Color.clear.frame(height: 40)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Chat list") {
    ChatListView(
        store: BridgeStore.mock(),
        onOpen: { _ in },
        onOpenProject: { _ in },
        onUnpair: {}
    )
    .preferredColorScheme(.dark)
}
