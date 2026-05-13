import SwiftUI
import UniformTypeIdentifiers

struct SidebarButton: View {
    let title: String
    let icon: String
    var customShape: AnyShape? = nil
    var customShapeSize: CGFloat = 11.3
    var customShapeStroke: CGFloat = 1.15
    let route: SidebarRoute
    var actionOnly: Bool = false
    var shortcut: String? = nil

    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    private var isSelected: Bool {
        guard !actionOnly else { return false }
        return appState.currentRoute == route
    }

    private var localizedTitle: String {
        L10n.t(String.LocalizationValue(title))
    }

    var body: some View {
        Button {
            appState.currentRoute = route
        } label: {
            HStack(spacing: 11) {
                Group {
                    if let shape = customShape {
                        shape
                            .stroke(iconColor,
                                    style: StrokeStyle(lineWidth: customShapeStroke, lineCap: .round, lineJoin: .round))
                            .frame(width: customShapeSize, height: customShapeSize)
                            .frame(width: 15, height: 15)
                    } else {
                        LucideIcon.auto(icon, size: 9.5)
                            .frame(width: 15)
                            .foregroundColor(iconColor)
                    }
                }
                Text(localizedTitle)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.78))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.32))
                        )
                        .opacity(hovered ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel(localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }


    private var iconColor: Color {
        if isSelected { return .white }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.92)
    }

    private var backgroundFill: Color {
        // Sidebar tabs (selected and hover) both use white-opacity so the
        // full-row glow stays soft; user preference outweighs the
        // wallpaper-tint side effect here.
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

struct ComposeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        // Box (open rounded square, corner radius 5.5).
        path.move(to: p(10.5, 1.5))
        path.addLine(to: p(7, 1.5))
        path.addCurve(to: p(1.5, 7),
                      control1: p(3.96, 1.5),
                      control2: p(1.5, 3.96))
        path.addLine(to: p(1.5, 17))
        path.addCurve(to: p(7, 22.5),
                      control1: p(1.5, 20.04),
                      control2: p(3.96, 22.5))
        path.addLine(to: p(17, 22.5))
        path.addCurve(to: p(22.5, 17),
                      control1: p(20.04, 22.5),
                      control2: p(22.5, 20.04))
        path.addLine(to: p(22.5, 13.5))

        // Pencil (45 deg axis from eraser center (20, 4) to tip apex
        // (7.17, 16.83), body half-width 3). Eraser is a true
        // semicircle, the two shoulders and the tip apex are filleted.
        // All arcs converted to two-cubic Bezier approximations so the
        // path renders identically across platforms without addArc's
        // clockwise-flag ambiguity.
        path.move(to: p(17.88, 1.88))
        // Eraser cap (180 deg, radius 3) split at apex (22.12, 1.88).
        path.addCurve(to: p(22.12, 1.88),
                      control1: p(19.05, 0.71),
                      control2: p(20.95, 0.71))
        path.addCurve(to: p(22.12, 6.12),
                      control1: p(23.29, 3.05),
                      control2: p(23.29, 4.95))
        // Body lower edge -> lower shoulder fillet (radius 1.5).
        path.addLine(to: p(13.45, 14.79))
        path.addCurve(to: p(12.81, 15.17),
                      control1: p(13.27, 14.97),
                      control2: p(13.05, 15.10))
        // Tip lower side -> tip apex fillet (radius 0.8) split at (7.78, 16.22).
        path.addLine(to: p(8.58, 16.42))
        path.addCurve(to: p(7.78, 16.22),
                      control1: p(8.30, 16.50),
                      control2: p(7.99, 16.43))
        path.addCurve(to: p(7.58, 15.42),
                      control1: p(7.57, 16.01),
                      control2: p(7.50, 15.70))
        // Tip upper side -> upper shoulder fillet (radius 1.5).
        path.addLine(to: p(8.83, 11.19))
        path.addCurve(to: p(9.21, 10.55),
                      control1: p(8.90, 10.95),
                      control2: p(9.03, 10.73))
        path.closeSubpath()
        return path
    }
}

