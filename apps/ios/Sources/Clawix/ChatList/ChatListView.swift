import SwiftUI
import UIKit
import ClawixCore

// Pure dark blur backdrop with no SwiftUI vibrancy whitening.
// SwiftUI Materials add a vibrancy layer that lifts dark areas to a
// gray that reads as a halo over a black canvas; UIKit's
// `.systemUltraThinMaterialDark` keeps the blur strong while
// staying neutral against the underlying black.
private struct NeutralDarkBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

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
                Color.clear.frame(height: 8)

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
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                NeutralDarkBlur()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black, location: 0.0),
                                .init(color: Color.black, location: 0.55),
                                .init(color: Color.black.opacity(0.42), location: 0.85),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                LinearGradient(
                    stops: [
                        .init(color: Palette.background.opacity(0.88), location: 0.0),
                        .init(color: Palette.background.opacity(0.85), location: 0.55),
                        .init(color: Palette.background.opacity(0.42), location: 0.85),
                        .init(color: Palette.background.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 135)
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 4)
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
            if !searchActive {
                Text("Clawix")
                    .font(AppFont.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
            }

            Spacer(minLength: 0)

            if searchActive {
                searchFieldPill
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            } else {
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
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    searchActive = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    searchFocused = true
                }
            } label: {
                SearchIcon(size: 15)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 42, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showSettings = true
            } label: {
                SettingsIcon(size: 19, lineWidth: 3.15 * 15 / 28)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 42, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassCapsule()
    }

    private var searchFieldPill: some View {
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
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    searchActive = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(BodyFont.system(size: 11, weight: .bold))
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
                        HStack(spacing: 12) {
                            Image(systemName: "ellipsis")
                                .font(BodyFont.system(size: 18, weight: .regular))
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
            .font(AppFont.system(size: 18, weight: .semibold))
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
        HStack(spacing: 12) {
            FolderClosedIcon(size: 20)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 24, alignment: .center)
            Text(project.name)
                .font(Typography.bodyFont)
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

    var body: some View {
        Text(chat.title)
            .font(Typography.bodyFont)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.screenHorizontalPadding)
            .padding(.vertical, 14)
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
                    Button("Done") { onDismiss() }
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
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(BodyFont.system(size: 16, weight: .regular))
                    .foregroundStyle(destructive ? Color(red: 0.95, green: 0.40, blue: 0.40) : Palette.textPrimary)
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(Typography.bodyFont)
                    .foregroundStyle(destructive ? Color(red: 0.95, green: 0.40, blue: 0.40) : Palette.textPrimary)
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(BodyFont.system(size: 12, weight: .semibold))
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
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(BodyFont.system(size: 16, weight: .semibold))
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
        Button(action: action) {
            HStack(spacing: 8) {
                ComposeIcon(size: 17)
                    .foregroundStyle(Color.black)
                Text("Chat")
                    .font(AppFont.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .frame(height: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, y: 8)
            .contentShape(Capsule(style: .continuous))
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
