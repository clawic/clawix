import Foundation

// Reads existing backend session rollouts to populate
// the sidebar with the user's real Clawix threads. We only parse what's
// needed for the row (id, cwd, title, mtime); RolloutReader handles
// hydrating the full message history when the user opens one.

struct ClawixSessionSummary: Identifiable, Hashable {
    let id: String                 // session id (UUIDv7), used as threadId
    let path: URL                  // absolute path to the rollout file
    let cwd: String?
    /// First user message of the rollout, trimmed. Used as input for
    /// title generation and as a last-resort display fallback when no
    /// title is available from any other source.
    let firstMessage: String
    let updatedAt: Date
}

enum SessionsIndex {
    private static let backendDataDirectoryName = "." + ["co", "dex"].joined()

    /// Default location for existing backend sessions.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(backendDataDirectoryName)/sessions", isDirectory: true)
    }

    /// Scan rollouts and return the most-recently-modified `limit` items.
    /// Cheap enough to run on app start (we read at most the first ~100
    /// lines of each rollout to extract metadata).
    static func list(limit: Int = 60, root: URL = defaultRoot) -> [ClawixSessionSummary] {
        let fm = FileManager.default
        guard let yearDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var rollouts: [(URL, Date)] = []
        for year in yearDirs {
            guard let monthDirs = try? fm.contentsOfDirectory(at: year, includingPropertiesForKeys: nil) else { continue }
            for month in monthDirs {
                guard let dayDirs = try? fm.contentsOfDirectory(at: month, includingPropertiesForKeys: nil) else { continue }
                for day in dayDirs {
                    guard let files = try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                    for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                        rollouts.append((file, mtime))
                    }
                }
            }
        }

        rollouts.sort { $0.1 > $1.1 }
        return rollouts.prefix(limit).compactMap { (url, mtime) in
            parseSummary(at: url, mtime: mtime)
        }
    }

    private static func parseSummary(at url: URL, mtime: Date) -> ClawixSessionSummary? {
        // Read the first ~256 KiB; that's plenty to find session_meta + the
        // first user_message of a normal conversation.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? Data()

        var id: String?
        var cwd: String?
        var firstMessage: String?

        // Each line is a JSON object. Process lines independently.
        var start = chunk.startIndex
        while let nl = chunk[start...].firstIndex(of: 0x0a) {
            let line = chunk[start..<nl]
            start = chunk.index(after: nl)
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any] else {
                continue
            }
            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any]
            switch type {
            case "session_meta":
                id = payload?["id"] as? String
                cwd = payload?["cwd"] as? String
            case "event_msg":
                if firstMessage == nil,
                   let inner = payload?["type"] as? String,
                   inner == "user_message",
                   let msg = payload?["message"] as? String {
                    let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        firstMessage = trimmed
                    }
                }
            default:
                continue
            }
            if id != nil && firstMessage != nil { break }
        }

        guard let id else { return nil }
        return ClawixSessionSummary(
            id: id,
            path: url,
            cwd: cwd,
            firstMessage: firstMessage ?? "",
            updatedAt: mtime
        )
    }
}
