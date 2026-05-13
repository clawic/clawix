import SwiftUI
import UniformTypeIdentifiers

struct ChatDropTarget<Content: View>: View {
    let accept: (UUID) -> Bool
    @ViewBuilder let content: () -> Content

    @State private var isTargeted: Bool = false

    var body: some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isTargeted ? Color(white: 0.30) : Color.clear)
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.10), value: isTargeted)
            .onDrop(of: [.text], delegate: ChatDropDelegate(
                isTargeted: $isTargeted,
                accept: accept
            ))
    }
}

struct ChatDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let accept: (UUID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [.url]) { return false }
        return info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let s = item as? String,
                  let uuid = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                _ = accept(uuid)
            }
        }
        return true
    }
}

final class PinnedRowFrameStore: ObservableObject {
    var byId: [UUID: CGRect] = [:]
}

struct PinnedReorderableList: View, Equatable {
    /// Injected from the parent. Not observed: callbacks go through the
    /// reference, but state reads are passed in explicitly so this view
    /// stops re-evaluating on every `AppState` publish (per-token chats
    /// updates were rebuilding the pinned list at ~16 Hz during streaming).
    let appState: AppState
    let pinned: [Chat]
    let selectedChatId: UUID?

    static func == (lhs: PinnedReorderableList, rhs: PinnedReorderableList) -> Bool {
        lhs.selectedChatId == rhs.selectedChatId
            && Self.pinnedEqual(lhs.pinned, rhs.pinned)
    }

