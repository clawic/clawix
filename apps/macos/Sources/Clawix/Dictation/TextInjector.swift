import Foundation
import AppKit

/// Pastes a transcribed string into whatever app currently owns the
/// keyboard focus. Strategy mirrors what most dictation tools settle on
/// because the AX text-insertion APIs are too unreliable across apps:
///
/// 1. Snapshot the current pasteboard contents.
/// 2. Replace it with the transcript.
/// 3. Synthesize Cmd+V via `CGEvent` so the focused field receives a
///    standard paste event (Electron, Cocoa, web textareas all
///    respond).
/// 4. Restore the snapshot after a delay long enough for the receiving
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
    /// Return after the paste lands, and restore the previous
    /// pasteboard contents after `restoreAfter` seconds.
    ///
    /// `restoreAfter` is intentionally generous (1.5 s by default)
    /// because the receiving app's paste handler isn't synchronous.
    /// `autoEnter` posts an unmodified Return ~150 ms after the paste,
    /// late enough that the focused field has finished applying the
    /// inserted text but before the clipboard is restored — this is
    /// what makes "dictate then send" work in chat fields like the
    /// Clawix composer or web inputs that submit on Enter.
    static func inject(
        text: String,
        restorePrevious: Bool = true,
        autoEnter: Bool = false,
        restoreAfter: TimeInterval = 1.5
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InjectError.empty }
        guard AXIsProcessTrusted() else {
            throw InjectError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.snapshot()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        if autoEnter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                postReturn()
            }
        }

        if restorePrevious {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
                pasteboard.restore(snapshot)
            }
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
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

    /// Post an unmodified Return key. Some chat fields submit on Enter
    /// only when the keystroke is delivered separately from the paste,
    /// so this is called from a delayed dispatch after `postCommandV`.
    private static func postReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
