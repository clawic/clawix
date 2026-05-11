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
        private var lastUsableBounds: CGRect = .zero
        var emulator: LocalProcessTerminalView? {
            didSet {
                oldValue?.removeFromSuperview()
                attachEmulatorIfNeeded()
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func layout() {
            super.layout()
            attachEmulatorIfNeeded()
            syncEmulatorFrameIfUsable()
            startIfReady()
            focusIfNeeded()
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
            emulator.needsDisplay = true
            startIfReady()
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
            emulator.frame = bounds
        }

        func focusIfNeeded() {
            guard shouldFocus, let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    func makeNSView(context: Context) -> Container {
        let container = Container()
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