    /// Same shape as `RecentChatRow.==`: only fields the row actually
    /// renders, skipping `messages`, `cwd`, `branch`, etc. Streaming
    /// mutates those continually; comparing them would defeat the gate.
    private static func pinnedEqual(_ lhs: [Chat], _ rhs: [Chat]) -> Bool {
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

    @State private var draggingId: UUID? = nil
    @State private var targetIndex: Int? = nil
    @State private var pendingClearTask: DispatchWorkItem? = nil
    @State private var mouseUpMonitor: Any? = nil
    /// Custom drag chip rendered in a borderless `NSPanel` that follows
    /// the cursor. Bypasses macOS's built-in drag preview so we control
    /// when it disappears (instantly on drop), instead of the system's
    /// ~500ms settle animation.
    @State private var dragChipPanel: DragChipPanel? = nil
    /// Each row reports its window-coord frame here so `handleDragStart`
    /// can compute the cursor's offset within the row at drag start.
    /// Reference-type bag (no `@Published`) so mutating `byId` is
    /// invisible to SwiftUI and the per-frame preference firehose
    /// stays cheap.
    @StateObject private var rowFrames = PinnedRowFrameStore()
    /// Holds a weak ref to the surrounding sidebar `NSScrollView`,
    /// captured by `EnclosingScrollViewLocator` once the view enters
    /// the AppKit hierarchy. Drives the edge auto-scroll while a
    /// pinned-row drag is active.
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    private let baseSpacing: CGFloat = 0
    /// Approximate slot size. `RecentChatRow` renders at 35 pt
    /// (`frame(height: 35)`) with 0 pt of baseSpacing so adjacent rows
    /// share an edge. The gap matches the row so the source's collapse
    /// and the gap's opening cancel out and the list height stays
    /// constant during an internal drag.
    private let gapHeight: CGFloat = 35
    private let rowHeight: CGFloat = 35
    /// Delay before a deferred clear fires when the cursor exits a slot
    /// zone. Short enough that leaving the list closes the gap quickly,
    /// long enough to absorb the brief inter-row transition without a
    /// visible flash.
    private static let exitClearDelay: TimeInterval = 0.10

    /// Smooth curve for the gap migrating from one slot to the next.
    /// Applied via `.animation(_:value:)` on the parent so every state
    /// change to `targetIndex` / `draggingId` interpolates with the
    /// same curve. Drop and cancel paths use a `disablesAnimations`
    /// transaction to override and commit instantly.
    private static let moveAnimation: Animation = .easeInOut(duration: 0.20)

    var body: some View {
        RenderProbe.tick("PinnedReorderableList")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pinned.enumerated()), id: \.element.id) { (i, chat) in
                slotZone(chat: chat, slot: i)
            }
            trailingSlotZone
        }
        // Animations are applied explicitly per-call (`withAnimation`)
        // so start/drop are instant while only the gap slide during
        // hover interpolates. The `withAnimation(moveAnimation)` in
        // `setTarget` opens a transaction scoped to that closure: it
        // animates the resulting `targetIndex` change (gap height) and
        // closes when the closure returns. Subsequent state mutations
        // in `performReorder` (plain assignments) do not inherit it,
        // so the row insertion lands instant without any extra
        // transaction trickery.
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cancelPendingClear()
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(PinnedRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: pinned.map(\.id)) { _, _ in
            // Defensive cleanup: any pinned-array reorder (ours or an
            // external sync) clears lingering drag state. Belt-and-
            // suspenders against the "extra gap stays forever" bug.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cancelPendingClear()
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    /// One slot zone, with two SEPARATE drop targets:
    ///
    /// - `gapPlaceholder(at: slot)` accepts drops with a constant
    ///   `slot` output. When the gap is open (32 pt) the cursor can
    ///   dwell inside it without flipping the target.
    /// - The row underneath uses a fixed `rowHeight / 2` threshold to
    ///   pick `slot` (top half, gap above this row) or `slot + 1`
    ///   (bottom half, gap below). Threshold is constant regardless
    ///   of whether the gap is open, so there is no oscillation when
    ///   the cursor sits right on a half boundary.
    @ViewBuilder
    private func slotZone(chat: Chat, slot: Int) -> some View {
        let isDragging = draggingId == chat.id
        let dragActive = draggingId != nil
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            RecentChatRow(
                chat: chat,
                isSelected: selectedChatId == chat.id,
                leadingIcon: .pin,
                suppressHoverStyling: dragActive,
                callbacks: makeRecentChatCallbacks(appState: appState, chat: chat, archived: false),
                onDragStart: { handleDragStart(chat: chat) }
            )
            .equatable()
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PinnedRowFrameKey.self,
                        value: [chat.id: proxy.frame(in: .global)]
                    )
                }
            )
            .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                computeSlot: { y in y < rowHeight / 2 ? slot : slot + 1 },
                onSet: { setTarget(slot: $0) },
                onExit: { scheduleExitClear() },
                onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
            ))
        }
    }

    /// Slot after the last row: trailing-end gap plus a small strip so
    /// the user can drop "at the end" without having to land on the
    /// last row's bottom half pixel-perfectly.
    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = pinned.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            // Trailing strip doubles as: (a) a drop target so dropping
            // "at the end" doesn't require landing on the last row's
            // bottom-half pixel-perfectly, and (b) the visible bottom
            // gap of the Pinned section. Sized to `sectionEdgePadding`
            // so Pinned's bottom gap matches every other collapsible
            // section. Earlier this was a hardcoded 14pt strip stacked
            // above the parent's `sectionEdgePadding` spacer, leaving
            // Pinned with ~14pt extra below the last row vs Chats /
            // Projects / Archived.
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: PinnedRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onExit: { scheduleExitClear() },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == pinned.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear
            .frame(height: isOpen ? gapHeight : baseHeight)
    }

    private func handleDragStart(chat: Chat) {
        cancelPendingClear()
        let src = pinned.firstIndex(where: { $0.id == chat.id })
        // Instant: source row collapses to 0 + gap opens at its slot in
        // the same render. The drag preview takes over with no fade.
        // Cleanup paths after a drop are: `performReorder`, the
        // `mouseUpMonitor` for drops outside any zone, and the
        // `.onChange(of: pinned…)` defensive sweep. No watchdog timer
        // here because any fixed delay either fires mid-drag (the
        // source reappears under the cursor) or is too long to actually
        // catch a stuck state.
        targetIndex = src
        draggingId = chat.id
        // Render our own chip in a borderless panel that polls the
        // cursor each frame. macOS still runs its drag preview animation,
        // but we hand it a 1pt transparent view (see `.onDrag`'s
        // `preview:`) so there is nothing to fade. The visible chip is
        // ours and disappears the instant `cleanupDragChip()` fires.
        // Anchor offset: cursor position relative to the row's top-left
        // at drag start. Carrying this through to the panel keeps the
        // cursor at the same point on the chip the user originally
        // clicked, instead of a fixed right-of-cursor offset.
        let (anchor, width) = grabAnchor(for: chat)
        dragChipPanel?.close()
        dragChipPanel = DragChipPanel(chat: chat, grabAnchor: anchor, width: width)
        dragChipPanel?.show()
        // Edge auto-scroll. The same 60Hz cursor poll the chip uses to
        // follow the cursor also drives this; nudges the surrounding
        // sidebar `NSScrollView` while the cursor sits in the top or
        // bottom edge zone, so reordering across a long pinned list
        // doesn't require manual scrolling.
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    /// Cursor offset (in chip-local coords, top-left origin) and the
    /// row's measured width at drag start. The anchor keeps the cursor
    /// pinned to the same point on the chip the user clicked, and the
    /// width sizes the chip 1:1 with the row underneath. Falls back to
    /// sensible defaults if we don't yet have a frame measurement
    /// (defensive only — every row reports its frame on appear).
    private func grabAnchor(for chat: Chat) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[chat.id] else {
            return (CGPoint(x: 30, y: 16), fallbackWidth)
        }
        // Compute the offset entirely in SwiftUI window coordinates
        // (top-left origin) to avoid screen<->window conversion errors
        // around title bars / contentLayoutRect. Convert the cursor from
        // screen coords into the same SwiftUI window space, then take
        // the diff against the row's frame.
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 16), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        // Screen -> window (still bottom-left origin).
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        // Window bottom-left -> SwiftUI top-left.
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        // Anchor in chip-local coords (top-left).
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        cancelPendingClear()
        // Drop targets keep firing `dropUpdated` for one more frame after
        // the drop completes (the layout reflow shifts which zone the
        // cursor sits over, SwiftUI dispatches one trailing event).
        // Without this guard that trailing event reopens the gap below
        // the row we just dropped and only a click clears it.
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        // Animated: the gap slides between positions as the cursor moves
        // over different slot zones. Source row collapse already happened
        // in `handleDragStart` so it doesn't get re-triggered here.
        withAnimation(Self.moveAnimation) {
            targetIndex = slot
        }
    }

    private func scheduleExitClear() {
        // Intentionally a no-op. SwiftUI fires `dropExited` on the zone
        // we just dropped onto (same event as the drop itself), which
        // means scheduling a state mutation here races with
        // `performReorder` and lands a phantom gap below the dropped row
        // for the gap between the two callbacks. Cleanup on cursor exit
        // is handled by the `mouseUpMonitor` (release outside any zone)
        // and `performReorder` (release inside a zone).
    }

    private func cancelPendingClear() {
        pendingClearTask?.cancel()
        pendingClearTask = nil
    }

    private func performReorder(uuid: UUID, beforeIndex: Int) {
        cancelPendingClear()
        cleanupDragChip()
        let beforeChatId: UUID? = (beforeIndex < pinned.count) ? pinned[beforeIndex].id : nil
        // Plain assignments. `setTarget`'s `withAnimation(moveAnimation)`
        // closure has already returned by the time the drop fires, so
        // there is no live transaction to override here. Row at new
        // index, no gap, source uncollapsed, all in one frame.
        appState.reorderPinned(chatId: uuid, beforeChatId: beforeChatId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cancelPendingClear()
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

struct PinnedRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onExit: () -> Void
    let onPerform: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let s = item as? String,
                  let uuid = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                onPerform(uuid, slot)
            }
        }
        return true
    }
}

