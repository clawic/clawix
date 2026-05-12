import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop payload for terminal tabs. Identifies the source tab by
/// uuid so the destination side (another chip for reorder, or a pane for
/// dock-as-split) can look it up in `TerminalSessionStore` without going
/// through a serialized snapshot of layout/state.
///
/// Carried over the pasteboard as a plain UTF-8 string with the prefix
/// `clawix-terminal-tab:` so we can quickly tell our drops apart from
/// arbitrary text drags the user might attempt.
struct TerminalTabPayload {
    static let providerPrefix = "clawix-terminal-tab:"
    static let utType: UTType = .utf8PlainText

    let tabId: UUID

    var providerString: String { Self.providerPrefix + tabId.uuidString }

    /// Synchronous extraction from an `NSItemProvider`. Tries the
    /// in-memory load path first, then falls back to loading the type's
    /// data representation. Returns nil if the payload is not ours.
    static func decode(from info: DropInfo) -> TerminalTabPayload? {
        let providers = info.itemProviders(for: [utType])
        guard let provider = providers.first else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: TerminalTabPayload?
        provider.loadItem(forTypeIdentifier: utType.identifier, options: nil) { data, _ in
            defer { semaphore.signal() }
            if let string = data as? String {
                result = decode(string: string)
            } else if let data = data as? Data,
                      let string = String(data: data, encoding: .utf8) {
                result = decode(string: string)
            } else if let url = data as? URL,
                      let string = try? String(contentsOf: url, encoding: .utf8) {
                result = decode(string: string)
            }
        }
        _ = semaphore.wait(timeout: .now() + 0.4)
        return result
    }

    private static func decode(string: String) -> TerminalTabPayload? {
        guard string.hasPrefix(providerPrefix) else { return nil }
        let raw = String(string.dropFirst(providerPrefix.count))
        guard let uuid = UUID(uuidString: raw) else { return nil }
        return TerminalTabPayload(tabId: uuid)
    }
}
