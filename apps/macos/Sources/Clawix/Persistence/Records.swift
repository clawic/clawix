import Foundation
import GRDB

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"
    var id: String
    var name: String
    var path: String
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case createdAt = "created_at"
    }
}

struct PinnedThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinned_threads"
    var threadId: String
    var sortOrder: Int64
    var pinnedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case sortOrder = "sort_order"
        case pinnedAt = "pinned_at"
    }
}

struct ChatProjectOverrideRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_project_overrides"
    var threadId: String
    var projectPath: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case projectPath = "project_path"
    }
}

struct ProjectlessThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projectless_threads"
    var threadId: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
    }
}

struct SessionTitleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_titles"
    var threadId: String
    var title: String
    var updatedAt: Int64
    var source: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case title
        case updatedAt = "updated_at"
        case source
    }
}

struct MetaRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meta"
    var key: String
    var value: String
}

struct LocalArchiveRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_archives"
    var threadId: String
    var archivedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case archivedAt = "archived_at"
    }
}

struct HiddenRootRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hidden_codex_roots"
    var path: String
    var hiddenAt: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case hiddenAt = "hidden_at"
    }
}