final class EnclosingScrollViewBox: ObservableObject {
    weak var scrollView: NSScrollView?
}

struct EnclosingScrollViewLocator: NSViewRepresentable {
    let box: EnclosingScrollViewBox

    func makeNSView(context: Context) -> NSView { LocatorView(box: box) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class LocatorView: NSView {
        let box: EnclosingScrollViewBox
        init(box: EnclosingScrollViewBox) {
            self.box = box
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.locate() }
        }
        private func locate() {
            var current: NSView? = self.superview
            while let v = current {
                if let sv = v as? NSScrollView {
                    box.scrollView = sv
                    return
                }
                current = v.superview
            }
        }
    }
}

final class PinnedDragAutoScroller {
    private weak var box: EnclosingScrollViewBox?
    private var timer: Timer?

    /// Distance from the top/bottom edge at which auto-scroll engages.
    /// ~3 pinned rows: wide enough that the user can park the cursor
    /// near the edge without having to nail it pixel-perfect.
    private let edgeZone: CGFloat = 96
    /// Speed (px/s) at the boundary of `edgeZone`. Even a slight nudge
    /// into the zone scrolls visibly instead of crawling.
    private let minSpeed: CGFloat = 600
    /// Peak scroll speed (px/s) right at the edge. ~3000 traverses
    /// the visible sidebar in roughly a third of a second, so a long
    /// pinned list moves quickly when the cursor is pinned to the edge.
    private let maxSpeed: CGFloat = 3000

    init(box: EnclosingScrollViewBox) {
        self.box = box
    }

