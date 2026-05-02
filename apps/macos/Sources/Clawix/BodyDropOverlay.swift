import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Full-panel file drop target. While the user drags files anywhere over
/// the content panel of the window (chrome included), the area shows a
/// translucent blue tint with a centered drop pill. Dropped files are
/// staged as composer attachments via `appState.addComposerAttachments`.
///
/// Apply with `.bodyDropTarget(enabled:)` on the content column. Use
/// `enabled: false` for routes that don't expose the composer
/// (`.settings`, `.automations`) so dropping there is a no-op.
///
/// The drop is wired through an AppKit `NSView` that registers for the
/// file URL drag type, instead of SwiftUI's `.onDrop`. AppKit delivers
/// drag events to non-key windows, so the tint lights up even when
/// Clawix is in the background, which is what users expect from a
/// macOS app accepting files from Finder.
extension View {
    func bodyDropTarget(enabled: Bool = true) -> some View {
        modifier(BodyDropTarget(enabled: enabled))
    }
}

private struct BodyDropTarget: ViewModifier {
    let enabled: Bool
    @EnvironmentObject var appState: AppState
    @State private var isDropping = false

    func body(content: Content) -> some View {
        content
            .overlay(
                // Sits ABOVE the composer's NSTextView so AppKit's drag
                // dispatch picks the body acceptor as destination instead
                // of the text view. Otherwise CleanShot-style drags (which
                // put both `.fileURL` and `.string` on the pasteboard) get
                // caught by the text view via its `.string` registration
                // and the file path is inserted as literal text. The
                // acceptor's `hitTest` returns nil so mouse events still
                // fall through to the SwiftUI views beneath.
                FileDropAcceptor(
                    isEnabled: enabled,
                    isDropping: $isDropping,
                    onDrop: { urls in
                        guard !urls.isEmpty else { return false }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.16)) {
                                appState.addComposerAttachments(urls)
                            }
                        }
                        return true
                    }
                )
            )
            .overlay { overlay }
    }

    /// Mirrors `ContentView.contentShape` so the tint follows the same
    /// squircle as the panel itself, including the top corners now that
    /// the modifier sits at the column level (chrome included).
    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: appState.isRightSidebarOpen ? 14 : 0,
            topTrailingRadius: appState.isRightSidebarOpen ? 14 : 0,
            style: .continuous
        )
    }

    @ViewBuilder
    private var overlay: some View {
        ZStack {
            Color(red: 0.20, green: 0.50, blue: 0.95)
                .opacity(0.16)
                .clipShape(panelShape)

            HStack(spacing: 9) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.94))
                Text(L10n.t("Drop to attach"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Color(white: 0.94))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .menuStandardBackground()
        }
        .opacity(isDropping ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: isDropping)
        .allowsHitTesting(false)
    }
}

// MARK: - AppKit drop acceptor

private struct FileDropAcceptor: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var isDropping: Bool
    let onDrop: ([URL]) -> Bool

    func makeNSView(context: Context) -> DropAcceptingNSView {
        let view = DropAcceptingNSView()
        view.coordinator = context.coordinator
        view.applyEnabled(isEnabled)
        return view
    }

    func updateNSView(_ nsView: DropAcceptingNSView, context: Context) {
        context.coordinator.isDropping = $isDropping
        context.coordinator.onDrop = onDrop
        nsView.coordinator = context.coordinator
        nsView.applyEnabled(isEnabled)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDropping: $isDropping, onDrop: onDrop)
    }

    final class Coordinator {
        var isDropping: Binding<Bool>
        var onDrop: ([URL]) -> Bool
        init(isDropping: Binding<Bool>, onDrop: @escaping ([URL]) -> Bool) {
            self.isDropping = isDropping
            self.onDrop = onDrop
        }
    }
}

private final class DropAcceptingNSView: NSView {
    weak var coordinator: FileDropAcceptor.Coordinator?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Pass mouse events through to underlying SwiftUI views. Drag events
    /// are NOT routed via `hitTest`, so this only suppresses click/hover
    /// interception, not drag delivery.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// AppKit delivers `draggingEntered:` to any view registered for the
    /// pasteboard type whose window is visible, regardless of key/active
    /// status. This is the whole point of routing through NSView instead
    /// of SwiftUI's `.onDrop`, which only fires reliably while the
    /// window is key.
    func applyEnabled(_ enabled: Bool) {
        if enabled {
            if registeredDraggedTypes.isEmpty {
                registerForDraggedTypes([.fileURL])
            }
        } else {
            unregisterDraggedTypes()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(in: sender) else { return [] }
        coordinator?.isDropping.wrappedValue = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFiles(in: sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.isDropping.wrappedValue = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        coordinator?.isDropping.wrappedValue = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFiles(in: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let urls = (pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        coordinator?.isDropping.wrappedValue = false
        guard !urls.isEmpty else { return false }
        return coordinator?.onDrop(urls) ?? false
    }

    private func hasFiles(in info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}