enum SidebarSection {
    static let toggleAnimation: Animation = .easeInOut(duration: 0.28)
    /// Disclosure chevron rotation. Strong ease-out so the arrow snaps
    /// most of the way to its target quickly, then brakes hard at the
    /// end. Decoupled from `toggleAnimation` on purpose: the section
    /// height keeps a softer in-out, the chevron reads as more crisp.
    static let chevronRotation: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    /// Hover fade-in for the disclosure chevron. Small delay on appear
    /// so the arrow doesn't flash in the instant the cursor lands; fade
    /// out is immediate so the row clears as soon as hover ends.
    static let chevronHoverAppearDelay: Double = 0.06
    static let chevronHoverFadeIn: Animation = .easeOut(duration: 0.14)
    static let chevronHoverFadeOut: Animation = .easeOut(duration: 0.10)
    /// Trailing action icons cascade in after the chevron and fade out
    /// together without delay.
    static let trailingIconsFirstDelay: Double = 0.16
    static let trailingIconsStagger: Double = 0.05
    static let trailingIconsFadeIn: Animation = .easeOut(duration: 0.14)
    static let trailingIconsFadeOut: Animation = .easeOut(duration: 0.10)
}

struct HoverStaggerFade: ViewModifier {
    let visible: Bool
    let appearDelay: Double
    var fadeIn: Animation = SidebarSection.trailingIconsFadeIn
    var fadeOut: Animation = SidebarSection.trailingIconsFadeOut

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                visible ? fadeIn.delay(appearDelay) : fadeOut,
                value: visible
            )
    }
}

extension View {
    func hoverStaggerFade(visible: Bool, appearDelay: Double) -> some View {
        modifier(HoverStaggerFade(visible: visible, appearDelay: appearDelay))
    }
}

struct SectionDisclosureChevron: View {
    let expanded: Bool
    var hovered: Bool = false

    var body: some View {
        LucideIcon(.chevronRight, size: 10)
            .foregroundColor(Color(white: 0.78))
            .frame(width: 14, height: 14, alignment: .center)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(SidebarSection.chevronRotation, value: expanded)
            .opacity(hovered ? 1 : 0)
            .animation(
                hovered
                    ? SidebarSection.chevronHoverFadeIn.delay(SidebarSection.chevronHoverAppearDelay)
                    : SidebarSection.chevronHoverFadeOut,
                value: hovered
            )
    }
}

struct CollapsibleSectionLabel: View {
    let title: LocalizedStringKey
    let expanded: Bool
    /// Row-wide hover state owned by the parent header. Chevron reveal and
    /// label brightening key off this. `trailingIconsActive` (which also
    /// stays true while a header dropdown is open) drives the right hairline
    /// retraction so the bar doesn't snap back under still-visible icons
    /// when the cursor enters a popup.
    let hovered: Bool
    /// True when the trailing action icons are visible — i.e. hover OR an
    /// anchored dropdown is open. Drives the right hairline retraction
    /// only; the chevron and label color stay keyed to `hovered` so the
    /// disclosure arrow still hides on hover-out.
    var trailingIconsActive: Bool? = nil
    var chevronLeadingPadding: CGFloat = 2
    var leadingIcon: AnyView? = nil
    /// On hover, retract the right hairline by this many points to clear
    /// the trailing action icons (organize / new project / new chat). Pass
    /// 0 (default) for headers without a trailing icon group.
    var trailingIconsClearance: CGFloat = 0

    /// Collapsed sections read as part of the top button list (`New chat`,
    /// `Search`), so they borrow that brighter palette. Expanded sections
    /// recede into a dim title so the rows below stand out.
    private var labelColor: Color {
        if expanded {
            return Color(white: hovered ? 0.78 : 0.55)
        }
        return Color(white: hovered ? 0.96 : 0.92)
    }

