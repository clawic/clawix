import SwiftUI
import AppKit

// MARK: - Search popover overlay

/// Bubbles the inner search-content's natural height (rows or empty
/// message) up to `SearchPopoverOverlay`, which uses it to size the
/// content slot. `max` so duplicate emissions converge on the tallest
/// reading.
struct SearchContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SearchPopoverOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var queryFocused: Bool = false
    /// Natural height of the inner content (rows or empty message),
    /// measured via `SearchContentHeightKey`. The popup's content slot
    /// renders at this height, capped at `contentAreaMaxHeight`. Anchored
    /// to the popup's top so the search icon never moves; only the
    /// bottom edge tracks the result count.
    @State private var contentNaturalHeight: CGFloat = 220

    private static let popupCornerRadius: CGFloat = 26
    private static let popupStrokeColor = Color.white.opacity(0.18)
    private static let popupStrokeWidth: CGFloat = 0.9
    /// Cap on the result list. Past this, the inner content scrolls.
    private static let contentAreaMaxHeight: CGFloat = 350

    private var scopedProject: Project? {
        guard let id = appState.searchScopedProjectId else { return nil }
        return appState.projects.first(where: { $0.id == id })
    }

    private var pinnedChats: [Chat] {
        appState.chats
            .filter { $0.isPinned && !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var filteredPinnedChats: [Chat] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pinnedChats }
        return searchableChats.filter { $0.title.lowercased().contains(q) }
    }

    private var searchableChats: [Chat] {
        appState.chats
            .filter { !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func scopedChats(for project: Project) -> [Chat] {
        appState.chats
            .filter { $0.projectId == project.id && !$0.isArchived && !$0.isQuickAskTemporary && !$0.isSideChat }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func filteredScopedChats(for project: Project) -> [Chat] {
        let all = scopedChats(for: project)
        let q = appState.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) }
    }

    private func projectName(for chat: Chat) -> String? {
        guard let pid = chat.projectId else { return nil }
        return appState.projects.first(where: { $0.id == pid })?.name
    }

    private var sortedProjects: [Project] {
        appState.projects.sorted {
            $0.name.lowercased() < $1.name.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            divider
            content
                .frame(height: min(max(contentNaturalHeight, 1),
                                   Self.contentAreaMaxHeight),
                       alignment: .top)
                .onPreferenceChange(SearchContentHeightKey.self) { newValue in
                    contentNaturalHeight = newValue
                }
        }
        .frame(width: 560, alignment: .leading)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow,
                                 blendingMode: .withinWindow,
                                 state: .active)
                MenuStyle.fill
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.popupCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.popupCornerRadius, style: .continuous)
                    .stroke(Self.popupStrokeColor, lineWidth: Self.popupStrokeWidth)
            )
            .shadow(color: MenuStyle.shadowColor,
                    radius: MenuStyle.shadowRadius,
                    x: 0, y: MenuStyle.shadowOffsetY)
        )
        .background(MenuOutsideClickWatcher(isPresented: searchOpenBinding))
        .background(SearchKeyMonitor(
            query: $appState.searchQuery,
            onEscape: { closePopover() },
            onSelectIndex: { index in selectResult(at: index) },
            onSubmitFirst: { selectResult(at: 0) }
        ))
        .task {
            // Re-arming the focus in a Task keeps the textfield reliably
            // first responder even when the popup is reopened from the
            // same route, where onAppear sometimes fires before the
            // field is in the responder chain.
            queryFocused = true
            triggerScopedHistoryLoadIfNeeded()
        }
        .onChange(of: appState.searchScopedProjectId) { _, _ in
            queryFocused = true
            triggerScopedHistoryLoadIfNeeded()
        }
    }

    private func closePopover() {
        if appState.currentRoute == .search {
            appState.currentRoute = .home
        }
    }

    private func selectResult(at index: Int) {
        guard index >= 0 else { return }
        let chats: [Chat]
        if let project = scopedProject {
            chats = filteredScopedChats(for: project)
        } else {
            chats = filteredPinnedChats
        }
        guard index < min(chats.count, 9) else { return }
        appState.navigate(to: .chat(chats[index].id))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SearchIcon(size: 14)
                .foregroundColor(Color(white: 0.55))
            if let project = scopedProject {
                ScopeChip(
                    name: project.name,
                    onRemove: { appState.searchScopedProjectId = nil }
                )
            }
            SearchQueryTextField(
                placeholder: scopedProject == nil
                    ? "Search chats"
                    : "Search in \(scopedProject!.name)",
                text: $appState.searchQuery,
                wantsFocus: queryFocused,
                onEscape: { closePopover() },
                onSelectIndex: { index in selectResult(at: index) },
                onSubmitFirst: { selectResult(at: 0) }
            )
            .frame(height: 20)
            if scopedProject == nil, !sortedProjects.isEmpty {
                projectFilterMenu
            }
            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                } label: {
                    LucideIcon(.circleX, size: 13)
                        .foregroundColor(Color(white: 0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var projectFilterMenu: some View {
        Menu {
            ForEach(sortedProjects) { project in
                Button(project.name) {
                    appState.searchScopedProjectId = project.id
                }
            }
        } label: {
            FolderOpenIcon(size: 14)
                .foregroundColor(Color(white: 0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by project")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        if let project = scopedProject {
            scopedContent(for: project)
        } else {
            unscopedContent
        }
    }

    @ViewBuilder
    private var unscopedContent: some View {
        let pinned = filteredPinnedChats
        if !pinned.isEmpty {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty ? "Pinned chats" : "Matches")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(MenuStyle.headerText)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(pinned.prefix(9).enumerated()), id: \.element.id) { index, chat in
                            SearchPinnedRow(
                                title: chat.title,
                                projectName: projectName(for: chat),
                                shortcutNumber: index + 1,
                                isFirst: index == 0 && appState.searchQuery.isEmpty,
                                onSelect: { appState.navigate(to: .chat(chat.id)) }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(naturalHeightProbe)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .thinScrollers()
        } else {
            emptyContent(message: appState.searchQuery.isEmpty
                         ? "Search by chat title"
                         : "No matches")
        }
    }

    @ViewBuilder
    private func scopedContent(for project: Project) -> some View {
        let chats = filteredScopedChats(for: project)
        if chats.isEmpty {
            emptyContent(message: appState.searchQuery.isEmpty
                         ? "No chats in this project yet"
                         : "No matches")
        } else {
            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(chats) { chat in
                        SearchScopedRow(
                            title: chat.title,
                            createdAt: chat.createdAt,
                            onSelect: { appState.navigate(to: .chat(chat.id)) }
                        )
                    }
                }
                .padding(.vertical, 8)
                .background(naturalHeightProbe)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .thinScrollers()
        }
    }

    private func emptyContent(message: LocalizedStringKey) -> some View {
        Text(message)
            .font(BodyFont.system(size: 13, wght: 500))
            .foregroundColor(MenuStyle.rowSubtle)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(naturalHeightProbe)
    }

    /// Transparent overlay used by the content branches to publish their
    /// unconstrained natural height to the popup so the outer frame can
    /// shrink to fit short lists and clip+scroll long ones.
    private var naturalHeightProbe: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: SearchContentHeightKey.self,
                            value: proxy.size.height)
        }
    }

    private var searchOpenBinding: Binding<Bool> {
        Binding(
            get: { appState.currentRoute == .search },
            set: { isOpen in
                if !isOpen, appState.currentRoute == .search {
                    appState.currentRoute = .home
                }
            }
        )
    }

    private func triggerScopedHistoryLoadIfNeeded() {
        // Pull the full project history into memory the moment a scope
        // is set, so the title filter sees every chat instead of just
        // the 10-row sidebar slice. Detached so the popup paints with
        // whatever's already cached and updates as rows arrive.
        guard let project = scopedProject else { return }
        Task.detached(priority: .userInitiated) { [project] in
            await appState.loadAllThreadsForProject(project)
        }
    }
}

