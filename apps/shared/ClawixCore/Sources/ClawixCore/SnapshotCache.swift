import Foundation

/// On-disk cache of the last `BridgeStore` / `AppState` snapshot the app
/// saw, living in `Application Support/clawix/snapshot.json`. The point
/// is cold-start "feel": when the app launches we can populate the chat
/// list and the most-recent transcripts before the WebSocket race even
/// completes. The bridge always wins eventually (its snapshot frames
/// replace the cache in memory), but the user no longer stares at an
/// empty screen for the seconds it takes to reach the Mac over Tailscale
/// or to wake it from sleep.
///
/// Lives in `ClawixCore` so iOS and the macOS desktop client share the
/// same on-disk format; both targets read the same `WireChat` /
/// `WireMessage` shapes via `BridgeCoder`. The cache is intentionally
/// small (last 30 chats, last 80 messages each). Users with thousands
/// of chats/messages still get an instant home; rarely-touched chats
/// fall back to the live snapshot path.
public enum SnapshotCache {
    /// `Codable` envelope for the persisted state. Lives in this file
    /// instead of leaking into the consumers because nothing outside of
    /// this cache should be reading from / writing to it.
    public struct Payload: Codable {
        public let chats: [WireChat]
        public let messagesByChat: [String: [WireMessage]]

        public init(chats: [WireChat], messagesByChat: [String: [WireMessage]]) {
            self.chats = chats
            self.messagesByChat = messagesByChat
        }
    }

    /// Cap defensive: keep the last `maxChats` chats by recency, and
    /// for each at most `maxMessagesPerChat` of the tail. Prevents the
    /// cache file from blowing up for power users without a maintenance
    /// pass.
    private static let maxChats = 30
    private static let maxMessagesPerChat = 80

    private static let dirName = "clawix"
    private static let fileName = "snapshot.json"

    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent(dirName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return dir.appendingPathComponent(fileName)
    }

    /// Load the persisted snapshot if any. Silent on every failure path
    /// (corrupt JSON, missing file, schema mismatch): the bridge will
    /// re-deliver the truth shortly anyway.
    public static func load() -> Payload? {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? BridgeCoder.decoder.decode(Payload.self, from: data)
    }

    /// Persist a clipped snapshot. Safe to call from a background
    /// queue; writes through a temp file so a mid-write process kill
    /// does not leave a partial JSON in place.
    public static func save(chats: [WireChat], messages: [String: [WireMessage]]) {
        guard let url = fileURL else { return }
        let topChats = chats
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let l = lhs.lastMessageAt ?? lhs.createdAt
                let r = rhs.lastMessageAt ?? rhs.createdAt
                return l > r
            }
            .prefix(maxChats)
            .map { $0 }
        let topIds = Set(topChats.map(\.id))
        var clipped: [String: [WireMessage]] = [:]
        for (chatId, list) in messages where topIds.contains(chatId) {
            clipped[chatId] = Array(list.suffix(maxMessagesPerChat))
        }
        let payload = Payload(chats: topChats, messagesByChat: clipped)
        guard let data = try? BridgeCoder.encoder.encode(payload) else { return }
        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// Wipe the cache. Called on unpair so a future user of the same
    /// device does not see the previous user's chats during the
    /// pairing → connect window.
    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
