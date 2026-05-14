import SwiftUI
import AppKit

// MARK: - Outside click monitor

struct MenuOutsideClickWatcher: NSViewRepresentable {
    @Binding var isPresented: Bool
    /// Optional extra hit-test, in window coordinates. Returns `true`
    /// when a point should be treated as INSIDE the popup (so the click
    /// propagates to SwiftUI instead of dismissing the menu). Used by
    /// menus whose submenu overlays render outside the watcher view's
    /// own bounds — without this their rows would silently no-op.
    var extraInsideTest: ((NSPoint) -> Bool)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = ClickWatcherView()
        view.onOutsideClick = {
            isPresented = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClickWatcherView else { return }
        view.isMonitoring = isPresented
        view.extraInsideTest = extraInsideTest
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? ClickWatcherView)?.isMonitoring = false
    }
}

final class ClickWatcherView: NSView {
    var onOutsideClick: (() -> Void)?
    private var monitor: Any?
    private var keyMonitor: Any?

    /// Optional extra hit-test, in window coordinates. When present and
    /// it returns `true` for the click point, the watcher treats the
    /// click as INSIDE its popup (returns the event, skips dismiss).
    /// Used by menus whose submenu overlays sit outside the watcher's
    /// own view bounds (the model picker's GPT / Other models / Speed
    /// columns and the local-models inline list) so clicks on those
    /// submenu rows aren't swallowed by the watcher.
    var extraInsideTest: ((NSPoint) -> Bool)?

    var isMonitoring: Bool = false {
        didSet {
            guard oldValue != isMonitoring else { return }
            isMonitoring ? attach() : detach()
        }
    }

    private func attach() {
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let win = self.window, event.window == win else { return event }
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pointInSelf) { return event }
                if let extra = self.extraInsideTest, extra(event.locationInWindow) { return event }
                // Swallow the dismissal click. SwiftUI Buttons fire on mouseUp,
                // so if we let mouseDown through to a trigger that does
                // `isOpen.toggle()`, the watcher closes the menu and the
                // button reopens it on release. NSPopover/NSMenu transient
                // dismissal works the same way: the click that closes the
                // popup is consumed.
                self.onOutsideClick?()
                return nil
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, event.window == win else { return event }
                guard event.keyCode == 53 else { return event }
                self.onOutsideClick?()
                return nil
            }
        }
    }

    private func detach() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    deinit { detach() }
}

// MARK: - Popup transition

struct PopupNudgeModifier: ViewModifier {
    let xOffset: CGFloat
    let yOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
    }
}

extension AnyTransition {
    // Asymmetric on purpose: insertion nudges from the offset to settle
    // in place, removal is fade-only. Translating on dismiss feels off,
    // especially when the click also opens a modal panel (NSOpenPanel)
    // and the user sees the row sliding down behind it.
    static func softNudge(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PopupNudgeModifier(xOffset: x, yOffset: y, opacity: 0),
                identity: PopupNudgeModifier(xOffset: 0, yOffset: 0, opacity: 1)
            ),
            removal: .opacity
        )
    }

    // Symmetric variant: removal also nudges back to the same offset while
    // fading. Use for popovers that should feel like they recede back to
    // their trigger on dismiss (no NSOpenPanel risk).
    static func softNudgeSymmetric(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        .modifier(
            active: PopupNudgeModifier(xOffset: x, yOffset: y, opacity: 0),
            identity: PopupNudgeModifier(xOffset: 0, yOffset: 0, opacity: 1)
        )
    }
}

// MARK: - Voice recording: transcribing spinner

/// Tiny indeterminate spinner that takes the mic button's slot while the
/// recorded clip is being transcribed. Visual language matches
/// `SidebarChatRowSpinner` (track + slow 2.4s rotation, ~0.79 arc) so
/// every "in flight" indicator across the app reads as the same family.
struct TranscribingSpinner: View {
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
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Composer text editor (Enter sends, Shift/Opt+Enter inserts a newline)

final class ComposerNSTextView: NSTextView {
    var trailingInset: CGFloat = 14
    /// Set to true when the editor should grab keyboard focus the next
    /// time it gets attached to a window. SwiftUI's `@FocusState` does
    /// not cross the NSViewRepresentable boundary, so this is how the
    /// composer auto-focuses on home / new chat.
    var wantsInitialFocus: Bool = false

    var popupSwiftUIRects: [CGRect] = []

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        pruneFileDragTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        pruneFileDragTypes()
    }

