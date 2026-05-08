import Foundation

// MARK: - JSON value

/// Type-erased JSON value used as the wire format for record payloads,
/// filter expressions, and other dynamic fields the server returns.
enum DBJSON: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int64)
    case string(String)
    case array([DBJSON])
    case object([String: DBJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([DBJSON].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: DBJSON].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:                 try container.encodeNil()
        case .bool(let value):      try container.encode(value)
        case .integer(let value):   try container.encode(value)
        case .number(let value):    try container.encode(value)
        case .string(let value):    try container.encode(value)
        case .array(let value):     try container.encode(value)
        case .object(let value):    try container.encode(value)
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return nil
        case .array, .object: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    var arrayValue: [DBJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: DBJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Lossy conversion to a Foundation value for encoding into JSON via
    /// JSONSerialization (used when the upstream API expects raw JSON).
    var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .integer(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map { $0.foundationValue }
        case .object(let value):
            var dict: [String: Any] = [:]
            for (k, v) in value { dict[k] = v.foundationValue }
            return dict
        }
    }

    static func wrap(_ value: Any?) -> DBJSON {
        guard let value else { return .null }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? Int64 { return .integer(value) }
        if let value = value as? Int { return .integer(Int64(value)) }
        if let value = value as? Double { return .number(value) }
        if let value = value as? String { return .string(value) }
        if let value = value as? [Any?] { return .array(value.map { wrap($0) }) }
        if let value = value as? [String: Any?] {
            var out: [String: DBJSON] = [:]
            for (k, v) in value { out[k] = wrap(v) }
            return .object(out)
        }
        if value is NSNull { return .null }
        return .null
    }
}

// MARK: - Schema

/// Mirrors the FieldType union the upstream `@clawjs/database` exposes.
enum DBFieldType: String, Codable, Equatable, CaseIterable {
    case text
    case number
    case boolean
    case date
    case json
    case select
    case relation
    case file
    case email
    case url
}

struct DBFieldDefinition: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let type: DBFieldType
    let required: Bool?
    let options: [String]?
    let relation: Relation?

    var id: String { name }

    struct Relation: Codable, Equatable, Hashable {
        let collectionName: String
    }

    var isRequired: Bool { required ?? false }

    /// Heuristic: text fields longer than ~120 chars are rendered as a
    /// long-text editor in the detail pane (multiline) instead of a
    /// single-line input. Names that match common "long text" patterns
    /// promote earlier so we don't have to inspect the data first.
    var prefersLongText: Bool {
        guard type == .text else { return false }
        let lower = name.lowercased()
        return lower.contains("description")
            || lower.contains("body")
            || lower.contains("content")
            || lower.contains("notes")
            || lower.contains("summary")
            || lower.contains("instructions")
            || lower.contains("markdown")
    }
}

struct DBIndexDefinition: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let fields: [String]
    let unique: Bool?

    var id: String { name }
}

struct DBCollection: Codable, Equatable, Hashable, Identifiable {
    let namespaceId: String
    let name: String
    let displayName: String
    let fields: [DBFieldDefinition]
    let indexes: [DBIndexDefinition]
    let builtin: Bool
    let `protected`: Bool
    let coreFieldNames: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { "\(namespaceId).\(name)" }

    /// Field shown as the row title in the table + detail pane. Tries
    /// `title` / `name` / first text field / first field.
    var titleField: DBFieldDefinition? {
        if let f = fields.first(where: { $0.name == "title" }) { return f }
        if let f = fields.first(where: { $0.name == "name" }) { return f }
        if let f = fields.first(where: { $0.type == .text && $0.isRequired }) { return f }
        if let f = fields.first(where: { $0.type == .text }) { return f }
        return fields.first
    }

    /// Subset of fields shown by default in the table (essential
    /// columns). The detail pane always shows all.
    var essentialFields: [DBFieldDefinition] {
        let core = Set(coreFieldNames)
        let essentials = fields.filter { core.contains($0.name) }
        return essentials.isEmpty ? Array(fields.prefix(6)) : essentials
    }

    /// Status field used to power the curated filter tabs and the kanban
    /// view (when present). Returns the first `select` field whose name
    /// is `status` or contains `state`.
    var statusField: DBFieldDefinition? {
        if let f = fields.first(where: { $0.name == "status" && $0.type == .select }) { return f }
        if let f = fields.first(where: { $0.type == .select && $0.name.lowercased().contains("status") }) { return f }
        return nil
    }
}

// MARK: - Records

