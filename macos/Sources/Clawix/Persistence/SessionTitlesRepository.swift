import Foundation
import GRDB

// Resolves conversation title overrides written by this app: manual user
// renames and generated titles. Runtime-provided titles arrive through the
// ClawJS sessions adapter and are not read from Codex-owned JSONL files here.
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
        loadFromDB()
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

    func count() -> Int {
        (try? db.read { try SessionTitleRow.fetchCount($0) }) ?? 0
    }

    func reload() {
        loadFromDB()
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
        ClawJSAppStateClient.upsertTitle(threadId: threadId, title: trimmed, source: source)
    }
}
