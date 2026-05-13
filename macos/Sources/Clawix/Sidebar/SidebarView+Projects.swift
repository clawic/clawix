import SwiftUI
import UniformTypeIdentifiers

struct ProjectAccordion: View, Equatable {
    let project: Project
    let expanded: Bool
    /// Up to `Self.maxVisible` (10) chats indexed for this project,
    /// already sorted desc by `createdAt`. The accordion further
    /// trims to `defaultVisible` (5) until "Show more" is tapped.
    let chats: [Chat]
    /// True once the user has tapped "Show more" on this project,
    /// promoting the visible slice from 5 to up to 10. Reset by the
    /// parent on collapse.
    let showingExtended: Bool
    let onToggle: () -> Void
    let onMenuToggle: () -> Void
    let onNewChat: () -> Void
    let onShowMore: () -> Void
    let onViewAll: () -> Void
    let menuOpen: Bool
    /// Currently selected chat id, lifted out so the accordion's `Equatable`
    /// check can detect "the user navigated to / away from a chat in this
    /// project" without subscribing to `AppState`.
    let selectedChatId: UUID?
    /// Factory that produces per-row callbacks. The closure itself is
    /// excluded from `==`; it captures `appState` and the chat id on the
    /// parent side, both stable across renders.
    let chatCallbacks: (Chat) -> RecentChatRowCallbacks

    /// Default number of chats shown when a project is freshly expanded.
    /// "Show more" promotes the slice to `maxVisible`.
    static let defaultVisible: Int = 5
    /// Hard cap on chats rendered inside the accordion. Anything past
    /// this is reachable through the per-project "View all" popup.
    static let maxVisible: Int = 10

    /// Visible slice of `chats` for the current `showingExtended` state.
    private var visibleChats: ArraySlice<Chat> {
        let cap = showingExtended ? Self.maxVisible : Self.defaultVisible
        return chats.prefix(cap)
    }

    /// Whether tapping "Show more" would reveal additional rows in the
    /// accordion. False once the visible slice already covers `chats`.
    private var canShowMore: Bool {
        !showingExtended && chats.count > Self.defaultVisible
    }

    /// Whether to surface the "View all" footer row. True once the
    /// indexed list has saturated the per-project cap, since the
    /// runtime may know about more conversations than the snapshot.
    /// Conservative: with exactly 10 indexed chats and nothing else
    /// behind them the popup just lists those 10, which is fine.
    private var canViewAll: Bool {
        showingExtended && chats.count >= Self.maxVisible
    }

    @State private var hovered = false
    @State private var newChatHovered = false
    @State private var menuHovered = false

    static func == (lhs: ProjectAccordion, rhs: ProjectAccordion) -> Bool {
        lhs.project.id == rhs.project.id
            && lhs.project.name == rhs.project.name
            && lhs.expanded == rhs.expanded
            && lhs.showingExtended == rhs.showingExtended
            && lhs.menuOpen == rhs.menuOpen
            && lhs.selectedChatId == rhs.selectedChatId
            && Self.chatsEqual(lhs.chats, rhs.chats)
    }

    /// Compare only the `Chat` fields the inner row actually renders
    /// (everything in `RecentChatRow.==`). Skips `messages`, `cwd`,
    /// `branch`, etc. — those mutate often during streaming and would
    /// invalidate the accordion for nothing.
    private static func chatsEqual(_ lhs: [Chat], _ rhs: [Chat]) -> Bool {
        if lhs.count != rhs.count { return false }
        for i in 0..<lhs.count {
            let l = lhs[i]
            let r = rhs[i]
            if l.id != r.id
                || l.title != r.title
                || l.hasActiveTurn != r.hasActiveTurn
                || l.hasUnreadCompletion != r.hasUnreadCompletion
                || l.createdAt != r.createdAt {
                return false
            }
        }
        return true
    }

