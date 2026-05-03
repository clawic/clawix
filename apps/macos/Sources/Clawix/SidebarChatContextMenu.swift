import SwiftUI
import AppKit

// MARK: - Right-click catcher

/// Sits in front of a SwiftUI row to claim right-clicks without breaking
/// the row's left-click, hover or drag gestures. `hitTest` returns self
/// only while the right mouse button is pressed; everything else falls
/// through to SwiftUI underneath.
struct SidebarRightClickCatcher: NSViewRepresentable {
    let onRightClick: (NSPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        Catcher(action: onRightClick)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Catcher)?.action = onRightClick
    }

    final class Catcher: NSView {
        var action: (NSPoint) -> Void

        init(action: @escaping (NSPoint) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let rightDown = (NSEvent.pressedMouseButtons & (1 << 1)) != 0
            return rightDown ? self : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action(NSEvent.mouseLocation)
        }

        override var mouseDownCanMoveWindow: Bool { false }
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}

// MARK: - Context menu content (rendered inside the panel's NSHostingView)

struct SidebarChatContextMenuContent: View {
    let chat: Chat
    let isArchived: Bool
    let onTogglePin: () -> Void
    let onRename: () -> Void
    let onArchiveToggle: () -> Void
    let onMarkUnread: () -> Void
    let onOpenInFinder: () -> Void
    let onCopyWorkingDirectory: () -> Void
    let onCopySessionId: () -> Void
    let onCopyDeeplink: () -> Void
    let onForkLocal: () -> Void
    let onForkWorktree: () -> Void
    let onOpenMiniWindow: () -> Void

    @State private var hovered: String?

    private struct Item {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let shortcut: String?
        let enabled: Bool
        let action: () -> Void
    }

    private var firstGroup: [Item] {
        var items: [Item] = [
            Item(id: "pin",
                 icon: "pin",
                 title: chat.isPinned ? "Unpin chat" : "Pin chat",
                 shortcut: "⌥⌘P",
                 enabled: !isArchived,
                 action: onTogglePin),
            Item(id: "rename",
                 icon: "pencil",
                 title: "Rename chat",
                 shortcut: "⌥⌘R",
                 enabled: chat.clawixThreadId != nil,
                 action: onRename),
            Item(id: "archive",
                 icon: "archivebox",
                 title: isArchived ? "Unarchive chat" : "Archive chat",
                 shortcut: "⇧⌘A",
                 enabled: true,
                 action: onArchiveToggle),
        ]
        if !isArchived {
            items.append(
                Item(id: "unread",
                     icon: "circle.fill",
                     title: chat.hasUnreadCompletion ? "Mark as read" : "Mark as unread",
                     shortcut: nil,
                     enabled: true,
                     action: onMarkUnread)
            )
        }
        return items
    }

    private var secondGroup: [Item] {
        let hasCwd = (chat.cwd?.isEmpty == false)
        let hasThread = chat.clawixThreadId != nil
        return [
            Item(id: "finder",
                 icon: "folder",
                 title: "Open in Finder",
                 shortcut: nil,
                 enabled: hasCwd,
                 action: onOpenInFinder),
            Item(id: "copyCwd",
                 icon: "doc.on.doc",
                 title: "Copy working directory",
                 shortcut: "⇧⌘C",
                 enabled: hasCwd,
                 action: onCopyWorkingDirectory),
            Item(id: "copyId",
                 icon: "doc.on.doc",
                 title: "Copy session ID",
                 shortcut: "⌥⌘C",
                 enabled: hasThread,
                 action: onCopySessionId),
            Item(id: "copyLink",
                 icon: "doc.on.doc",
                 title: "Copy deeplink",
                 shortcut: "⌥⌘L",
                 enabled: hasThread,
                 action: onCopyDeeplink),
        ]
    }

    private var thirdGroup: [Item] {
        [
            Item(id: "forkLocal",
                 icon: "laptopcomputer",
                 title: "Fork into local",
                 shortcut: nil,
                 enabled: true,
                 action: onForkLocal),
            Item(id: "forkWorktree",
                 icon: "arrow.triangle.branch",
                 title: "Fork into new worktree",
                 shortcut: nil,
                 enabled: true,
                 action: onForkWorktree),
        ]
    }

    private var fourthGroup: [Item] {
        [
            Item(id: "miniWindow",
                 icon: "macwindow.on.rectangle",
                 title: "Open in mini window",
                 shortcut: nil,
                 enabled: true,
                 action: onOpenMiniWindow),
        ]
    }

    var body: some View {
        let groups = [firstGroup, secondGroup, thirdGroup, fourthGroup]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                if idx > 0 {
                    MenuStandardDivider()
                        .padding(.vertical, 4)
                }
                ForEach(group, id: \.id) { item in
                    row(item)
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 268)
        .menuStandardBackground(blurBehindWindow: true)
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        Button(action: item.action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                rowIcon(item)
                    .frame(width: 18, alignment: .center)
                    .opacity(item.enabled ? 1 : 0.4)
                Text(item.title)
                    .font(.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .opacity(item.enabled ? 1 : 0.5)
                Spacer(minLength: 0)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10))
                        .foregroundColor(MenuStyle.rowSubtle)
                        .opacity(item.enabled ? 1 : 0.5)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == item.id && item.enabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .onHover { hovering in
            if hovering && item.enabled { hovered = item.id }
            else if hovered == item.id { hovered = nil }
        }
    }

