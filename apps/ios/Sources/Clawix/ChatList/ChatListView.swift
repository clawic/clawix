import SwiftUI
import ClawixCore

// Home surface. Two-section scroll over a pure-black canvas with
// floating Liquid Glass chrome:
//
//   - Top bar (floating, Liquid Glass): "Clawix" wordmark on the
//     left, search and Settings buttons on the right. The search
//     button morphs into a search field when tapped. Connection
//     state lives entirely inside the Settings sheet.
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
    let onPair: (Credentials) -> Void
    let onUnpair: () -> Void
    var onNewChat: () -> Void = {}

    @State private var searchActive: Bool = false
    @State private var searchText: String = ""
    @State private var showAllProjects = false
    @State private var showSettings = false
    @State private var searchChatLimit: Int = 20
    @FocusState private var searchFocused: Bool

    private let visibleProjectCount = 5
    private let searchChatLimitInitial = 20
    private let searchChatLimitStep = 20
    private let searchProjectLimit = 8

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
        return projects.filter { project in
            let label = store.projectDisplayName(cwd: project.cwd, fallback: project.name).lowercased()
            return label.contains(q)
                || project.name.lowercased().contains(q)
                || project.cwd.lowercased().contains(q)
        }
    }

    private var displayedFilteredChats: [WireChat] {
        Array(filteredChats.prefix(searchChatLimit))
    }

    private var displayedFilteredProjects: [DerivedProject] {
        Array(filteredProjects.prefix(searchProjectLimit))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 20).id("top")

                    if isSearching {
                        searchResults
                    } else {
                        projectsSection
                        chatsSection
                        if projects.isEmpty && visibleChats.isEmpty {
                            emptyStateSection
                        }
                    }

                    Color.clear.frame(height: 80)
                }
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: searchActive) { _, _ in
                searchChatLimit = searchChatLimitInitial
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: searchText) { _, _ in
                searchChatLimit = searchChatLimitInitial
            }
            .onChange(of: isSearching) { _, _ in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .topBarBlurFade(height: 135)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 1)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            NewChatFAB(action: onNewChat)
                .padding(.trailing, AppLayout.screenHorizontalPadding)
                .padding(.bottom, 22)
        }
        .sheet(isPresented: $showAllProjects) {
            AllProjectsSheet(
                projects: projects,
                store: store,
                onSelect: { project in
                    showAllProjects = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onOpenProject(project.cwd)
                    }
                },
                onDismiss: { showAllProjects = false }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                store: store,
                onPair: { creds in
                    showSettings = false
                    onPair(creds)
                },
                onUnpair: {
                    showSettings = false
                    onUnpair()
                },
                onDismiss: { showSettings = false }
            )
        }
    }

    // MARK: Top bar (floating glass)

    private var topBar: some View {
        HStack(spacing: 10) {
            if searchActive {
                searchInputPill
                    .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                searchCloseCircle
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            } else {
                Text("Clawix")
                    .font(AppFont.system(size: 23, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))

                Spacer(minLength: 0)

                actionPill
                    .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: searchActive)
    }

    // Single Liquid Glass capsule that hosts the two top-bar actions
    // side by side. Each button is a plain Button with the glass
    // applied to the parent HStack so taps reach the underlying
    // gesture surface (the iOS 26 quirk that swallows taps when
    // `.glassEffect` is layered on top of `.buttonStyle(.plain)` is
    // why the glass goes on the container, not on the buttons).
    private var actionPill: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                SearchIcon(size: 20)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstantPressButtonStyle {
                guard !searchActive else { return }
                Haptics.tap()
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    searchActive = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    searchFocused = true
                }
            })

            Button(action: {}) {
                SettingsIcon(size: 28, lineWidth: 2.0)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstantPressButtonStyle {
                guard !showSettings else { return }
                Haptics.tap()
                showSettings = true
            })
        }
        .glassCapsule()
    }

    private var searchInputPill: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 16)
                .foregroundStyle(Palette.textSecondary)
            TextField("Search", text: $searchText)
                .font(BodyFont.system(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .tint(Color.white)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        searchText = ""
                    }
                } label: {
                    CloseChipIcon(size: 14, lineWidth: 2.8)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .glassCapsule()
    }

    private var searchCloseCircle: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                searchActive = false
                searchText = ""
                searchFocused = false
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Circle())
                CloseIcon(size: 27, lineWidth: 2.1)
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Projects section

    @ViewBuilder
    private var projectsSection: some View {
        if !projects.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Projects")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 12)

                ForEach(projects.prefix(visibleProjectCount)) { project in
                    Button {
                        Haptics.tap()
                        onOpenProject(project.cwd)
                    } label: {
                        ProjectRow(
                            project: project,
                            displayName: store.projectDisplayName(cwd: project.cwd, fallback: project.name)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if projects.count > visibleProjectCount {
                    Button {
                        Haptics.tap()
                        showAllProjects = true
                    } label: {
                        HStack(spacing: 12) {
                            LucideIcon(.ellipsis, size: 29)
                                .foregroundStyle(Palette.textPrimary)
                                .frame(width: 24, alignment: .center)
                            Text("See more")
                                .font(Typography.bodyFont)
                                .foregroundStyle(Palette.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, AppLayout.screenHorizontalPadding)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Chats section

    @ViewBuilder
    private var chatsSection: some View {
        if !visibleChats.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Chats")
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.bottom, 12)

                ForEach(visibleChats) { chat in
                    chatRowButton(chat)
                }
            }
        }
    }

    // MARK: Search results

    // Headerless: projects first, then chats. The matched substring
    // is bolded inside the title; chat rows additionally show a
    // snippet of the source field where the match was found, with
    // the matched word brightened against a dimmed snippet.
    @ViewBuilder
    private var searchResults: some View {
        let projectsShown = displayedFilteredProjects
        let chatsShown = displayedFilteredChats
        let lastChatId = chatsShown.last?.id

        VStack(alignment: .leading, spacing: 0) {
            if !projectsShown.isEmpty {
                ForEach(projectsShown) { project in
                    Button {
                        Haptics.tap()
                        onOpenProject(project.cwd)
                    } label: {
                        SearchProjectRow(
                            project: project,
                            displayName: store.projectDisplayName(cwd: project.cwd, fallback: project.name),
                            query: searchText
                        )
                    }
                    .buttonStyle(.plain)
                }
                if !chatsShown.isEmpty {
                    Color.clear.frame(height: 6)
                }
            }

            if !chatsShown.isEmpty {
                ForEach(chatsShown) { chat in
                    Button {
                        Haptics.tap()
                        onOpen(chat.id)
                    } label: {
                        SearchChatRow(chat: chat, query: searchText)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        // Auto-paginate: when the last currently-rendered
                        // chat row enters the viewport, extend the cap so
                        // the next chunk streams in without a tap.
                        guard chat.id == lastChatId else { return }
                        guard filteredChats.count > searchChatLimit else { return }
                        searchChatLimit += searchChatLimitStep
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

    // MARK: Empty / loading / error placeholder

    /// Renders when the chat list is empty. Picks one of three
    /// states from `store`:
    ///   • bridge syncing → "Sincronizando con tu Mac…" + spinner
    ///   • bridge error   → tarjeta con el motivo y subtítulo de ayuda
    ///   • bridge ready   → empty state real ("No tienes chats todavía")
    /// Centred vertically inside the scroll view so the placeholder
    /// reads as a screen state, not a list row.
    @ViewBuilder
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 120)
            Group {
                if case .error(let message) = store.bridgeSync {
                    placeholderError(message: message)
                } else if store.isBridgeSyncing() {
                    placeholderSyncing
                } else {
                    placeholderEmpty
                }
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
    }

    private var placeholderSyncing: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(Palette.textTertiary)
            Text("Sincronizando con tu Mac…")
                .font(BodyFont.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Text("Cargando tus chats por primera vez")
                .font(BodyFont.system(size: 14))
                .tracking(-0.2)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var placeholderEmpty: some View {
        VStack(spacing: 12) {
            Text("Aún no tienes chats")
                .font(BodyFont.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Text("Empieza una conversación desde tu Mac y aparecerá aquí.")
                .font(BodyFont.system(size: 14))
                .tracking(-0.2)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func placeholderError(message: String) -> some View {
        VStack(spacing: 12) {
            Text("No se pudo conectar con tu Mac")
                .font(BodyFont.system(size: 17, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(BodyFont.system(size: 14))
                .tracking(-0.2)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(BodyFont.system(size: 18, weight: .bold))
            .tracking(-0.4)
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, 8)
    }

    private func chatRowButton(_ chat: WireChat) -> some View {
        Button {
            Haptics.tap()
            onOpen(chat.id)
        } label: {
            ChatRow(chat: chat, isUnread: store.isUnread(chatId: chat.id))
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
    let displayName: String

    var body: some View {
        HStack(spacing: 12) {
            FolderClosedIcon(size: 20)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 24, alignment: .center)
            Text(displayName)
                .font(BodyFont.system(size: 17))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            if project.hasActiveTurn {
                Circle()
                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Chat row

struct ChatRow: View {
    let chat: WireChat
    /// `true` when the chat finished its last assistant turn while the
    /// user wasn't viewing it. Drives the soft-blue dot pinned to the
    /// trailing edge. Owned by `BridgeStore.unreadChatIds`; the call
    /// site reads it once so we don't pull the whole store into the
    /// row's observation graph.
    var isUnread: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            titleView
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsUnreadDot {
                Circle()
                    .fill(Palette.unreadDot)
                    .frame(width: 8, height: 8)
                    .transition(.scale(scale: 0.0, anchor: .center).combined(with: .opacity))
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: chat.hasActiveTurn)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: showsUnreadDot)
    }

    @ViewBuilder
    private var titleView: some View {
        if chat.hasActiveTurn {
            ChatTitleShimmer(text: chat.title)
        } else {
            Text(chat.title)
                .font(BodyFont.system(size: 17))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
    }

    private var showsUnreadDot: Bool {
        isUnread && !chat.hasActiveTurn
    }
}

// MARK: - Search rows
//
// Variants of the project / chat rows that highlight the matched
// substring inline. Projects emphasise the match with a heavier
// weight (the title stays white throughout); chats add a snippet
// underneath drawn from the field where the match was found, with
// the match brightened against a dimmed snippet so the eye snaps
// straight to it.

private struct SearchProjectRow: View {
    let project: DerivedProject
    let displayName: String
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            FolderClosedIcon(size: 20)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 24, alignment: .center)
            SearchHighlight.titleText(
                displayName,
                query: query,
                color: Palette.textPrimary
            )
            .tracking(-0.1)
            .lineLimit(1)
            Spacer()
            if project.hasActiveTurn {
                Circle()
                    .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct SearchChatRow: View {
    let chat: WireChat
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SearchHighlight.titleText(
                chat.title,
                query: query,
                color: Palette.textPrimary
            )
            .tracking(-0.1)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let snippet = snippetText {
                snippet
                    .tracking(0)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var snippetText: Text? {
        guard let source = SearchHighlight.snippetSource(for: chat, query: query) else {
            return nil
        }
        let trimmed = SearchHighlight.snippet(source, query: query, leadingContext: 8)
        return SearchHighlight.snippetText(trimmed, query: query)
    }
}

// MARK: - Search highlight helpers

private enum SearchHighlight {
    /// Title is rendered in white. The match goes in Bold at full
    /// opacity; the rest stays at the body-default Medium weight
    /// with a barely-there opacity dip so the matched substring
    /// gains a faint extra lift on top of the weight contrast.
    static func titleText(_ source: String, query: String, color: Color) -> Text {
        compose(
            source,
            query: query,
            baseFont: BodyFont.system(size: 17, weight: .regular),
            matchFont: BodyFont.system(size: 17, weight: .semibold),
            baseColor: color.opacity(0.88),
            matchColor: color
        )
    }

    /// Snippet is smaller and dimmer than the title so the row reads
    /// as title-first; the matched substring brightens to white to
    /// guide the eye to the reason this row showed up.
    static func snippetText(_ source: String, query: String) -> Text {
        compose(
            source,
            query: query,
            baseFont: BodyFont.system(size: 13, weight: .regular),
            matchFont: BodyFont.system(size: 13, weight: .regular),
            baseColor: Palette.textTertiary,
            matchColor: Palette.textPrimary
        )
    }

    /// Trim `source` so the first match sits near the start, leaving
    /// `leadingContext` characters of context before it. Returns the
    /// original string if the match is already near the start or
    /// missing.
    static func snippet(_ source: String, query: String, leadingContext: Int) -> String {
        guard !query.isEmpty,
              let range = source.range(of: query, options: .caseInsensitive) else {
            return source
        }
        let offset = source.distance(from: source.startIndex, to: range.lowerBound)
        guard offset > leadingContext else { return source }
        let start = source.index(source.startIndex, offsetBy: offset - leadingContext)
        return String(source[start...])
    }

    /// Pick the field that actually contains the match, in priority:
    /// preview → cwd → title. Returns nil if none of the fields
    /// contains the query.
    static func snippetSource(for chat: WireChat, query: String) -> String? {
        guard !query.isEmpty else { return nil }
        if let preview = chat.lastMessagePreview,
           !preview.isEmpty,
           preview.range(of: query, options: .caseInsensitive) != nil {
            return preview
        }
        if let cwd = chat.cwd,
           !cwd.isEmpty,
           cwd.range(of: query, options: .caseInsensitive) != nil {
            return cwd
        }
        return nil
    }

    private static func compose(
        _ source: String,
        query: String,
        baseFont: Font,
        matchFont: Font,
        baseColor: Color,
        matchColor: Color
    ) -> Text {
        guard !query.isEmpty else {
            return Text(source).font(baseFont).foregroundColor(baseColor)
        }
        var result = Text("")
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let range = source.range(
                of: query,
                options: .caseInsensitive,
                range: cursor..<source.endIndex
              ) {
            let before = source[cursor..<range.lowerBound]
            if !before.isEmpty {
                result = result + Text(String(before)).font(baseFont).foregroundColor(baseColor)
            }
            let matched = source[range]
            result = result + Text(String(matched)).font(matchFont).foregroundColor(matchColor)
            cursor = range.upperBound
        }
        let tail = source[cursor..<source.endIndex]
        if !tail.isEmpty {
            result = result + Text(String(tail)).font(baseFont).foregroundColor(baseColor)
        }
        return result
    }
}

// MARK: - All projects sheet

private struct AllProjectsSheet: View {
    let projects: [DerivedProject]
    let store: BridgeStore
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
                                Haptics.tap()
                                onSelect(project)
                            } label: {
                                ProjectRow(
                            project: project,
                            displayName: store.projectDisplayName(cwd: project.cwd, fallback: project.name)
                        )
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
                    Button("Close") {
                        Haptics.tap()
                        onDismiss()
                    }
                    .foregroundStyle(Palette.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings sheet

// Hosts everything connection-related: which Mac is paired, on which
// route (LAN / Tailscale), and the controls for re-pairing or
// disconnecting. Removed from the home chrome so the list of chats
// reads as the foreground content.
private struct SettingsSheet: View {
    let store: BridgeStore
    let onPair: (Credentials) -> Void
    let onUnpair: () -> Void
    let onDismiss: () -> Void

    @State private var showScanner = false
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        connectionCard
                        pairingActions
                        if let lastError {
                            Text(lastError)
                                .font(Typography.captionFont)
                                .foregroundStyle(Color.red.opacity(0.85))
                                .padding(.horizontal, 6)
                        }
                    }
                    .padding(.horizontal, AppLayout.screenHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        onDismiss()
                    }
                    .foregroundStyle(Palette.textPrimary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScanner) {
            SettingsScannerSheet(
                onScan: handleScan,
                onCancel: { showScanner = false },
                onError: { msg in
                    lastError = msg
                    showScanner = false
                }
            )
        }
    }

    // MARK: Connection card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                connectionDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionTitle)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let detail = connectionDetail {
                        Text(detail)
                            .font(Typography.captionFont)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRounded(radius: AppLayout.cardCornerRadius)
    }

    private var connectionDot: some View {
        let color: Color
        switch store.connection {
        case .connected:  color = Color(red: 0.30, green: 0.78, blue: 0.45)
        case .connecting: color = Color(red: 0.95, green: 0.78, blue: 0.30)
        case .error:      color = Color(red: 0.85, green: 0.30, blue: 0.30)
        case .unpaired:   color = Palette.textTertiary
        }
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private var connectionTitle: String {
        switch store.connection {
        case .unpaired:
            return "Not paired"
        case .connecting:
            return "Connecting"
        case .connected(let macName, _):
            return macName ?? "Connected"
        case .error:
            return "Disconnected"
        }
    }

    private var connectionDetail: String? {
        switch store.connection {
        case .unpaired:
            return "Scan the Clawix QR on your Mac to connect."
        case .connecting:
            return "Reaching your Mac…"
        case .connected(_, let route):
            switch route {
            case .tailscale: return "Connected via Tailscale"
            case .lan, .none: return "Connected over the local network"
            }
        case .error(let message):
            return message
        }
    }

    // MARK: Pairing actions

    private var pairingActions: some View {
        VStack(spacing: 0) {
            actionRow(
                title: "Pair another Mac",
                iconName: "qrcode.viewfinder",
                showsChevron: true,
                action: { showScanner = true }
            )
            Rectangle()
                .fill(Palette.borderSubtle)
                .frame(height: 0.5)
                .padding(.leading, 56)
            actionRow(
                title: "Disconnect",
                iconName: "personalhotspot.slash",
                destructive: true,
                action: onUnpair
            )
        }
        .glassRounded(radius: AppLayout.cardCornerRadius)
    }

    private func actionRow(
        title: String,
        iconName: String,
        showsChevron: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            // Disconnect / unpair gets a `.warning` notification haptic
            // because it's a destructive jump back to the pairing flow;
            // routine actions get the standard light tap.
            if destructive {
                Haptics.warning()
            } else {
                Haptics.tap()
            }
            action()
        }) {
            HStack(spacing: 14) {
                LucideIcon.auto(iconName, size: 25.5)
                    .foregroundStyle(destructive ? Color(red: 0.95, green: 0.40, blue: 0.40) : Palette.textPrimary)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(Typography.bodyFont)
                    .foregroundStyle(destructive ? Color(red: 0.95, green: 0.40, blue: 0.40) : Palette.textPrimary)
                Spacer(minLength: 8)
                if showsChevron {
                    LucideIcon(.chevronRight, size: 19)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: QR scan handling

    private func handleScan(_ raw: String) {
        showScanner = false
        guard let payload = PairingPayload.parse(raw) else {
            lastError = "Not a Clawix pairing code"
            return
        }
        guard payload.v == 1 else {
            lastError = "Pairing format v\(payload.v) not supported. Update this app."
            return
        }
        let creds = payload.asCredentials
        CredentialStore.shared.save(creds)
        lastError = nil
        onPair(creds)
    }
}

private struct SettingsScannerSheet: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            QRScannerView(onScan: onScan, onError: onError)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: {
                        Haptics.tap()
                        onCancel()
                    }) {
                        LucideIcon(.x, size: 25.5)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .glassCircle()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }
                Spacer()
                Text("Scan the Clawix QR shown on your Mac")
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - New chat FAB

/// White floating action button anchored to the bottom-right of the
/// chat list. Pairs the v7 ComposeIcon with a "Chat" label and reads
/// as the primary affordance for starting a new conversation.
private struct NewChatFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.send()
            action()
        }) {
            HStack(spacing: 8) {
                ComposeIcon(size: 18)
                    .foregroundStyle(Color.black)
                Text("Chat")
                    .font(BodyFont.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
            .padding(.leading, 19)
            .padding(.trailing, 18)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New chat")
    }
}

#Preview("Chat list") {
    ChatListView(
        store: BridgeStore.mock(),
        onOpen: { _ in },
        onOpenProject: { _ in },
        onPair: { _ in },
        onUnpair: {}
    )
    .preferredColorScheme(.dark)
}

// Fires its action on touch-down (when `isPressed` flips to true)
// instead of touch-up, eliminating the perceived latency of a stock
// SwiftUI Button. Idempotency is the caller's responsibility.
private struct InstantPressButtonStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}