    func start() {
        timer?.invalidate()
        let dt: TimeInterval = 1.0 / 60.0
        timer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            self?.tick(dt: dt)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(dt: TimeInterval) {
        guard let sv = box?.scrollView, let win = sv.window else { return }
        let cursorScreen = NSEvent.mouseLocation
        let cursorWindow = win.convertPoint(fromScreen: cursorScreen)
        let clip = sv.contentView
        let cursorClip = clip.convert(cursorWindow, from: nil)
        let bounds = clip.bounds
        guard cursorClip.x >= bounds.minX, cursorClip.x <= bounds.maxX,
              cursorClip.y >= bounds.minY, cursorClip.y <= bounds.maxY
        else { return }

        // Distance from the visible top edge, regardless of clip view
        // orientation. SwiftUI hosting views are flipped (origin at top),
        // but support both orientations defensively.
        let yFromTop: CGFloat = clip.isFlipped
            ? (cursorClip.y - bounds.minY)
            : (bounds.maxY - cursorClip.y)
        let visibleH = bounds.height

        // Linear ramp from `minSpeed` (factor=0, just inside the zone)
        // to `maxSpeed` (factor=1, glued to the edge). A floor speed
        // means scrolling kicks in immediately when the cursor enters
        // the zone instead of crawling for the first few pixels.
        var delta: CGFloat = 0
        if yFromTop < edgeZone {
            let factor = max(0, min(1, (edgeZone - yFromTop) / edgeZone))
            let speed = minSpeed + (maxSpeed - minSpeed) * factor
            delta = -speed * CGFloat(dt)
        } else if yFromTop > visibleH - edgeZone {
            let factor = max(0, min(1, (yFromTop - (visibleH - edgeZone)) / edgeZone))
            let speed = minSpeed + (maxSpeed - minSpeed) * factor
            delta = speed * CGFloat(dt)
        }
        guard abs(delta) > 0.05 else { return }

        let docHeight = sv.documentView?.frame.height ?? 0
        let maxY = max(0, docHeight - visibleH)
        // In a flipped clip view, increasing bounds.origin.y reveals
        // content that was below; in a non-flipped one it's the
        // opposite. Flip the sign so a positive `delta` always means
        // "scroll towards the bottom".
        let signedDelta: CGFloat = clip.isFlipped ? delta : -delta
        let currentY = bounds.origin.y
        let newY = max(0, min(maxY, currentY + signedDelta))
        guard abs(newY - currentY) > 0.05 else { return }
        clip.scroll(to: NSPoint(x: bounds.origin.x, y: newY))
        sv.reflectScrolledClipView(clip)
    }
}

struct OrganizeFunnelIcon: View {
    var body: some View {
        VStack(spacing: 1.76) {
            Capsule(style: .continuous).frame(width: 11.0, height: 1.1)
            Capsule(style: .continuous).frame(width: 7.04, height: 1.1)
            Capsule(style: .continuous).frame(width: 3.52, height: 1.1)
        }
    }
}

struct WindowDragInhibitor: NSViewRepresentable {
    var onRightClick: ((NSPoint) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        _NoWindowDragView(onRightClick: onRightClick)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? _NoWindowDragView)?.onRightClick = onRightClick
    }

    private final class _NoWindowDragView: NSView {
        var onRightClick: ((NSPoint) -> Void)?