    @ViewBuilder
    private func rowIcon(_ item: Item) -> some View {
        switch item.icon {
        case "pencil":
            PencilIconView(color: MenuStyle.rowIcon, lineWidth: 1.0)
                .frame(width: 11, height: 11)
        case "circle.fill":
            // Unread dot uses the same pastel blue as the sidebar indicator
            // so the menu reads as "this is the unread state".
            Circle()
                .fill(Palette.pastelBlue)
                .frame(width: 7, height: 7)
        default:
            IconImage(item.icon, size: 11)
                .foregroundColor(MenuStyle.rowIcon)
        }
    }
}

// MARK: - Borderless panel host

/// Hosts `SidebarChatContextMenuContent` in a borderless non-activating
/// panel so the menu can position itself at the right-click point and
/// escape the sidebar's scroll-view clip. Click-outside, Escape and
/// any selected item all dismiss the panel.
@MainActor
final class SidebarChatContextMenuPanel: NSObject {
    private static var current: SidebarChatContextMenuPanel?

    private let panel: NSPanel
    private let shadowMargin: CGFloat
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    private init(rootView: AnyView, size: NSSize, shadowMargin: CGFloat) {
        self.shadowMargin = shadowMargin
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        super.init()
    }

    static func present(
        at clickPoint: NSPoint,
        chat: Chat,
        isArchived: Bool,
        appState: AppState
    ) {
        // Only one menu open at a time. Closing first releases its event
        // monitors so they don't fight with the new instance's monitors.
        current?.close()

        var holder: SidebarChatContextMenuPanel!
        let dismiss: () -> Void = { holder?.close() }

        let content = SidebarChatContextMenuContent(
            chat: chat,
            isArchived: isArchived,
            onTogglePin: {
                appState.togglePin(chatId: chat.id)
                dismiss()
            },
            onRename: {
                appState.pendingRenameChat = chat
                dismiss()
            },
            onArchiveToggle: {
                if isArchived {
                    appState.unarchiveChat(chatId: chat.id)
                } else {
                    appState.archiveChat(chatId: chat.id)
                }
                dismiss()
            },
            onMarkUnread: {
                appState.toggleChatUnread(chatId: chat.id)
                dismiss()
            },
            onOpenInFinder: {
                if let cwd = chat.cwd, !cwd.isEmpty {
                    let path = (cwd as NSString).expandingTildeInPath
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                dismiss()
            },
            onCopyWorkingDirectory: {
                if let cwd = chat.cwd, !cwd.isEmpty { setPasteboardString(cwd) }
                dismiss()
            },
            onCopySessionId: {
                if let id = chat.clawixThreadId { setPasteboardString(id) }
                dismiss()
            },
            onCopyDeeplink: {
                if let id = chat.clawixThreadId {
                    setPasteboardString("clawix://chat/\(id)")
                }
                dismiss()
            },
            onForkLocal: { dismiss() },
            onForkWorktree: { dismiss() },
            onOpenMiniWindow: { dismiss() }
        )

        // The popup itself draws a 0/10 offset shadow with 18 px radius,
        // which paints outside the SwiftUI view's layout bounds. We wrap
        // it in a transparent padding so the hosting panel's frame is big
        // enough to contain the shadow without clipping it.
        let shadowMargin: CGFloat = 30
        let padded = AnyView(
            content
                .padding(.horizontal, shadowMargin)
                .padding(.top, shadowMargin - 8)
                .padding(.bottom, shadowMargin + 8)
        )

        let measureController = NSHostingController(rootView: padded)
        let fitting = measureController.sizeThatFits(in: NSSize(width: 400, height: 1200))
        let size = NSSize(width: ceil(fitting.width), height: ceil(fitting.height))

        let p = SidebarChatContextMenuPanel(
            rootView: padded,
            size: size,
            shadowMargin: shadowMargin
        )
        holder = p
        current = p
        p.show(at: clickPoint)
    }

    private func show(at clickPoint: NSPoint) {
        let size = panel.frame.size
        // The visible menu sits inset by `shadowMargin` from each side of
        // the panel (with the bottom inset being `shadowMargin + 8` and
        // the top `shadowMargin - 8`, matching the asymmetric padding we
        // wrap the content in for the shadow). Position so the menu's
        // visible top-left corner lands at the right-click point.
        let topPadding = shadowMargin - 8
        var origin = NSPoint(
            x: clickPoint.x - shadowMargin,
            y: clickPoint.y + topPadding - size.height
        )

        let hostScreen = NSScreen.screens.first { NSPointInRect(clickPoint, $0.frame) }
            ?? NSScreen.main
        if let screen = hostScreen {
            let visible = screen.visibleFrame
            let menuVisibleWidth = size.width - 2 * shadowMargin
            // Keep the visible menu inside the screen, with a small inset.
            let inset: CGFloat = 6
            let minX = visible.minX + inset - shadowMargin
            let maxX = visible.maxX - inset - menuVisibleWidth - shadowMargin
            origin.x = min(max(origin.x, minX), max(minX, maxX))

            // If we'd drop below the screen, flip and anchor the visible
            // menu's bottom-left at the click point instead.
            if origin.y < visible.minY + inset - (shadowMargin + 8) {
                origin.y = clickPoint.y - (shadowMargin + 8)
                let maxY = visible.maxY - inset - size.height + (shadowMargin + 8)
                if origin.y > maxY { origin.y = maxY }
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        installMonitors()
    }

    private func installMonitors() {
        // Clicks anywhere in our app outside the panel close it, but the
        // event still flows so the row underneath responds to a normal
        // selection click if that's what the user did next.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel { return event }
            self.close()
            return event
        }

        // Clicks landing in another app (the local monitor doesn't see
        // those) also dismiss the menu.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.close()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 = Escape.
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }
}

private func setPasteboardString(_ value: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(value, forType: .string)
}