    var body: some View {
        RenderProbe.tick("ProjectAccordion")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Tap-gesture instead of `Button`. A `Button` would consume
                // mouseDown and starve the parent's `.onDrag` (custom sort
                // mode reorders by dragging this row), the same reason
                // `RecentChatRow` uses `.onTapGesture` for selection.
                HStack(spacing: 8) {
                    FolderMorphIcon(size: 14.5, progress: expanded ? 1 : 0, lineWidthScale: 1.027)
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 15, height: 15)
                        .animation(.easeOut(duration: 0.28), value: expanded)
                    Text(project.name)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color(white: 0.94))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.28)) { onToggle() }
                }

                // Ellipsis (hover/menu open) — anchors the dropdown.
                // `.disabled` instead of `.allowsHitTesting` so the button's
                // hover tracking area survives even while invisible; toggling
                // hit testing on/off from the same `hovered` state the parent
                // row owns creates a flicker loop where moving the cursor
                // into the icon makes the parent lose hover and the icon
                // disappears.
                Button(action: onMenuToggle) {
                    LucideIcon(.ellipsis, size: 13)
                        .foregroundColor(menuHovered || menuOpen ? Color(white: 0.94) : Color(white: 0.55))
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || menuOpen ? 1 : 0)
                .disabled(!(hovered || menuOpen))
                .sidebarHover { menuHovered = $0 }
                .help(L10n.t("More options"))
                .anchorPreference(key: ProjectMenuAnchorKey.self, value: .bounds) { anchor in
                    menuOpen ? anchor : nil
                }

                // Pencil. start a new chat in this project (always visible).
                // 28x28 hit area around a 12.2pt glyph: the cursor catches
                // the button as soon as it nears the icon, no need to land
                // exactly on the strokes.
                Button(action: onNewChat) {
                    ComposeIcon()
                        .stroke(newChatHovered ? Color(white: 0.94) : Color(white: 0.50),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 12.2, height: 12.2)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .sidebarHover { newChatHovered = $0 }
                .help(L10n.t("New chat in this project"))
            }
            .frame(height: 35)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered || menuOpen ? Color.white.opacity(0.04) : Color.clear)
            )
            .padding(.trailing, 3)
            .sidebarHover { hovered = $0 }
            .animation(.easeOut(duration: 0.10), value: hovered || menuOpen)
            .animation(.easeOut(duration: 0.12), value: newChatHovered)
            .animation(.easeOut(duration: 0.12), value: menuHovered)

            // `SidebarAccordion` uses the targetHeight as an open-state
            // animation hint but takes max(target, measured) for the
            // actual frame, so a slightly off heuristic clips a few
            // pixels rather than the bottom row. The previous fixed
            // `SmoothAccordion` cropped the 10th chat because the
            // 30pt row metric undershoots the rendered height and the
            // footer row was not in the calculation at all.
            let visibleCount = visibleChats.count
            let baseHeight: CGFloat = visibleCount > 0
                ? SidebarRowMetrics.recentChats(
                    count: visibleCount,
                    spacing: SidebarRowMetrics.projectChatSpacing
                )
                : SidebarRowMetrics.projectEmptyState
            let footerHeight: CGFloat = (canShowMore || canViewAll)
                ? SidebarRowMetrics.projectFooterRow + SidebarRowMetrics.projectChatSpacing
                : 0
            SidebarAccordion(
                expanded: expanded,
                targetHeight: baseHeight + footerHeight
            ) {
                // `LazyVStack` so a project with many chats doesn't pay
                // for instantiating off-screen rows. The accordion's
                // `targetHeight` provides the bounded frame, and the
                // surrounding `ThinScrollView` is the scroll context that
                // actually drives lazy materialisation.
                LazyVStack(alignment: .leading, spacing: 0) {
                    if chats.isEmpty {
                        Text("No chats")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Color(white: 0.40))
                            .padding(.leading, 30)
                            .padding(.vertical, 4)
                    }
                    ForEach(Array(visibleChats)) { chat in
                        RecentChatRow(
                            chat: chat,
                            isSelected: selectedChatId == chat.id,
                            leadingIcon: .pinOnHover,
                            callbacks: chatCallbacks(chat)
                        )
                        .equatable()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                    if canShowMore {
                        ProjectAccordionFooterRow(
                            label: L10n.t("Show more"),
                            action: onShowMore
                        )
                        .transition(.opacity)
                    } else if canViewAll {
                        ProjectAccordionFooterRow(
                            label: L10n.t("View all"),
                            action: onViewAll
                        )
                        .transition(.opacity)
                    }
                }
            }
        }
    }
}

struct ProjectAccordionFooterRow: View {
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: hovered ? 0.78 : 0.55))
            Spacer(minLength: 6)
        }
        .padding(.leading, 33)
        .padding(.trailing, 10)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.14), value: hovered)
    }
}

struct SmoothAccordion<Content: View>: View {
    let expanded: Bool
    let targetHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: expanded ? targetHeight : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
            .animation(nil, value: expanded)
            .animation(nil, value: targetHeight)
    }
}

