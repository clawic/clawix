import AppKit

/// Borderless panel that hosts the QuickAsk floating composer. Two
/// behaviours differ from `DictationOverlay`'s panel:
///   • `canBecomeKey` returns `true`, so the embedded `TextEditor` can
///     receive keystrokes. A non-activating panel that can't become key
///     would render but never accept text input.
///   • `isMovableByWindowBackground = true` lets the user grab the
///     panel anywhere outside the text field and drag it to any spot
///     across any space, mirroring the "Spotlight that I drag where I
///     want" feel the user described.
final class QuickAskPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Strict `.borderless`: no titled chrome, no fullSizeContent
            // shim. `.titled` (even with hidden title and transparent
            // titlebar) still paints a thin window edge that reads as
            // a phantom outline around the SwiftUI rounded shape.
            // `.nonactivatingPanel` keeps the underlying app frontmost
            // while the panel still receives clicks/keys.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        // The drop shadow is drawn by SwiftUI inside the content view's
        // padding so it can be soft and offset; AppKit's own shadow on
        // a transparent borderless panel renders a hard rectangle that
        // outlines the entire window bounds.
        self.hasShadow = false
        // `popUpMenu` floats above almost every regular window; on top
        // of a fullscreen Space we additionally need
        // `.fullScreenAuxiliary` (set by the controller's
        // collectionBehavior).
        self.level = .popUpMenu
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
    }

    // Default `NSPanel` behaviour for borderless panels is
    // `canBecomeKey == false`, which would silently swallow keystrokes
    // from the SwiftUI `TextField`.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Esc dismisses, even when the text field is first responder.
    // SwiftUI's `.onSubmit` doesn't fire on Esc, and forwarding to
    // `cancelOperation(_:)` here keeps the behaviour consistent with
    // how Spotlight-style HUDs behave on macOS.
    override func cancelOperation(_ sender: Any?) {
        QuickAskController.shared.hide()
    }
}
