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
        var emulator: LocalProcessTerminalView? {
            didSet {
                oldValue?.removeFromSuperview()
                if let emulator {
                    emulator.frame = bounds
                    emulator.autoresizingMask = [.width, .height]
                    addSubview(emulator)
                }
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(emulator)
            super.mouseDown(with: event)
        }
    }

    func makeNSView(context: Context) -> Container {
        let container = Container()
        container.sessionId = session.id
        container.emulator = session.terminalView
        return container
    }

    func updateNSView(_ nsView: Container, context: Context) {
        if nsView.sessionId != session.id {
            nsView.sessionId = session.id
            nsView.emulator = session.terminalView
        }
        if isFocused, let emulator = nsView.emulator,
           let window = emulator.window,
           window.firstResponder !== emulator {
            DispatchQueue.main.async {
                window.makeFirstResponder(emulator)
            }
        }
    }
}