enum SidebarRowMetrics {
    /// `RecentChatRow` and `ProjectAccordion` headers are both pinned
    /// to `frame(height: 35)` so every hoverable "tab" in the sidebar
    /// reads at one consistent size, regardless of internal content
    /// (e.g. the chat row's 22pt archive button vs the project header's
    /// 16pt text line).
    static let chatRow: CGFloat = 35
    /// VStack spacing between recent chat rows.
    static let chatSpacing: CGFloat = 0
    /// Spacing inside `ProjectAccordion`'s chat list.
    static let projectChatSpacing: CGFloat = 0
    /// "No chats" / "Loading…" placeholder row inside a project accordion.
    static let projectEmptyState: CGFloat = 24
    /// "Show more" / "View all" footer row at the end of a project's
    /// chat list. Same text size as a chat row plus a generous bottom
    /// gap so it visually separates from the next project header.
    static let projectFooterRow: CGFloat = 36
    /// Trailing buffer rendered as a `Color.clear` spacer at the end of
    /// every collapsible section's content (Pinned, Chats, All chats,
    /// Projects, Archived). Inside the accordion (not standalone) so it
    /// rides the height transition. Driving the gap from a real spacer
    /// inside `content()` instead of from `targetHeight` overshoot is
    /// what guarantees the gap reads identically across sections: when
    /// a section's row-height estimate is too low (Projects: 28pt
    /// estimate vs ~35pt actual rows), `measuredHeight` overshoots
    /// `targetHeight` and the accordion frame uses `measuredHeight`,
    /// which used to consume the buffer entirely (Projects looked glued
    /// to Archived while Pinned/Chats had a generous gap). With the
    /// spacer baked into measured content, the visible gap = this
    /// constant regardless of estimate accuracy.
    static let sectionEdgePadding: CGFloat = 9.75

    static func recentChats(count: Int, spacing: CGFloat = chatSpacing) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * chatRow + CGFloat(count - 1) * spacing
    }
}

struct SidebarAccordion<Content: View>: View {
    let expanded: Bool
    let targetHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        let h = max(targetHeight, measuredHeight)
        VStack(spacing: 0) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                measuredHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size.height) { _, newH in
                                measuredHeight = newH
                            }
                    }
                )
        }
        .frame(height: expanded ? h : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .animation(nil, value: expanded)
        .animation(nil, value: h)
    }
}

struct SidebarAccordionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ExpandableContainer<Content: View>: View {
    let expanded: Bool
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ExpandableHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            content()
        }
        .frame(height: expanded ? measuredHeight : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .animation(nil, value: expanded)
        .animation(nil, value: measuredHeight)
        .onPreferenceChange(ExpandableHeightKey.self) { measuredHeight = $0 }
    }
}

struct ExpandableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ProjectMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct PinnedRow: View {
    let item: PinnedItem
    @State private var hovered = false

    var body: some View {
        RenderProbe.tick("PinnedRow")
        return HStack(spacing: 10) {
            PinnedIcon()
                .stroke(Color(white: 0.58),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text(item.title)
                .font(BodyFont.system(size: 14, wght: 500))
                .foregroundColor(Color(white: 0.94))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hovered {
                Button {
                    // archivar chat
                } label: {
                    LucideIcon(.archive, size: 13)
                        .foregroundColor(Color(white: 0.72))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("Archive chat"))
            } else {
                Text(item.age)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovered ? Color.white.opacity(0.035) : Color.clear)
        )
        .sidebarHover { hovered = $0 }
        .contextMenu {
            Button("Unpin chat")     {}
            Button("Rename chat")     {}
            Button("Archive chat")      {}
            Button("Mark as unread") {}
            Divider()
            Button("Open in Finder")            {}
            Button("Copy working directory") {
                copyToPasteboard("~/Projects/\(item.title)")
            }
            Button("Copy session ID") {
                copyToPasteboard(item.id.uuidString)
            }
            Button("Copy direct link") {
                copyToPasteboard("clawix://chat/\(item.id.uuidString)")
            }
            Divider()
            Button("Fork to local")         {}
            Button("Fork to new worktree") {}
            Divider()
            Button("Open in mini window") {}
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }
}

struct ProjectRowMenuPopup: View {
    let project: Project
    let isCodexSourced: Bool
    @Binding var isPresented: Bool
    let onOpenInFinder: () -> Void
    let onRename: () -> Void
    let onArchive: () -> Void
    let onRemove: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectRowMenuRow(icon: "folder", label: "Open in Finder", action: onOpenInFinder)
            ProjectRowMenuRow(icon: "arrow.triangle.branch", label: "Create a permanent worktree") {
                isPresented = false
            }
            ProjectRowMenuRow(icon: "pencil", label: "Rename project", action: onRename)
            ProjectRowMenuRow(icon: "tray.and.arrow.down", label: "Archive chats", action: onArchive)
            if isCodexSourced {
                ProjectRowMenuRow(icon: "eye.slash", label: "Hide from sidebar", action: onHide)
            } else {
                ProjectRowMenuRow(icon: "xmark", label: "Remove", action: onRemove)
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

struct ProjectRowMenuRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "pencil" {
                        PencilIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                            .frame(width: 14, height: 14)
                    } else {
                        IconImage(icon, size: 11)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}
