import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's `LocalProcessTerminalView`. The
/// underlying NSView is owned by the `TerminalSession`, so switching
/// between chats / tabs preserves scrollback and process state — the
/// view detaches/reattaches but the PTY read loop keeps running.
struct TerminalEmulatorView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    var isFocused: Bool
    var onFocus: () -> Void

    final class Container: NSView {
        var sessionId: UUID?
        var onReady: (() -> Void)?
        var shouldFocus = false
        private var isKeyboardResponder = false
        private var lastUsableBounds: CGRect = .zero
        private let scrollIndicator = TerminalScrollIndicator()
        var emulator: LocalProcessTerminalView? {
            didSet {
                oldValue?.removeFromSuperview()
                attachEmulatorIfNeeded()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            scrollIndicator.translatesAutoresizingMaskIntoConstraints = true
            scrollIndicator.autoresizingMask = [.minXMargin, .height]
            addSubview(scrollIndicator)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            scrollIndicator.translatesAutoresizingMaskIntoConstraints = true
            scrollIndicator.autoresizingMask = [.minXMargin, .height]
            addSubview(scrollIndicator)
        }

        override var acceptsFirstResponder: Bool { true }

        override func layout() {
            super.layout()
            attachEmulatorIfNeeded()
            syncEmulatorFrameIfUsable()
            positionScrollIndicator()
            startIfReady()
            focusIfNeeded()
        }

        private func positionScrollIndicator() {
            // Live above the emulator on the trailing edge so it paints
            // over the area where SwiftTerm's hidden native scroller
            // would be. 11pt-wide column gives the thumb room without
            // eating terminal columns visually.
            let width: CGFloat = 11
            scrollIndicator.frame = NSRect(
                x: bounds.width - width,
                y: 0,
                width: width,
                height: bounds.height
            )
            if scrollIndicator.superview === self,
               let above = subviews.last,
               above !== scrollIndicator {
                addSubview(scrollIndicator, positioned: .above, relativeTo: nil)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func keyDown(with event: NSEvent) {
            if let emulator {
                emulator.keyDown(with: event)
            } else {
                super.keyDown(with: event)
            }
        }

        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok {
                isKeyboardResponder = true
                TerminalSessionStore.shared.setKeyboardFocused(true)
            }
            return ok
        }

        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok {
                isKeyboardResponder = false
                TerminalSessionStore.shared.setKeyboardFocused(false)
            }
            return ok
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil, isKeyboardResponder {
                isKeyboardResponder = false
                TerminalSessionStore.shared.setKeyboardFocused(false)
            }
        }

        private func startIfReady() {
            guard bounds.width > 20, bounds.height > 20 else { return }
            onReady?()
        }

        func attachEmulatorIfNeeded() {
            guard let emulator else { return }
            if emulator.superview !== self {
                emulator.removeFromSuperview()
                addSubview(emulator)
            }
            emulator.translatesAutoresizingMaskIntoConstraints = true
            emulator.autoresizingMask = []
            syncEmulatorFrameIfUsable()
            hideEmbeddedScroller()
            emulator.needsDisplay = true
            startIfReady()
        }

        private func hideEmbeddedScroller() {
            guard let emulator else { return }
            for sub in emulator.subviews {
                if let scroller = sub as? NSScroller {
                    scroller.isHidden = true
                    scrollIndicator.attach(to: scroller)
                }
            }
        }

        private func syncEmulatorFrameIfUsable() {
            guard let emulator else { return }
            guard bounds.width > 20, bounds.height > 20 else {
                if !lastUsableBounds.isEmpty {
                    emulator.frame = lastUsableBounds
                }
                return
            }
            lastUsableBounds = bounds
            let frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width + Container.swiftTermScrollerWidth,
                height: bounds.height
            )
            emulator.frame = frame
        }

        static let swiftTermScrollerWidth: CGFloat = NSScroller.scrollerWidth(
            for: .regular,
            scrollerStyle: .clawixAlwaysVisible
        )

        func focusIfNeeded() {
            guard shouldFocus, let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    func makeNSView(context: Context) -> Container {
        let container = Container()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.sessionId = session.id
        container.onReady = { session.startIfNeeded() }
        container.emulator = session.terminalView
        return container
    }

    func updateNSView(_ nsView: Container, context: Context) {
        nsView.onReady = { session.startIfNeeded() }
        nsView.shouldFocus = isFocused
        if nsView.sessionId != session.id {
            nsView.sessionId = session.id
            nsView.emulator = session.terminalView
        }
        nsView.attachEmulatorIfNeeded()
        if nsView.bounds.width > 20, nsView.bounds.height > 20 {
            session.startIfNeeded()
        }
        if isFocused {
            DispatchQueue.main.async { nsView.focusIfNeeded() }
        }
    }

    static func dismantleNSView(_ nsView: Container, coordinator: ()) {
        nsView.emulator?.removeFromSuperview()
        nsView.emulator = nil
    }
}