    /// NSTextView registers file URL drag types by default so dropping a
    /// file onto the editor inserts its path as text. That hijacks file
    /// drops away from the panel-wide `BodyDropOverlay`: when the cursor
    /// crosses the input, the text view wins the drag dispatch and the
    /// drop overlay disappears. The user expects drops over the input to
    /// behave exactly like drops over the main area, so we strip file URL
    /// types here and let the body overlay handle them.
    private func pruneFileDragTypes() {
        let blocked: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        let kept = registeredDraggedTypes.filter { !blocked.contains($0) }
        unregisterDraggedTypes()
        if !kept.isEmpty {
            registerForDraggedTypes(kept)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var thin = rect
        thin.size.width = 1
        thin.size.height = max(0, rect.size.height - 4)
        thin.origin.y = rect.origin.y + 2
        super.drawInsertionPoint(in: thin, color: color, turnedOn: flag)
    }

    override var rangeForUserCompletion: NSRange { NSRange(location: NSNotFound, length: 0) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            ComposerCursorRectsBridge.shared.textView = self
            popupSwiftUIRects = ComposerCursorRectsBridge.shared.popupSwiftUIRects
        }
        guard wantsInitialFocus, let window else { return }
        wantsInitialFocus = false
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let container = self.textContainer else { return }
        let targetWidth = max(0, newSize.width - trailingInset)
        if abs(container.containerSize.width - targetWidth) > 0.5 {
            container.containerSize = NSSize(width: targetWidth,
                                             height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private func swiftUIWindowPoint(for event: NSEvent) -> CGPoint? {
        guard let contentView = window?.contentView else { return nil }
        let p = event.locationInWindow
        return CGPoint(x: p.x, y: contentView.bounds.height - p.y)
    }

    private func isInsidePopup(_ event: NSEvent) -> Bool {
        guard !popupSwiftUIRects.isEmpty,
              let p = swiftUIWindowPoint(for: event) else { return false }
        return popupSwiftUIRects.contains { $0.contains(p) }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isInsidePopup(event) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isInsidePopup(event) {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }
}

@MainActor
final class ComposerCursorRectsBridge {
    static let shared = ComposerCursorRectsBridge()
    weak var textView: ComposerNSTextView?
    var popupSwiftUIRects: [CGRect] = [] {
        didSet { textView?.popupSwiftUIRects = popupSwiftUIRects }
    }
    private init() {}
}

struct ComposerPopupRectsKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func reportsComposerPopupRect() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ComposerPopupRectsKey.self,
                                value: [proxy.frame(in: .global)])
            }
        )
    }
}

struct ComposerTextEditor: NSViewRepresentable, Equatable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    /// Whether to grab keyboard focus the first time the view mounts.
    var autofocus: Bool = false
    /// Monotonic counter. When it changes, the editor is forced back to
    /// first responder. Used for "⌘N from home" and chat switching where
    /// the same editor instance stays mounted.
    var focusToken: Int = 0
    var onSubmit: () -> Void
    /// Fires when the user presses ⇧⇥ inside the editor. The composer
    /// uses this to toggle plan mode without leaving the keyboard.
    var onShiftTab: (() -> Void)? = nil

    // Equatable on the inputs that actually affect the visible state
    // of the wrapped NSTextView. The closures (`onSubmit`, `onShiftTab`)
    // are recreated on every parent body eval but they capture
    // EnvironmentObject references, so an older snapshot does the same
    // work as a fresher one. Bindings (`$text`, `$contentHeight`)
    // resolve back through the SwiftUI graph by stable identity so
    // skipping `updateNSView` does not strand a write path. Wrapping
    // the call site in `.equatable()` then lets SwiftUI skip the
    // updateNSView storm we get when the parent `ComposerView` body
    // re-evaluates because an unrelated environment object (auth,
    // dictation, localModelsService) ticked.
    static func == (lhs: ComposerTextEditor, rhs: ComposerTextEditor) -> Bool {
        lhs.text == rhs.text
            && lhs.autofocus == rhs.autofocus
            && lhs.focusToken == rhs.focusToken
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let bigSize = NSSize(width: CGFloat(0), height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: bigSize)
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = ComposerNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.minSize = NSSize(width: CGFloat(0), height: CGFloat(0))
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.string = text
        textView.wantsInitialFocus = autofocus
        context.coordinator.lastFocusToken = focusToken

        let scroller = ThinScroller()
        scroller.scrollerStyle = .overlay
        scrollView.verticalScroller = scroller

        scrollView.documentView = textView
        DispatchQueue.main.async { [weak textView] in
            guard let tv = textView else { return }
            context.coordinator.measure(tv)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let needsTextSync = textView.string != text
        let needsFocusSync = focusToken != context.coordinator.lastFocusToken
        guard needsTextSync || needsFocusSync else { return }
        RenderProbe.tick("ComposerTextEditor.updateNSView")
        // Only push the binding's value into the text view (and re-measure)
        // when it actually differs from what the user is currently editing.
        // Doing this unconditionally on every SwiftUI re-render forces an
        // extra `ensureLayout` pass per keystroke, which lands in the run
        // loop *between* the character insertion and the caret redraw and
        // makes typing feel laggy ("letter appears, then cursor catches up").
        if needsTextSync {
            textView.string = text
            DispatchQueue.main.async { [weak textView] in
                guard let tv = textView else { return }
                context.coordinator.measure(tv)
            }
        }
        if needsFocusSync {
            context.coordinator.lastFocusToken = focusToken
            if let composer = textView as? ComposerNSTextView {
                if composer.window != nil {
                    DispatchQueue.main.async { [weak composer] in
                        guard let composer, let window = composer.window else { return }
                        window.makeFirstResponder(composer)
                    }
                } else {
                    composer.wantsInitialFocus = true
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ComposerTextEditor
        var lastFocusToken: Int = 0
        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            measure(textView)
            // Defer the binding write to the next run-loop tick. Writing
            // synchronously fires `objectWillChange` on AppState mid-keystroke,
            // which forces SwiftUI to re-render the entire composer (toolbars,
            // attachment row, slash menu, project picker, model selector...)
            // *before* AppKit has committed the caret redraw for the inserted
            // character. The user perceives this as "the letter shows up, then
            // the cursor moves." Yielding one tick lets AppKit finish its draw
            // cycle first, then SwiftUI catches up.
            let snapshot = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != snapshot {
                    self.parent.text = snapshot
                }
            }
        }

        func measure(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height
            let h = ceil(used.height + inset * 2)
            if abs(parent.contentHeight - h) > 0.5 {
                parent.contentHeight = h
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(self)
                    return true
                }
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let onShiftTab = parent.onShiftTab {
                    onShiftTab()
                    return true
                }
            }
            return false
        }
    }
}
