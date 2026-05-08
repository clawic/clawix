import AppKit
import ApplicationServices

/// Reads the text the user had selected in whatever app was frontmost
/// before they triggered the QuickAsk hotkey, via the Accessibility
/// API. Best-effort: returns nil whenever the system denies access,
/// the focused element doesn't expose `AXSelectedText`, or the
/// selection is empty. The QuickAsk view consumes this on `show()` to
/// offer a "Use selection" affordance without auto-injecting.
@MainActor
enum QuickAskSelectionSniffer {

    /// Snapshot of what was selected at panel-open time.
    struct Snapshot {
        let text: String
        let appName: String?
    }

    /// Probe the frontmost app for selected text. Caller should invoke
    /// this BEFORE the QuickAsk panel becomes key, otherwise the
    /// frontmost app is already Clawix and the snapshot is empty.
    static func capture() -> Snapshot? {
        guard AXIsProcessTrusted() else {
            // No Accessibility permission yet. Don't ask for it here;
            // the work-with-apps / settings flow handles the prompt
            // explicitly so we don't surprise users with a system
            // dialog every time they hit the hotkey.
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        // Don't snoop on ourselves: when the panel is already key the
        // frontmost app would be Clawix and we'd quote our own input
        // back to the user.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusStatus == .success, let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        var selRef: CFTypeRef?
        let selStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selRef
        )
        guard selStatus == .success,
              let text = selRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return Snapshot(text: text, appName: app.localizedName)
    }
}
