import Foundation
import GRDB

enum CodexStateThreadIndex {
    private static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }

    static func list(limit: Int, pinnedThreadIds: [String]) -> [AgentThreadSummary] {
        let env = ProcessInfo.processInfo.environment
        let url = env["CLAWIX_CODEX_STATE_DB"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? defaultURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        do {
            var config = Configuration()
            config.readonly = true
            let queue = try DatabaseQueue(path: url.path, configuration: config)
            let boundedLimit = max(1, min(limit, 5_000))
            return try queue.read { db in
                var byId: [String: AgentThreadSummary] = [:]
                let recent = try fetchRows(
                    db,
                    sql: "\(selectSQL) FROM threads WHERE archived = 0 ORDER BY updated_at DESC LIMIT ?",
                    arguments: [boundedLimit]
                )
                for thread in recent {
                    byId[thread.id] = thread
                }

                let pins = Array(Set(pinnedThreadIds)).filter { !$0.isEmpty }
                for chunk in pins.chunked(into: 200) {
                    let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                    let pinned = try fetchRows(
                        db,
                        sql: "\(selectSQL) FROM threads WHERE archived = 0 AND id IN (\(placeholders))",
                        arguments: StatementArguments(chunk)
                    )
                    for thread in pinned {
                        byId[thread.id] = thread
                    }
                }

                return byId.values.sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            return []
        }
    }

    private static let selectSQL = """
        SELECT
            id,
            NULLIF(cwd, '') AS cwd,
            NULLIF(title, '') AS name,
            COALESCE(first_user_message, '') AS preview,
            NULLIF(rollout_path, '') AS path,
            CASE
                WHEN created_at_ms IS NOT NULL AND created_at_ms > 0 THEN created_at_ms / 1000
                ELSE created_at
            END AS createdAt,
            CASE
                WHEN updated_at_ms IS NOT NULL AND updated_at_ms > 0 THEN updated_at_ms / 1000
                ELSE updated_at
            END AS updatedAt,
            archived
        """

    private static func fetchRows(
        _ db: GRDB.Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [AgentThreadSummary] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        return rows.compactMap { row in
            guard let id: String = row["id"] else { return nil }
            let cwd: String? = row["cwd"]
            let name: String? = row["name"]
            let preview: String = row["preview"] ?? ""
            let path: String? = row["path"]
            let createdAt: Int64 = row["createdAt"] ?? 0
            let updatedAt: Int64 = row["updatedAt"] ?? createdAt
            let archivedRaw: Int64 = row["archived"] ?? 0
            return AgentThreadSummary(
                id: id,
                cwd: cwd,
                name: name,
                preview: preview,
                path: path,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archived: archivedRaw != 0
            )
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