        init(onRightClick: ((NSPoint) -> Void)?) {
            self.onRightClick = onRightClick
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            nextResponder?.mouseDown(with: event)
        }
        override func mouseDragged(with event: NSEvent) {
            nextResponder?.mouseDragged(with: event)
        }
        override func mouseUp(with event: NSEvent) {
            nextResponder?.mouseUp(with: event)
        }
        override func rightMouseDown(with event: NSEvent) {
            if let onRightClick {
                onRightClick(NSEvent.mouseLocation)
            } else {
                nextResponder?.rightMouseDown(with: event)
            }
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { _DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class _DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

struct PinnedRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

final class DragChipPanel {
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>
    private var timer: Timer?
    /// Cursor offset within the chip (chip-local, top-left origin)
    /// captured at drag start.
    private let grabAnchor: CGPoint
    /// Transparent margin around the chip body inside the panel so the
    /// drop shadow (radius 14 + y offset 8) has room to render. Without
    /// it the panel's frame clips the shadow flush at the chip edge.
    private static let shadowInset: CGFloat = 24

    /// Designated init. Takes any SwiftUI view as the chip body so the
    /// same panel can render either a chat row preview or a project row
    /// preview. `fallbackHeight` is the height used when the hosting
    /// view's `fittingSize` isn't available yet (a measurement race
    /// every chip type works around).
    init(content: AnyView, grabAnchor: CGPoint, width: CGFloat, fallbackHeight: CGFloat) {
        self.grabAnchor = grabAnchor
        host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        // Width is pinned to the row's measured width plus the shadow
        // inset on each side so the shadow doesn't get clipped at the
        // panel edge. Height comes from the natural fitting size, or
        // `fallbackHeight + 2*inset` if measurement isn't ready yet.
        let measured = host.fittingSize
        let panelWidth = measured.width > 0 ? measured.width : width + Self.shadowInset * 2
        let panelHeight = measured.height > 0 ? measured.height : fallbackHeight + Self.shadowInset * 2
        let size = CGSize(width: panelWidth, height: panelHeight)

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
        // Borderless panels still inherit a default fade-out from
        // `orderOut(_:)`. Force `.none` so the chip disappears the same
        // frame the drop lands; otherwise the chip lingers for a beat
        // and reads as "the row I just dropped is animating in".
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host
    }

    convenience init(chat: Chat, grabAnchor: CGPoint, width: CGFloat) {
        let chip = DragChipView(chat: chat, width: width, shadowInset: Self.shadowInset)
        self.init(content: AnyView(chip), grabAnchor: grabAnchor, width: width, fallbackHeight: 35)
    }

    convenience init(project: Project, grabAnchor: CGPoint, width: CGFloat) {
        let chip = ProjectDragChipView(project: project, width: width, shadowInset: Self.shadowInset)
        self.init(content: AnyView(chip), grabAnchor: grabAnchor, width: width, fallbackHeight: 35)
    }

    func show() {
        updatePosition()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    private func updatePosition() {
        let cursor = NSEvent.mouseLocation
        let frame = panel.frame
        // grabAnchor is in chip-local coords, top-left origin. The chip
        // sits inset by `shadowInset` inside the panel (so the shadow
        // has room to render), so the cursor's target point in
        // panel-local coords is shifted by that inset on both axes.
        // Translate to AppKit screen coords (bottom-left origin) so the
        // cursor stays at the same point on the chip the user originally
        // clicked when the drag began.
        let inset = Self.shadowInset
        let new = NSRect(
            x: cursor.x - grabAnchor.x - inset,
            y: cursor.y - (frame.height - grabAnchor.y - inset),
            width: frame.width,
            height: frame.height
        )
        panel.setFrame(new, display: false)
    }
}

struct DragChipView: View {
    let chat: Chat
    let width: CGFloat
    /// Transparent breathing room around the chip so the drop shadow
    /// extends beyond the host panel's content view bounds without
    /// being clipped.
    let shadowInset: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            PinIcon(size: 12.5)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 14, height: 14)
            Text(chat.title.isEmpty
                 ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
                 : chat.title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
            ArchiveIcon(size: 14.5)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 14, height: 14)
                .padding(.trailing, 2)
        }
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(height: 35)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }
}

struct ProjectDragChipView: View {
    let project: Project
    let width: CGFloat
    let shadowInset: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            FolderMorphIcon(size: 14.5, progress: 0, lineWidthScale: 1.027)
                .foregroundColor(Color(white: 0.5))
                .frame(width: 15, height: 15)
            Text(project.name)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 35)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }
}

struct ProjectRowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

final class ProjectRowFrameStore: ObservableObject {
    var byId: [UUID: CGRect] = [:]
}

struct ProjectReorderableList<RowContent: View>: View {
    let appState: AppState
    let projects: [Project]
    @ViewBuilder let row: (Project) -> RowContent

