import SwiftUI
import AppKit

/// Cooldown-based scroll gate. Any sidebar hover handler reads
/// `SidebarScrollState.shared.isScrolling` and drops hover state writes
/// when true. Tracking a moving cursor over passing rows is what costs
/// during scroll: ungated, every row crossed produces two `@State`
/// mutations and two body re-evaluations.
///
/// Implementation: every observed scroll event stamps `lastScrollTime`.
/// `isScrolling` returns `true` for `cooldown` seconds after the last
/// stamp, no timers. Self-clearing, robust to gaps between event sources.
final class SidebarScrollState {
    static let shared = SidebarScrollState()

    /// How long after the last scroll event the gate stays engaged. Long
    /// enough to bridge gaps between discrete wheel ticks (~150-250ms),
    /// short enough that hover re-engages quickly when the user actually
    /// stops.
    private static let cooldown: TimeInterval = 0.25

    private var lastScrollTime: TimeInterval = 0

    private init() {}

    var isScrolling: Bool {
        CFAbsoluteTimeGetCurrent() - lastScrollTime < Self.cooldown
    }

    /// Stamp scroll activity. Called from the AppKit-side installer on
    /// every signal that the sidebar is being scrolled (wheel events,
    /// live scroll notifications, clip-view bounds changes).
    func bump() {
        lastScrollTime = CFAbsoluteTimeGetCurrent()
    }
}

/// Drop this as a `.background(...)` inside the sidebar's scroll content.
/// On attach it walks up the AppKit hierarchy to find the surrounding
/// `NSScrollView`, then bumps `SidebarScrollState.shared` from three
/// independent sources to cover trackpad live scroll, wheel/discrete
/// scroll, and any programmatic scroll path that mutates the clip view's
/// bounds.
struct SidebarScrollStateInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarScrollStateInstallerView {
        SidebarScrollStateInstallerView()
    }

    func updateNSView(_ nsView: SidebarScrollStateInstallerView, context: Context) {
        nsView.installIfNeeded()
    }
}

final class SidebarScrollStateInstallerView: NSView {
    private weak var observed: NSScrollView?
    private var startObs: NSObjectProtocol?
    private var liveObs: NSObjectProtocol?
    private var boundsObs: NSObjectProtocol?
    private var wheelMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Defer to next runloop so SwiftUI has time to wire the hosting
        // view into the scroll view's clip view before we walk superviews.
        DispatchQueue.main.async { [weak self] in
            self?.installIfNeeded()
        }
    }

    func installIfNeeded() {
        guard observed == nil else { return }
        var current: NSView? = self.superview
        while let view = current {
            if let scroll = view as? NSScrollView {
                attach(to: scroll)
                return
            }
            current = view.superview
        }
    }

    private func attach(to scrollView: NSScrollView) {
        observed = scrollView

        // Trackpad live scroll: posted at start and on every frame during
        // the gesture. Catches the gesture immediately (no first-frame
        // hover leak) and keeps stamping while inertia continues.
        startObs = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }
        liveObs = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }

        // Clip-view bounds change: fires for every scroll source (wheel,
        // animated, programmatic, key-driven) on every frame the bounds
        // actually move. The trackpad notifications above don't cover
        // wheel mice, so this is the catch-all.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        boundsObs = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }

        // Local NSEvent monitor for `.scrollWheel`: fires *before* the
        // scroll view processes the event and *before* any bounds change
        // is posted, so the gate is engaged by the time SwiftUI dispatches
        // the synthetic hover events caused by content moving under the
        // cursor. Filter by window so wheel events outside our window
        // don't engage the sidebar's gate.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak scrollView] event in
            if let win = scrollView?.window, event.window === win {
                SidebarScrollState.shared.bump()
            }
            return event
        }
    }

    deinit {
        if let o = startObs { NotificationCenter.default.removeObserver(o) }
        if let o = liveObs { NotificationCenter.default.removeObserver(o) }
        if let o = boundsObs { NotificationCenter.default.removeObserver(o) }
        if let m = wheelMonitor { NSEvent.removeMonitor(m) }
    }
}

extension View {
    /// `onHover` variant that drops events while the sidebar is in a
    /// scroll cooldown window. The next genuine cursor motion after the
    /// cooldown expires re-asserts hover state via the normal AppKit
    /// tracking path; a row that was hovered when scroll began can stay
    /// visually highlighted for a frame or two until the cursor actually
    /// moves, which is invisible in practice and dramatically cheaper
    /// than the per-frame thrash.
    func sidebarHover(_ action: @escaping (Bool) -> Void) -> some View {
        self.onHover { entered in
            guard !SidebarScrollState.shared.isScrolling else { return }
            action(entered)
        }
    }
}