    private var iconColor: Color {
        if expanded {
            return Color(white: hovered ? 0.78 : 0.55)
        }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let leadingIcon {
                ZStack {
                    leadingIcon
                        .foregroundColor(iconColor)
                        .scaleEffect(expanded ? 0 : 1, anchor: .center)
                        .opacity(expanded ? 0 : 1)
                        .animation(.easeOut(duration: 0.16), value: expanded)
                        .offset(y: 0.5)
                    SectionTitleHairline(visible: expanded, anchor: .trailing)
                }
                .frame(width: 15, height: 15, alignment: .center)
                .padding(.trailing, 11)
            }
            Text(title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(labelColor)
            ZStack(alignment: .leading) {
                // Asymmetric animation: contract fast on hover-in to clear
                // room for the trailing icons (collapse all, organize, new
                // project, new chat); on hover-out, wait for those icons to
                // finish their `trailingIconsFadeOut` (0.10s) and then sweep
                // back smoothly. Without the delay the line visibly crosses
                // still-fading icons; with too short a duration after the
                // delay it reads as a snap, not an animation.
                let trailingActive = trailingIconsActive ?? hovered
                SectionTitleHairline(visible: expanded, anchor: .leading)
                    .padding(.leading, hovered ? chevronLeadingPadding + 10 : 0)
                    .animation(
                        hovered
                            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
                            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.26).delay(0.10),
                        value: hovered
                    )
                    .padding(.trailing, trailingActive ? trailingIconsClearance : 0)
                    .animation(
                        trailingActive
                            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
                            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.26).delay(0.10),
                        value: trailingActive
                    )
                SectionDisclosureChevron(expanded: expanded, hovered: hovered)
                    .offset(x: chevronLeadingPadding - 11)
            }
            .frame(height: 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 11)
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct BasicSectionHeader: View {
    let title: LocalizedStringKey
    @Binding var expanded: Bool
    let leadingIcon: AnyView?
    /// Optional view rendered in a 22pt slot at the trailing edge. Fades
    /// in on hover or when `trailingForceVisible` is true. The view is
    /// responsible for its own click handler.
    var trailingIcon: AnyView? = nil
    /// Keep the trailing icon visible regardless of hover (e.g. while
    /// the icon's popup menu is open) so it doesn't blink out when the
    /// cursor enters the dropdown.
    var trailingForceVisible: Bool = false

    @State private var hovered = false

    private var iconsVisible: Bool { hovered || trailingForceVisible }

    var body: some View {
        let leadingPadding: CGFloat = leadingIcon != nil ? 16 : 20
        let hasTrailing = trailingIcon != nil
        let trailingClearance: CGFloat = hasTrailing ? 28 : 0
        HStack(spacing: 0) {
            CollapsibleSectionLabel(
                title: title,
                expanded: expanded,
                hovered: hovered,
                trailingIconsActive: hasTrailing ? iconsVisible : nil,
                leadingIcon: leadingIcon,
                trailingIconsClearance: trailingClearance
            )
            Spacer()
        }
        .frame(height: 24)
        .padding(.leading, leadingPadding)
        .padding(.trailing, 11)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(SidebarSection.toggleAnimation) { expanded.toggle() }
        }
        .overlay(alignment: .trailing) {
            if let trailingIcon {
                trailingIcon
                    .frame(width: 22, height: 22)
                    .padding(.trailing, 11)
                    .opacity(iconsVisible ? 1 : 0)
                    .animation(
                        iconsVisible
                            ? SidebarSection.trailingIconsFadeIn
                                .delay(SidebarSection.trailingIconsFirstDelay)
                            : SidebarSection.trailingIconsFadeOut,
                        value: iconsVisible
                    )
                    .disabled(!iconsVisible)
            }
        }
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct SectionTitleHairline: View {
    let visible: Bool
    let anchor: UnitPoint

    var body: some View {
        // Solid grays for the visible portion so the line doesn't take its
        // tone from the wallpaper through the translucent sidebar. The
        // endpoint stays alpha-0 because a hairline that disappears must
        // fade somewhere; the fade is local to the tail third while the
        // first ~70% nearest the word renders as a true solid line.
        let solid = Color(white: 0.42)
        let mid = Color(white: 0.36)
        let clear = Color.white.opacity(0)
        let stops: [Gradient.Stop] = anchor == .trailing
            ? [
                .init(color: clear, location: 0.0),
                .init(color: mid, location: 0.30),
                .init(color: solid, location: 0.55),
                .init(color: solid, location: 1.0)
            ]
            : [
                .init(color: solid, location: 0.0),
                .init(color: solid, location: 0.45),
                .init(color: mid, location: 0.70),
                .init(color: clear, location: 1.0)
            ]
        Rectangle()
            .fill(LinearGradient(gradient: Gradient(stops: stops),
                                 startPoint: .leading,
                                 endPoint: .trailing))
            .frame(height: 0.5)
            .scaleEffect(x: visible ? 1 : 0, y: 1, anchor: anchor)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.22), value: visible)
    }
}

