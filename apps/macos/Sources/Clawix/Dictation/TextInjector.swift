import Foundation
import AppKit
import ApplicationServices

/// Pastes a transcribed string into whatever app currently owns the
/// keyboard focus. Strategy mirrors what most dictation tools settle on
/// because the AX text-insertion APIs are too unreliable across apps:
///
/// 1. Snapshot the current pasteboard contents.
/// 2. Replace it with the transcript.
/// 3. Synthesize Cmd+V via `CGEvent` so the focused field receives a
///    standard paste event (Electron, Cocoa, web textareas all
///    respond).
/// 4. Optionally synthesize an auto-send key (plain Return, Shift+Return,
///    Cmd+Return) ~150 ms after the paste so the field has fully
///    consumed the inserted text.
/// 5. Restore the snapshot after a delay long enough for the receiving
///    app to actually apply the paste before we overwrite it.
///
/// Requires Accessibility permission for `CGEvent.post(tap:)` to
/// deliver to other apps. The first time the app asks the OS prompts
/// the user; we re-check on every inject and surface a friendly error
/// to the coordinator if it's still missing.
@MainActor
enum TextInjector {

    enum InjectError: Error, LocalizedError {
        case accessibilityNotGranted
        case empty

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Allow Clawix in Accessibility to paste transcripts"
            case .empty:
                return "Empty transcript"
            }
        }
    }

    /// Place `text` on the pasteboard, fire Cmd+V, optionally fire
    /// an auto-send key after the paste lands, and restore the previous
    /// pasteboard contents after `restoreAfter` seconds.
    ///
    /// `addSpaceBefore` queries Accessibility for the character to the
    /// left of the focused caret. If it's an alphanumeric, we prepend
    /// " " to the text so dictating into the middle of an existing
    /// paragraph doesn't run words together. Best-effort: any AX
    /// failure (sandboxed app, no AX support, no insertion point)
    /// silently skips the heuristic so the paste still happens.
    static func inject(
        text: String,
        restorePrevious: Bool = true,
        autoSendKey: DictationAutoSendKey = .none,
        restoreAfter: TimeInterval = 1.5,
        addSpaceBefore: Bool = false
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InjectError.empty }
        if let capturePath = ProcessInfo.processInfo.environment["CLAWIX_E2E_TEXT_INJECTOR_CAPTURE"] {
            try injectForE2E(
                text: text,
                restorePrevious: restorePrevious,
                autoSendKey: autoSendKey,
                restoreAfter: restoreAfter,
                capturePath: capturePath,
                addSpaceBefore: addSpaceBefore
            )
            return
        }
        guard AXIsProcessTrusted() else {
            throw InjectError.accessibilityNotGranted
        }

        let payload: String
        if addSpaceBefore, shouldPrependSpace() {
            payload = " " + text
        } else {
            payload = text
        }

        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.snapshot()

        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)

        if shouldUseAppleScriptPaste {
            pasteUsingAppleScript()
        } else {
            postCommandV()
        }

        if autoSendKey != .none {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                postReturn(flags: autoSendKey.modifierFlags)
            }
        }

        if restorePrevious {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
                pasteboard.restore(snapshot)
            }
        }
    }

    private static var shouldUseAppleScriptPaste: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "useAppleScriptPaste") != nil {
            return defaults.bool(forKey: "useAppleScriptPaste")
        }
        if defaults.object(forKey: "UseAppleScriptPaste") != nil {
            return defaults.bool(forKey: "UseAppleScriptPaste")
        }
        return false
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        // .cghidEventTap is the lowest tap available to a third-party
        // app and what most apps observe for keystrokes. Posting at a
        // higher tap (annotated session) fails to register in some
        // sandboxed receivers.
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    /// Post a Return key, optionally with modifier flags. With no
    /// flags, regular Enter for chat fields. With shift, the same key
    /// but flagged as Shift+Return for multiline fields. With command,
    /// Cmd+Return for command-submit fields. Some chat fields submit only when the keystroke is
    /// delivered separately from the paste, so this is called from a
    /// delayed dispatch after `postCommandV`.
    private static func postReturn(flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func pasteUsingAppleScript() {
        let source = "tell application \"System Events\" to key code 9 using command down"
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            NSLog("[Clawix.TextInjector] AppleScript paste failed: %@", "\(error)")
        }
    }

    private static func injectForE2E(
        text: String,
        restorePrevious: Bool,
        autoSendKey: DictationAutoSendKey,
        restoreAfter: TimeInterval,
        capturePath: String,
        addSpaceBefore: Bool
    ) throws {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let snapshot = pasteboard.snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let report: [String: Any] = [
            "payload": text,
            "previousClipboard": previous,
            "restorePrevious": restorePrevious,
            "autoSendKey": autoSendKey.rawValue,
            "addSpaceBefore": addSpaceBefore
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: capturePath), options: .atomic)

        if restorePrevious {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
                pasteboard.restore(snapshot)
            }
        }
    }

    // MARK: - Accessibility heuristic for "Add Space Before"

    /// Query the focused element's text + selection range; if the
    /// character immediately before the caret is alphanumeric, return
    /// `true` so the caller prepends a space. Quietly returns `false`
    /// on every failure path (no AX, no focused element, no value
    /// attribute, range at start, etc.) so a problematic app can never
    /// break the paste.
    private static func shouldPrependSpace() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let element = focused else { return false }
        let focusedElement = element as! AXUIElement

        // 1. Read the selected text range — this gives us the caret
        // position in characters. AXValue wraps a CFRange.
        var rangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeStatus == .success, let rv = rangeValue else { return false }
        var range = CFRange(location: 0, length: 0)
        let axValue = rv as! AXValue
        guard AXValueGetValue(axValue, .cfRange, &range) else { return false }
        guard range.location > 0 else { return false }

        // 2. Read the full text value. Many apps expose `kAXValueAttribute`
        // on the focused field. Some don't, in which case we bail.
        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueRef
        )
        guard valueStatus == .success, let value = valueRef as? String else { return false }

        // 3. Look at the character immediately before the caret.
        // `range.location` is in UTF-16 code units (CFString-style),
        // which lines up with `String.utf16` indexing.
        let utf16 = value.utf16
        let beforeIndex = range.location - 1
        guard beforeIndex >= 0, beforeIndex < utf16.count else { return false }
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: beforeIndex)
        let unit = utf16[utf16Index]
        // Reconstruct as Character to make alphanumeric tests
        // straightforward across multilingual input. If the unit is a
        // surrogate half we just bail; this code path is for the
        // common case (BMP text).
        guard let scalar = Unicode.Scalar(unit) else { return false }
        let char = Character(scalar)
        // Treat letters, digits and most "word" punctuation (apostrophe,
        // letter-with-mark) as alphanumeric. Whitespace and ASCII
        // punctuation that already implies a separator (".", ",", ":",
        // ";", "!", "?", "(", ")", "[", "]", quotes) → no extra space.
        return char.isLetter || char.isNumber
    }
}

private extension NSPasteboard {
    /// Captures every pasteboard item of every type we know about so we
    /// can restore richer payloads (e.g. an image plus a string) and
    /// not just the current `.string`. The cost is one extra alloc per
    /// transcript, which is negligible.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    func snapshot() -> Snapshot {
        let entries: [[NSPasteboard.PasteboardType: Data]] = (pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return Snapshot(items: entries)
    }

    func restore(_ snapshot: Snapshot) {
        clearContents()
        let items: [NSPasteboardItem] = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            writeObjects(items)
        }
    }
}
