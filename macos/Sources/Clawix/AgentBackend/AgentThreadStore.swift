import Foundation

struct AgentThreadSummary: Codable, Identifiable, Hashable {
    let id: String
    let cwd: String?
    let name: String?
    let preview: String
    let path: String?
    let createdAt: Int64
    let updatedAt: Int64
    var archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, cwd, name, preview, path, createdAt, updatedAt, archived
    }

    init(
        id: String,
        cwd: String?,
        name: String?,
        preview: String,
        path: String?,
        createdAt: Int64,
        updatedAt: Int64,
        archived: Bool = false
    ) {
        self.id = id
        self.cwd = cwd
        self.name = name
        self.preview = preview
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        self.path = try c.decodeIfPresent(String.self, forKey: .path)
        self.createdAt = Self.decodeInt64IfPresent(c, forKey: .createdAt) ?? 0
        self.updatedAt = Self.decodeInt64IfPresent(c, forKey: .updatedAt) ?? self.createdAt
        self.archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    private static func decodeInt64IfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64? {
        if let value = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            if let int = Int64(value) { return int }
            if let double = Double(value) { return Int64(double) }
        }
        return nil
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}

enum AgentThreadStore {
    static func fixtureThreads() -> [AgentThreadSummary]? {
        guard
            let raw = ProcessInfo.processInfo.environment["CLAWIX_THREAD_FIXTURE"],
            !raw.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AgentThreadSummary].self, from: data)) ?? []
    }
}