struct SearchKeyMonitor: NSViewRepresentable {
    @Binding var query: String
    var onEscape: () -> Void
    var onSelectIndex: (Int) -> Void
    var onSubmitFirst: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.query = $query
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onSubmitFirst = onSubmitFirst
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MonitorView else { return }
        view.query = $query
        view.onEscape = onEscape
        view.onSelectIndex = onSelectIndex
        view.onSubmitFirst = onSubmitFirst
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? MonitorView)?.detach()
    }

    final class Coordinator {
        var query: Binding<String>

        init(query: Binding<String>) {
            self.query = query
        }
    }

    final class MonitorView: NSView {
        var query: Binding<String>?
        var onEscape: (() -> Void)?
        var onSelectIndex: ((Int) -> Void)?
        var onSubmitFirst: (() -> Void)?
        private var monitor: Any?
        private let shortcutKeyCodes: [UInt16: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
            22: 5, 26: 6, 28: 7, 25: 8
        ]
        private let navigationKeyCodes: Set<UInt16> = [
            36, 48, 76, 115, 116, 119, 121, 123, 124, 125, 126
        ]

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { attach() } else { detach() }
        }

        private func attach() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, NSApp.keyWindow === win else { return event }
                if event.keyCode == 53 {
                    self.onEscape?()
                    return nil
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.command),
                   let index = self.shortcutKeyCodes[event.keyCode] {
                    self.onSelectIndex?(index)
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.onSubmitFirst?()
                    return nil
                }
                if self.handleTextInput(event) {
                    return nil
                }
                return event
            }
        }

        private func handleTextInput(_ event: NSEvent) -> Bool {
            guard let query else { return false }
            if navigationKeyCodes.contains(event.keyCode) {
                return false
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return false
            }
            if event.keyCode == 51 {
                guard !query.wrappedValue.isEmpty else { return true }
                query.wrappedValue.removeLast()
                return true
            }
            guard let characters = event.characters, !characters.isEmpty else { return false }
            if characters.unicodeScalars.allSatisfy({ CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
                return false
            }
            query.wrappedValue.append(characters)
            return true
        }

        func detach() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { detach() }
    }
}