struct HeaderHoverIcon<Label: View>: View {
    let tooltip: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let label: (Color) -> Label

    @State private var hovered = false

    private var color: Color {
        hovered ? Color(white: 0.96) : Color(white: 0.6)
    }

    var body: some View {
        Button(action: action) {
            label(color)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

struct PinnedIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(8, 4))
        path.addLine(to: p(16, 4))

        path.move(to: p(9, 4))
        path.addLine(to: p(9, 10))
        path.addLine(to: p(7, 14))
        path.addLine(to: p(7, 16))
        path.addLine(to: p(17, 16))
        path.addLine(to: p(17, 14))
        path.addLine(to: p(15, 10))
        path.addLine(to: p(15, 4))

        path.move(to: p(12, 16))
        path.addLine(to: p(12, 21))
        return path
    }
}

enum SidebarChatLeadingIcon { case none, pin, pinOnHover, bubble, unarchive }

struct RecentChatRowCallbacks {
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onUnarchive: () -> Void
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onToggleUnread: () -> Void
    let onOpenInFinder: () -> Void
    let onCopyWorkingDirectory: () -> Void
    let onCopySessionId: () -> Void
    let onCopyDeeplink: () -> Void
    let onForkLocal: () -> Void
    let onContextMenu: (NSPoint) -> Void
}

struct RecentChatRow: View, Equatable {
    let chat: Chat
    /// Pre-computed `currentRoute == .chat(chat.id)`. Lifted out of the row
    /// so the row's `Equatable` check can detect selection changes without
    /// having to subscribe to `AppState`.
    let isSelected: Bool
    var indent: CGFloat = 0
    var leadingIcon: SidebarChatLeadingIcon = .bubble
    /// Disables the hovered-row tint. The reorderable pinned list flips
    /// it on while a drag is active so dragging over another row doesn't
    /// read as "you can drop on this chat" — drops only land in the gaps.
    var suppressHoverStyling: Bool = false
    /// True for rows rendered inside the sidebar's archived section. The
    /// trailing hover button becomes "unarchive", drag is disabled (an
    /// archived chat has no slot to drop into) and the context menu is
    /// trimmed to actions that still make sense.
    var archivedRow: Bool = false
    let callbacks: RecentChatRowCallbacks
    /// Called from `.onDrag` the moment AppKit asks for the drag's
    /// `NSItemProvider`. The reorderable pinned list uses it to mark the
    /// row as the drag source so it can collapse its slot to 0 height
    /// while the drag is active.
    var onDragStart: (() -> Void)? = nil

    @State private var hovered = false
    @State private var pinHovered = false
    @State private var archiveHovered = false
    @State private var unarchiveHovered = false

    /// Closures are deliberately excluded from equality: they are recreated
    /// every parent render but capture `appState` (a stable reference) and
    /// chat id (a stable value), so a "stale" closure still does the right
    /// thing. Comparing only data fields lets SwiftUI skip body when none
    /// of them moved, even when the closure identities did.
    static func == (lhs: RecentChatRow, rhs: RecentChatRow) -> Bool {
        lhs.chat.id == rhs.chat.id
            && lhs.chat.title == rhs.chat.title
            && lhs.chat.hasActiveTurn == rhs.chat.hasActiveTurn
            && lhs.chat.hasUnreadCompletion == rhs.chat.hasUnreadCompletion
            && lhs.chat.createdAt == rhs.chat.createdAt
            && lhs.isSelected == rhs.isSelected
            && lhs.indent == rhs.indent
            && lhs.leadingIcon == rhs.leadingIcon
            && lhs.suppressHoverStyling == rhs.suppressHoverStyling
            && lhs.archivedRow == rhs.archivedRow
    }