    @State private var draggingId: UUID? = nil
    @State private var targetIndex: Int? = nil
    @State private var mouseUpMonitor: Any? = nil
    @State private var dragChipPanel: DragChipPanel? = nil
    @StateObject private var rowFrames = ProjectRowFrameStore()
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    /// Vertical breathing room between projects when no drag is active.
    /// Matches the `LazyVStack` spacing in the parent's non-custom
    /// branch so switching modes doesn't shift the layout.
    private let baseSpacing: CGFloat = 0
    /// Open-gap height during drag. Matches the project header (35 pt)
    /// with 0 pt baseSpacing so adjacent rows share an edge and the
    /// source's collapse plus the gap's opening cancel out, keeping the
    /// list height stable.
    private let gapHeight: CGFloat = 35
    /// Threshold for splitting a row into top-half / bottom-half slot
    /// zones. Used by the row-level drop delegate to choose between
    /// "gap above this row" and "gap below this row" depending on
    /// where the cursor is vertically.
    private let rowHeight: CGFloat = 35

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { (i, project) in
                slotZone(project: project, slot: i)
            }
            trailingSlotZone
        }
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(ProjectRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: projects.map(\.id)) { _, _ in
            // Defensive sweep: any external mutation to the projects
            // array (rename, delete, Codex roots refresh) clears
            // lingering drag state so a stale gap can never persist.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    @ViewBuilder
    private func slotZone(project: Project, slot: Int) -> some View {
        let isDragging = draggingId == project.id
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            row(project)
                .background(WindowDragInhibitor())
                .opacity(isDragging ? 0 : 1)
                .frame(height: isDragging ? 0 : nil, alignment: .top)
                .clipped()
                .allowsHitTesting(!isDragging)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ProjectRowFrameKey.self,
                            value: [project.id: proxy.frame(in: .global)]
                        )
                    }
                )
                .onDrag {
                    handleDragStart(project: project)
                    // Register `public.url` data DIRECTLY rather than
                    // wrapping an `NSURL` instance. `NSItemProvider(object:
                    // NSURL)` bridges through AppKit's pasteboard layer,
                    // which auto-promotes URLs to `public.utf8-plain-text`
                    // so other text drop targets (`ChatDropTarget`) flip
                    // their `isTargeted` highlight when a project is being
                    // reordered. Going through `registerDataRepresentation`
                    // exposes ONLY `public.url`, keeping the drag invisible
                    // to chat drop targets.
                    let provider = NSItemProvider()
                    let urlString = "\(clawixProjectURLScheme)://\(project.id.uuidString)"
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.url.identifier,
                        visibility: .ownProcess
                    ) { completion in
                        completion(urlString.data(using: .utf8), nil)
                        return nil
                    }
                    provider.suggestedName = project.name
                    return provider
                } preview: {
                    // 1pt transparent: macOS animates the system drag
                    // preview settling at drop for ~500ms; we hand it
                    // nothing visible so the only chip the user sees
                    // is our `DragChipPanel`, which closes instantly.
                    Color.clear.frame(width: 1, height: 1)
                }
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { y in y < rowHeight / 2 ? slot : slot + 1 },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = projects.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
            // Trailing strip doubles as drop target for "at the end"
            // and as the section's visible bottom gap. Sized to
            // `sectionEdgePadding` for parity with every other
            // collapsible section; see the matching strip in
            // `PinnedReorderableList.trailingSlotZone` for the rationale.
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ProjectRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { uuid, chosen in performReorder(uuid: uuid, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == projects.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear.frame(height: isOpen ? gapHeight : baseHeight)
    }

    private func handleDragStart(project: Project) {
        let src = projects.firstIndex(where: { $0.id == project.id })
        targetIndex = src
        draggingId = project.id
        let (anchor, width) = grabAnchor(for: project)
        dragChipPanel?.close()
        dragChipPanel = DragChipPanel(project: project, grabAnchor: anchor, width: width)
        dragChipPanel?.show()
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    private func grabAnchor(for project: Project) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[project.id] else {
            return (CGPoint(x: 30, y: 16), fallbackWidth)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 16), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        withAnimation(projectReorderMoveAnimation) {
            targetIndex = slot
        }
    }

    private func performReorder(uuid: UUID, beforeIndex: Int) {
        cleanupDragChip()
        let beforeProjectId: UUID? = (beforeIndex < projects.count) ? projects[beforeIndex].id : nil
        appState.reorderProject(projectId: uuid, beforeProjectId: beforeProjectId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

struct ProjectRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onPerform: (UUID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
            guard let data,
                  let s = String(data: data, encoding: .utf8),
                  let url = URL(string: s),
                  url.scheme == clawixProjectURLScheme,
                  let uuid = projectId(from: url) else { return }
            DispatchQueue.main.async {
                onPerform(uuid, slot)
            }
        }
        return true
    }
}

struct ToolRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

final class ToolRowFrameStore: ObservableObject {
    var byId: [String: CGRect] = [:]
}

struct ToolsReorderableList: View {
    let tools: [SidebarToolEntry]
    let selectedRoute: SidebarRoute
    let onSelect: (SidebarRoute) -> Void
    let onReorder: (String, String?) -> Void

    @State private var draggingId: String? = nil
    @State private var targetIndex: Int? = nil
    @State private var mouseUpMonitor: Any? = nil
    @State private var dragChipPanel: DragChipPanel? = nil
    @StateObject private var rowFrames = ToolRowFrameStore()
    @StateObject private var scrollBox = EnclosingScrollViewBox()
    @State private var autoScroller: PinnedDragAutoScroller? = nil

    /// Slot height used both as the row height and the gap height during
    /// drag. The two cancel out so the list height stays constant while
    /// the gap migrates between slots. Matches the natural intrinsic
    /// height of `DatabaseToolRow` / `SecretsToolRow` (~28 pt: 6 pt
    /// vertical padding + ~16 pt content).
    static let rowSlotHeight: CGFloat = 28
    private let baseSpacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { (i, entry) in
                slotZone(entry: entry, slot: i)
            }
            trailingSlotZone
        }
        .background(EnclosingScrollViewLocator(box: scrollBox).allowsHitTesting(false))
        .onAppear { installMouseUpMonitor() }
        .onDisappear {
            cleanupDragChip()
            removeMouseUpMonitor()
        }
        .onPreferenceChange(ToolRowFrameKey.self) { rowFrames.byId = $0 }
        .onChange(of: tools.map(\.id)) { _, _ in
            // Defensive sweep: any external mutation to the tools array
            // (filter toggle, reorder) clears lingering drag state so a
            // stale gap can never persist.
            guard draggingId != nil || targetIndex != nil else {
                cleanupDragChip()
                return
            }
            cleanupDragChip()
            targetIndex = nil
            draggingId = nil
        }
    }

    @ViewBuilder
    private func slotZone(entry: SidebarToolEntry, slot: Int) -> some View {
        let isDragging = draggingId == entry.id
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            ToolDisplayRow(
                entry: entry,
                isSelected: selectedRoute == entry.route,
                onTap: { onSelect(entry.route) }
            )
            .background(WindowDragInhibitor())
            .opacity(isDragging ? 0 : 1)
            .frame(height: isDragging ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isDragging)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ToolRowFrameKey.self,
                        value: [entry.id: proxy.frame(in: .global)]
                    )
                }
            )
            .onDrag {
                handleDragStart(entry: entry)
                let provider = NSItemProvider()
                let urlString = "\(clawixToolURLScheme)://\(entry.id)"
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.url.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(urlString.data(using: .utf8), nil)
                    return nil
                }
                provider.suggestedName = entry.titleString
                return provider
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                computeSlot: { y in y < Self.rowSlotHeight / 2 ? slot : slot + 1 },
                onSet: { setTarget(slot: $0) },
                onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
            ))
        }
    }

    @ViewBuilder
    private var trailingSlotZone: some View {
        let slot = tools.count
        VStack(alignment: .leading, spacing: 0) {
            gapPlaceholder(at: slot)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
            Color.clear
                .frame(height: SidebarRowMetrics.sectionEdgePadding)
                .contentShape(Rectangle())
                .onDrop(of: [.url], delegate: ToolRowDropDelegate(
                    computeSlot: { _ in slot },
                    onSet: { setTarget(slot: $0) },
                    onPerform: { id, chosen in performReorder(toolId: id, beforeIndex: chosen) }
                ))
        }
    }

    @ViewBuilder
    private func gapPlaceholder(at index: Int) -> some View {
        let isOpen = targetIndex == index
        let isFirst = index == 0
        let isLast = index == tools.count
        let baseHeight: CGFloat = (isFirst || isLast) ? 0 : baseSpacing
        Color.clear.frame(height: isOpen ? Self.rowSlotHeight : baseHeight)
    }

    private func handleDragStart(entry: SidebarToolEntry) {
        let src = tools.firstIndex(where: { $0.id == entry.id })
        targetIndex = src
        draggingId = entry.id
        let (anchor, width) = grabAnchor(for: entry)
        dragChipPanel?.close()
        let chip = ToolDragChipView(
            entry: entry,
            width: width,
            shadowInset: 24
        )
        dragChipPanel = DragChipPanel(
            content: AnyView(chip),
            grabAnchor: anchor,
            width: width,
            fallbackHeight: Self.rowSlotHeight
        )
        dragChipPanel?.show()
        autoScroller?.stop()
        let scroller = PinnedDragAutoScroller(box: scrollBox)
        scroller.start()
        autoScroller = scroller
    }

    private func grabAnchor(for entry: SidebarToolEntry) -> (CGPoint, CGFloat) {
        let fallbackWidth: CGFloat = 240
        guard let rowFrame = rowFrames.byId[entry.id] else {
            return (CGPoint(x: 30, y: 14), fallbackWidth)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView
        else {
            return (CGPoint(x: 30, y: 14), rowFrame.width)
        }
        let cursorScreen = NSEvent.mouseLocation
        let cursorInWindow = window.convertPoint(fromScreen: cursorScreen)
        let cursorSwiftUI = CGPoint(
            x: cursorInWindow.x,
            y: contentView.frame.height - cursorInWindow.y
        )
        let dx = cursorSwiftUI.x - rowFrame.origin.x
        let dy = cursorSwiftUI.y - rowFrame.origin.y
        return (CGPoint(x: dx, y: dy), rowFrame.width)
    }

    private func cleanupDragChip() {
        dragChipPanel?.close()
        dragChipPanel = nil
        autoScroller?.stop()
        autoScroller = nil
    }

    private func setTarget(slot: Int) {
        guard draggingId != nil else { return }
        guard targetIndex != slot else { return }
        withAnimation(toolReorderMoveAnimation) {
            targetIndex = slot
        }
    }

    private func performReorder(toolId: String, beforeIndex: Int) {
        cleanupDragChip()
        // Skip a no-op drop onto the source's own slot (either the gap
        // immediately above or the slot immediately below it). Otherwise
        // we'd churn the persisted order and re-fire the onChange watcher
        // on every drop that didn't actually move anything.
        if let src = tools.firstIndex(where: { $0.id == toolId }),
           (beforeIndex == src || beforeIndex == src + 1) {
            targetIndex = nil
            draggingId = nil
            return
        }
        let beforeId: String? = (beforeIndex < tools.count) ? tools[beforeIndex].id : nil
        onReorder(toolId, beforeId)
        targetIndex = nil
        draggingId = nil
    }

    private func installMouseUpMonitor() {
        guard mouseUpMonitor == nil else { return }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            DispatchQueue.main.async {
                cleanupDragChip()
                guard draggingId != nil || targetIndex != nil else { return }
                targetIndex = nil
                draggingId = nil
            }
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}

struct ToolRowDropDelegate: DropDelegate {
    let computeSlot: (CGFloat) -> Int
    let onSet: (Int) -> Void
    let onPerform: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url])
    }

    func dropEntered(info: DropInfo) {
        onSet(computeSlot(info.location.y))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onSet(computeSlot(info.location.y))
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let slot = computeSlot(info.location.y)
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
            guard let data,
                  let s = String(data: data, encoding: .utf8),
                  let url = URL(string: s),
                  url.scheme == clawixToolURLScheme
            else { return }
            // The id sits in the URL host slot. Tool ids in the catalog
            // are already lowercase so macOS's hostname canonicalisation
            // is a no-op.
            let id = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return }
            DispatchQueue.main.async {
                onPerform(id, slot)
            }
        }
        return true
    }
}

