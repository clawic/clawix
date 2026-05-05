import Foundation
import GRDB

// Resolves conversation titles from two sources:
//
//   1. The runtime session index at ~/.codex/session_index.jsonl
//      (read-only, JSONL, owned by the codex CLI). Re-read on reload().
//   2. The session_titles SQLite table (overrides written by this app:
//      manual user renames + generated titles).
//
// Both contribute to an in-memory fold; the latest updated_at per
// thread id wins. Manual renames and generated titles are persisted
// here directly (replacing the legacy JSONL overrides file).
@MainActor
final class SessionTitlesRepository {
    struct Entry {
        let threadId: String
        let title: String
        let updatedAt: Date
        let source: String
    }

    private let db: DatabaseQueue
    private var resolved: [String: Entry] = [:]

    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
        // Cheap, indexed read of the SQLite override table so manual
        // renames + generated titles are honored from the very first
        // paint. The expensive JSONL fold (~/.codex/session_index.jsonl)
        // is deferred to a post-paint Task: thread names also come from
        // the runtime via `AgentThreadSummary`, so the sidebar's first
        // paint does not depend on it.
        loadFromDB()
        Task { @MainActor [weak self] in
            self?.reload()
        }
    }

    private func loadFromDB() {
        let rows = (try? db.read { try SessionTitleRow.fetchAll($0) }) ?? []
        var fold: [String: Entry] = [:]
        for row in rows {
            fold[row.threadId] = Entry(
                threadId: row.threadId,
                title: row.title,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                source: row.source
            )
        }
        resolved = fold
    }

    static var runtimeIndexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
    }

    func count() -> Int {
        (try? db.read { try SessionTitleRow.fetchCount($0) }) ?? 0
    }

    func reload() {
        var fold: [String: Entry] = [:]
        Self.mergeJSONL(file: Self.runtimeIndexURL, into: &fold, defaultSource: "runtime")
        let rows = (try? db.read { try SessionTitleRow.fetchAll($0) }) ?? []
        for row in rows {
            let entry = Entry(threadId: row.threadId,
                              title: row.title,
                              updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                              source: row.source)
            if let existing = fold[row.threadId], existing.updatedAt >= entry.updatedAt { continue }
            fold[row.threadId] = entry
        }
        resolved = fold
    }

    func title(for id: String) -> String? {
        guard let entry = resolved[id] else { return nil }
        let trimmed = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func hasTitle(for id: String) -> Bool { title(for: id) != nil }

    func upsertManual(threadId: String, title: String) {
        upsert(threadId: threadId, title: title, source: "manual")
    }

    func upsertGenerated(threadId: String, title: String) {
        upsert(threadId: threadId, title: title, source: "generated")
    }

    private func upsert(threadId: String, title: String, source: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let row = SessionTitleRow(threadId: threadId,
                                  title: trimmed,
                                  updatedAt: Int64(now.timeIntervalSince1970),
                                  source: source)
        try? db.write { try row.upsert($0) }
        resolved[threadId] = Entry(threadId: threadId,
                                   title: trimmed,
                                   updatedAt: now,
                                   source: source)
    }

    static func mergeJSONL(file: URL, into fold: inout [String: Entry], defaultSource: String) {
        guard let data = try? Data(contentsOf: file) else { return }
        let isoMain = ISO8601DateFormatter()
        isoMain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        var start = data.startIndex
        while start < data.endIndex {
            let nl = data[start...].firstIndex(of: 0x0a) ?? data.endIndex
            let line = data[start..<nl]
            start = nl < data.endIndex ? data.index(after: nl) : data.endIndex
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["thread_name"] as? String else { continue }
            let updatedAtStr = obj["updated_at"] as? String ?? ""
            let updatedAt = isoMain.date(from: updatedAtStr)
                ?? isoFallback.date(from: updatedAtStr)
                ?? .distantPast
            let source = (obj["source"] as? String) ?? defaultSource
            let candidate = Entry(threadId: id, title: name, updatedAt: updatedAt, source: source)
            if let existing = fold[id], existing.updatedAt >= candidate.updatedAt { continue }
            fold[id] = candidate
        }
    }
}