    private var ageLabel: String { Self.relative(from: chat.createdAt) }

    @ViewBuilder
    private var trailingStatusView: some View {
        // Archive layered on top of the default trailing content
        // (spinner / unread dot / age label) and fades in/out via opacity so
        // it reads as a smooth crossfade on hover instead of a hard
        // view swap. Hit testing follows visibility so the button only
        // catches the cursor while the row is hovered.
        let archiveVisible = hovered && !archivedRow && !chat.hasActiveTurn

        ZStack(alignment: .trailing) {
            Group {
                if chat.hasActiveTurn {
                    SidebarChatRowSpinner()
                        .frame(width: 14, height: 14)
                        .frame(width: 28)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                } else if !archivedRow && chat.hasUnreadCompletion {
                    Circle()
                        .fill(Palette.pastelBlue)
                        .frame(width: 7, height: 7)
                        .frame(width: 28, height: 14)
                        .transition(.scale(scale: 0.0, anchor: .center).combined(with: .opacity))
                } else {
                    Text(ageLabel)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 28, alignment: .trailing)
                        .padding(.trailing, 5)
                        .transition(.opacity)
                }
            }
            .opacity(archiveVisible ? 0 : 1)
            .animation(.smooth(duration: 0.55, extraBounce: 0), value: chat.hasActiveTurn)
            .animation(.spring(response: 0.55, dampingFraction: 0.62), value: chat.hasUnreadCompletion)

            if !archivedRow && archiveVisible {
                // Render only while visible so hidden row actions do not
                // flood the accessibility tree during sidebar navigation.
                // The 22x22 frame around the 15.5pt icon gives a generous
                // halo so the cursor catches the button before it lands
                // on the glyph.
                Button(action: callbacks.onArchive) {
                    ArchiveIcon(size: 15.5)
                        .foregroundColor(archiveHovered ? Color(white: 0.94) : Color(white: 0.5))
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sidebarHover { archiveHovered = $0 }
                .help(L10n.t("Archive"))
            }
        }
        .animation(.easeOut(duration: 0.16), value: archiveVisible)
        .animation(.easeOut(duration: 0.12), value: archiveHovered)
    }