struct ToolDisplayRow: View {
    let entry: SidebarToolEntry
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        switch entry.icon {
        case .secrets:
            SecretsToolRow(isSelected: isSelected, onTap: onTap)
        case .system(let name):
            DatabaseToolRow(
                title: entry.titleString,
                systemIcon: name,
                route: entry.route,
                isSelected: isSelected,
                onTap: onTap
            )
        case .clawixLogo:
            AgentsToolRow(
                title: entry.titleString,
                route: entry.route,
                isSelected: isSelected,
                onTap: onTap
            )
        }
    }
}

struct AgentsToolRow: View {
    let title: String
    let route: SidebarRoute
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                ClawixLogoIcon(size: 13)
                    .frame(width: 15, height: 15)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
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
        .accessibilityLabel(title)
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
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

struct ToolDragChipView: View {
    let entry: SidebarToolEntry
    let width: CGFloat
    let shadowInset: CGFloat
    @EnvironmentObject private var vault: SecretsManager

    var body: some View {
        HStack(spacing: 11) {
            iconView
                .frame(width: 15, height: 15)
            Text(entry.title)
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Color(white: 0.82))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: ToolsReorderableList.rowSlotHeight)
        .background(
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                Color.white.opacity(0.035)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .padding(.trailing, 3)
        .frame(width: width, alignment: .leading)
        .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 4)
        .padding(shadowInset)
    }

    @ViewBuilder
    private var iconView: some View {
        switch entry.icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(Color(white: 0.82))
        case .secrets:
            SecretsIcon(
                size: 13.8,
                lineWidth: 1.28,
                color: Color(white: 0.82),
                isLocked: vault.state == .locked || vault.state == .unlocking
            )
        case .clawixLogo:
            ClawixLogoIcon(size: 13.5)
                .foregroundColor(Color(white: 0.82))
        }
    }
}