struct DBRecord: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let createdAt: String
    let updatedAt: String
    /// Field values keyed by field name. The server returns id/createdAt/
    /// updatedAt at the top level AND the rest of the data as siblings;
    /// the decoder merges them all into `data` so consumers don't have
    /// to think about it.
    var data: [String: DBJSON]

    static func == (lhs: DBRecord, rhs: DBRecord) -> Bool {
        lhs.id == rhs.id
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.data == rhs.data
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(updatedAt)
    }

    init(id: String, createdAt: String, updatedAt: String, data: [String: DBJSON]) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var data: [String: DBJSON] = [:]
        var idValue = ""
        var createdAt = ""
        var updatedAt = ""
        for key in container.allKeys {
            if key.stringValue == "id" {
                idValue = (try? container.decode(String.self, forKey: key)) ?? ""
            } else if key.stringValue == "createdAt" {
                createdAt = (try? container.decode(String.self, forKey: key)) ?? ""
            } else if key.stringValue == "updatedAt" {
                updatedAt = (try? container.decode(String.self, forKey: key)) ?? ""
            } else {
                data[key.stringValue] = try container.decode(DBJSON.self, forKey: key)
            }
        }
        self.id = idValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.data = data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encode(id, forKey: AnyKey("id"))
        try container.encode(createdAt, forKey: AnyKey("createdAt"))
        try container.encode(updatedAt, forKey: AnyKey("updatedAt"))
        for (k, v) in data {
            try container.encode(v, forKey: AnyKey(k))
        }
    }

    var titleString: String {
        if case .string(let value) = data["title"] ?? .null, !value.isEmpty { return value }
        if case .string(let value) = data["name"] ?? .null, !value.isEmpty { return value }
        if case .string(let value) = data["identifier"] ?? .null, !value.isEmpty { return value }
        return id
    }

    var isArchived: Bool {
        if let v = data["archivedAt"], case .string(let s) = v, !s.isEmpty { return true }
        return false
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// MARK: - Namespaces / files / tokens

struct DBNamespace: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let createdAt: String
    let updatedAt: String
}

struct DBFileAsset: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let namespaceId: String
    let collectionName: String?
    let recordId: String?
    let filename: String
    let contentType: String
    let sizeBytes: Int64
    let createdAt: String
    let downloadPath: String
}

struct DBScopedToken: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let label: String
    let namespaceId: String
    let collectionName: String?
    let operations: [String]
    let createdAt: String
    let lastUsedAt: String?
    let revokedAt: String?
}

// MARK: - Realtime events

struct DBRecordEvent: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case created = "record.created"
        case updated = "record.updated"
        case deleted = "record.deleted"
    }

    let type: Kind
    let namespaceId: String
    let collectionName: String
    let recordId: String
    let record: DBRecord?
    let at: String
}

// MARK: - List response

struct DBListResponse<Item: Codable & Equatable>: Codable, Equatable {
    let total: Int?
    let items: [Item]
}

// MARK: - Filter state

/// Logical filter state used by the UI. The HTTP client serializes it to
/// the server's expected JSON filter (a flat `field=value` map).
struct DBFilterState: Equatable, Hashable, Codable {
    enum Op: String, Equatable, Hashable, Codable {
        case eq
        case neq
        case isNull
        case notNull
    }

    struct Chip: Equatable, Hashable, Codable, Identifiable {
        var id = UUID()
        var field: String
        var op: Op
        var value: DBJSON

        init(id: UUID = UUID(), field: String, op: Op, value: DBJSON) {
            self.id = id
            self.field = field
            self.op = op
            self.value = value
        }
    }

    struct Sort: Equatable, Hashable, Codable {
        var field: String
        var descending: Bool
    }

    var chips: [Chip] = []
    var sort: Sort?
    var search: String = ""

    /// Builds the JSON dict the server consumes (`?filter=...`).
    /// The server's flat filter is field=value; isNull/notNull and neq
    /// are post-filtered client-side until the backend gains a richer
    /// filter language.
    func backendFilterJSON() -> [String: Any]? {
        var dict: [String: Any] = [:]
        for chip in chips where chip.op == .eq {
            dict[chip.field] = chip.value.foundationValue
        }
        return dict.isEmpty ? nil : dict
    }

    func clientSidePostFilter(records: [DBRecord]) -> [DBRecord] {
        guard !chips.isEmpty || !search.isEmpty else { return records }
        let needle = search.lowercased()
        return records.filter { record in
            // search across stringy fields
            if !needle.isEmpty {
                let haystack = record.data.values.compactMap { $0.stringValue?.lowercased() }
                let matches = haystack.contains { $0.contains(needle) }
                let titleHit = record.titleString.lowercased().contains(needle)
                if !matches && !titleHit { return false }
            }
            for chip in chips {
                let value = record.data[chip.field] ?? .null
                switch chip.op {
                case .eq:       if value != chip.value { return false }
                case .neq:      if value == chip.value { return false }
                case .isNull:   if !value.isNull { return false }
                case .notNull:  if value.isNull { return false }
                }
            }
            return true
        }
    }

    func sortString() -> String? {
        guard let sort else { return nil }
        return sort.descending ? "-\(sort.field)" : sort.field
    }
}