    var body: some View {
        RenderProbe.tick("RecentChatRow")
        let title = chat.title.isEmpty
            ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
            : chat.title
        return HStack(spacing: 10) {
            leadingIconView
            Text(verbatim: title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(isSelected ? .white : Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailingStatusView
        }
        .padding(.leading, 8 + indent)
        .padding(.trailing, 3)
        .frame(height: 35)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .padding(.trailing, 3)
        .onTapGesture(perform: callbacks.onSelect)
        .sidebarHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: pinHovered)
        // Window has `isMovableByWindowBackground = true`, so without an
        // NSView in the row that returns `mouseDownCanMoveWindow = false`
        // AppKit hijacks mouseDown for a window drag and SwiftUI's
        // `.onDrag` never fires.
        .background(WindowDragInhibitor())
        .onDrag {
            // Carry the chat's UUID as plain text. Drop targets parse it
            // back to a UUID and route to AppState (reorder / move-to-
            // project / pin). The provider's suggestedName is used as
            // the macOS drag preview's label. Archived rows return an
            // empty provider so drop targets can't decode a UUID and
            // the drag is effectively inert.
            if archivedRow { return NSItemProvider() }
            onDragStart?()
            let provider = NSItemProvider(object: chat.id.uuidString as NSString)
            provider.suggestedName = chat.title
            return provider
        } preview: {
            // 1pt transparent: macOS animates the drag preview settling
            // at the drop location for ~500ms and SwiftUI does not expose
            // a way to disable it. We hand it a 1pt invisible view here
            // so the system has nothing visible to fade. The actual chip
            // the user sees follows the cursor via `DragChipPanel`, which
            // we close instantly on drop.
            Color.clear.frame(width: 1, height: 1)
        }
        .contextMenu { nativeContextMenu }
    }

    @ViewBuilder
    private var nativeContextMenu: some View {
        Button(chat.isPinned ? "Unpin chat" : "Pin chat", action: callbacks.onTogglePin)
            .disabled(archivedRow)
        Button("Rename chat", action: callbacks.onRename)
        Button(archivedRow ? "Unarchive chat" : "Archive chat") {
            archivedRow ? callbacks.onUnarchive() : callbacks.onArchive()
        }
        if !archivedRow {
            Button(chat.hasUnreadCompletion ? "Mark as read" : "Mark as unread", action: callbacks.onToggleUnread)
        }
        Divider()
        Button("Open in Finder", action: callbacks.onOpenInFinder)
            .disabled(chat.cwd?.isEmpty != false)
        Button("Copy working directory", action: callbacks.onCopyWorkingDirectory)
            .disabled(chat.cwd?.isEmpty != false)
        Button("Copy session ID", action: callbacks.onCopySessionId)
            .disabled(chat.clawixThreadId == nil)
        Button("Copy direct link", action: callbacks.onCopyDeeplink)
            .disabled(chat.clawixThreadId == nil)
        Divider()
        Button("Fork conversation", action: callbacks.onForkLocal)
    }

    @ViewBuilder
    private var leadingIconView: some View {
        switch leadingIcon {
        case .none:
            EmptyView()
        case .pin:
            pinToggleButton(
                visible: true,
                color: pinHovered ? .white : Color(white: 0.5),
                help: L10n.t("Unpin")
            )
        case .pinOnHover:
            pinToggleButton(
                visible: hovered,
                color: pinHovered ? Color(white: 0.94) : Color(white: 0.5),
                help: L10n.t("Pin")
            )
        case .bubble:
            LucideIcon(.messageCircle, size: 11)
                .foregroundColor(Color(white: 0.58))
                .frame(width: 14, height: 14)
        case .unarchive:
            unarchiveButton()
                .offset(y: 1)
        }
    }

    private func unarchiveButton() -> some View {
        // Leading slot, so growing the layout frame would push the
        // title right. Pad outwards to a 28x22 halo for the hit
        // shape, then pad back inwards by the same amount so the
        // parent HStack still allocates 14x14. Matches the generous
        // hover catch of the archive button on the right.
        Button(action: callbacks.onUnarchive) {
            ArchiveUnarchiveMorphIcon(
                size: 16.5,
                hovered: hovered,
                iconHovered: unarchiveHovered
            )
                .frame(width: 14, height: 14)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .padding(.horizontal, -7)
                .padding(.vertical, -4)
        }
        .buttonStyle(.plain)
        .sidebarHover { unarchiveHovered = $0 }
        .help(L10n.t("Unarchive"))
    }

    private func pinToggleButton(visible: Bool, color: Color, help: String) -> some View {
        // `.disabled(!visible)` instead of `.allowsHitTesting(visible)` so the
        // button keeps its hover tracking area alive when invisible. With
        // `.allowsHitTesting(false)` toggling on/off based on the parent row's
        // hover state, the moment the cursor crosses into the icon the parent
        // briefly loses hover, the icon flips back to non hit testable, and
        // the cursor falls through, producing the flicker the user reported.
        Button(action: callbacks.onTogglePin) {
            PinIcon(size: 15.0, lineWidth: 1.5)
                .foregroundColor(color)
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
                .opacity(visible ? 1 : 0)
        }
        .buttonStyle(.plain)
        .sidebarHover { pinHovered = $0 }
        .disabled(!visible)
        .accessibilityHidden(!visible)
        .help(help)
    }

    private var rowBackground: Color {
        // Both selected and hover use white-opacity so the chat-row glow
        // stays soft and consistent with the rest of the sidebar tabs.
        if isSelected { return Color.white.opacity(0.05) }
        if hovered && !suppressHoverStyling { return Color.white.opacity(0.035) }
        return .clear
    }

    private static func relative(from date: Date) -> String {
        L10n.relativeAge(elapsed: Date().timeIntervalSince(date))
    }
}

struct SidebarChatRowSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.28),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.79)
                .stroke(Color(white: 0.75),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 11, height: 11)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