struct SearchQueryTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let wantsFocus: Bool
    var onEscape: () -> Void
    var onSelectIndex: (Int) -> Void
    var onSubmitFirst: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusableSearchTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        field.textColor = NSColor(white: 0.94, alpha: 1)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.onEscape = onEscape
        field.onSelectIndex = onSelectIndex
        field.onSubmitFirst = onSubmitFirst
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onWindowReady = {
            guard context.coordinator.wantsFocus else { return }
            context.coordinator.focusIfNeeded(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.text = $text
        context.coordinator.wantsFocus = wantsFocus
        if let field = nsView as? FocusableSearchTextField {
            field.onEscape = onEscape
            field.onSelectIndex = onSelectIndex
            field.onSubmitFirst = onSubmitFirst
        }
        if wantsFocus {
            context.coordinator.focusIfNeeded(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var wantsFocus: Bool = false

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func focusIfNeeded(_ field: NSTextField) {
            if Self.fieldIsEditing(field) {
                return
            }
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                if Self.fieldIsEditing(field) { return }
                window.makeFirstResponder(field)
                Self.collapseSelectionToEnd(field)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak field] in
                guard let field, let window = field.window else { return }
                if Self.fieldIsEditing(field) { return }
                window.makeFirstResponder(field)
                Self.collapseSelectionToEnd(field)
            }
        }

        private static func fieldIsEditing(_ field: NSTextField) -> Bool {
            guard let window = field.window, let editor = field.currentEditor()
            else { return false }
            return window.firstResponder === editor
        }

        private static func collapseSelectionToEnd(_ field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }
}

final class FocusableSearchTextField: NSTextField {
    var onWindowReady: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSelectIndex: ((Int) -> Void)?
    var onSubmitFirst: (() -> Void)?

    private let shortcutKeyCodes: [UInt16: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
        22: 5, 26: 6, 28: 7, 25: 8
    ]
    private let navigationKeyCodes: Set<UInt16> = [
        48, 115, 116, 119, 121, 123, 124, 125, 126
    ]

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowReady?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           let index = shortcutKeyCodes[event.keyCode] {
            onSelectIndex?(index)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onSubmitFirst?()
            return
        }
        if navigationKeyCodes.contains(event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }
}

struct ScopeChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            FolderOpenIcon(size: 11)
                .foregroundColor(Color(white: 0.65))
            Text(name)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.88))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: onRemove) {
                LucideIcon(.x, size: 10)
                    .foregroundColor(Color(white: 0.62))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .fixedSize()
    }
}

struct SearchScopedRow: View {
    let title: String
    let createdAt: Date
    let onSelect: () -> Void

    @State private var hovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var displayTitle: String {
        title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : title
    }

    var body: some View {
        HStack(spacing: 11) {
            LucideIcon(.messageCircle, size: 11)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(displayTitle)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            Text(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(MenuStyle.rowSubtle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            MenuRowHover(active: hovered)
        )
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open chat"), onSelect)
    }
}

struct SearchPinnedRow: View {
    let title: String
    let projectName: String?
    let shortcutNumber: Int
    let isFirst: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var displayTitle: String {
        title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : title
    }

    var body: some View {
        HStack(spacing: 11) {
            PinIcon(size: 13, lineWidth: 1.0)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)

            Text(displayTitle)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let projectName {
                Text(projectName)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .trailing)
            }

            ShortcutGlyph(number: shortcutNumber)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            MenuRowHover(
                active: hovered || isFirst,
                intensity: (hovered || isFirst) ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            )
        )
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(projectName ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Open chat"), onSelect)
    }
}

struct ShortcutGlyph: View {
    let number: Int

    var body: some View {
        Text("⌘\(number)")
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(MenuStyle.rowSubtle)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .frame(minWidth: 28, alignment: .center)
    }
}
