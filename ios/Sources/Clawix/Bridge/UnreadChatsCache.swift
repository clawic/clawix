import Foundation

/// Set of chat ids that finished a turn while the user wasn't looking
/// at them. Drives the soft-blue dot at the right edge of the chat
/// row, mirroring the desktop's `hasUnreadCompletion` flag. The wire
/// model has no notion of read state, so this lives entirely on the
/// iPhone. Persisted to UserDefaults so the dot survives a relaunch
/// (the user hasn't read the chat yet, the launch shouldn't clear it).
enum UnreadChatsCache {
    private static let key = "Clawix.UnreadChatIds.v1"

    static func load() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: key) as? [String] else {
            return []
        }
        return Set(array)
    }

    static func save(_ ids: Set<String>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(Array(ids), forKey: key)
        }
    }
}
