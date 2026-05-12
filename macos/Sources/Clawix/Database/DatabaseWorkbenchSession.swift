import Combine
import Foundation

struct DatabaseWorkbenchQueryDraft: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var sql: String
    var profileID: UUID?
    var updatedAt: Date

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled query" : title
    }

    static func blank(profileID: UUID? = nil) -> DatabaseWorkbenchQueryDraft {
        DatabaseWorkbenchQueryDraft(
            id: UUID(),
            title: "Untitled query",
            sql: "SELECT *\nFROM table_name\nLIMIT 100;",
            profileID: profileID,
            updatedAt: Date()
        )
    }
}

struct DatabaseWorkbenchHistoryEntry: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable, Equatable {
        case dryRun
        case externalPending
        case blocked
    }

    var id: UUID
    var profileName: String
    var statementPreview: String
    var outcome: Outcome
    var message: String
    var createdAt: Date
}

struct DatabaseWorkbenchRunPlan: Equatable {
    enum Status: Equatable {
        case readyForFileProfile
        case externalPending
        case blocked
    }

    enum StatementKind: String, Equatable {
        case empty
        case readOnly
        case write
        case schema
        case transaction
        case unknown
    }

    var status: Status
    var statementKind: StatementKind
    var message: String
    var requiresWriteConfirmation: Bool
}

@MainActor
final class DatabaseWorkbenchSessionStore: ObservableObject {
    static let shared = DatabaseWorkbenchSessionStore()

    @Published var activeSQL: String {
        didSet { persistActiveState() }
    }
    @Published var selectedProfileID: UUID? {
        didSet { persistActiveState() }
    }
    @Published private(set) var drafts: [DatabaseWorkbenchQueryDraft] = []
    @Published private(set) var history: [DatabaseWorkbenchHistoryEntry] = []
    @Published private(set) var console: [String] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let activeSQLKey = "clawix.databaseWorkbench.activeSQL.v1"
    private let selectedProfileKey = "clawix.databaseWorkbench.selectedProfile.v1"
    private let draftsKey = "clawix.databaseWorkbench.queryDrafts.v1"
    private let historyKey = "clawix.databaseWorkbench.history.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        activeSQL = defaults.string(forKey: activeSQLKey) ?? DatabaseWorkbenchQueryDraft.blank().sql
        if let value = defaults.string(forKey: selectedProfileKey) {
            selectedProfileID = UUID(uuidString: value)
        }
        loadDrafts()
        loadHistory()
    }

    func newDraft(profileID: UUID? = nil) {
        let draft = DatabaseWorkbenchQueryDraft.blank(profileID: profileID ?? selectedProfileID)
        drafts.insert(draft, at: 0)
        activeSQL = draft.sql
        selectedProfileID = draft.profileID
        persistDrafts()
        appendConsole("Created query draft.")
    }

    @discardableResult
    func saveDraft(title: String? = nil) -> DatabaseWorkbenchQueryDraft {
        let trimmed = activeSQL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = resolvedTitle?.isEmpty == false ? resolvedTitle! : Self.automaticTitle(for: trimmed)
        let draft = DatabaseWorkbenchQueryDraft(
            id: UUID(),
            title: name,
            sql: activeSQL,
            profileID: selectedProfileID,
            updatedAt: Date()
        )
        drafts.removeAll { $0.sql == draft.sql && $0.profileID == draft.profileID }
        drafts.insert(draft, at: 0)
        drafts = Array(drafts.prefix(100))
        persistDrafts()
        appendConsole("Saved query draft: \(draft.displayTitle).")
        return draft
    }

    func loadDraft(_ draft: DatabaseWorkbenchQueryDraft) {
        activeSQL = draft.sql
        selectedProfileID = draft.profileID
        appendConsole("Loaded query draft: \(draft.displayTitle).")
    }

    func formatActiveSQL() {
        activeSQL = Self.formatSQL(activeSQL)
        appendConsole("Formatted active SQL.")
    }

    @discardableResult
    func dryRun(
        profile: DatabaseConnectionProfile?,
        preferences: DatabaseWorkbenchPreferences = .shared
    ) -> DatabaseWorkbenchRunPlan {
        let plan = Self.runPlan(
            sql: activeSQL,
            profile: profile,
            preferences: preferences,
            fileManager: fileManager
        )
        let entry = DatabaseWorkbenchHistoryEntry(
            id: UUID(),
            profileName: profile?.displayName ?? "No profile",
            statementPreview: Self.statementPreview(activeSQL),
            outcome: plan.status == .blocked ? .blocked : (plan.status == .externalPending ? .externalPending : .dryRun),
            message: plan.message,
            createdAt: Date()
        )
        history.insert(entry, at: 0)
        history = Array(history.prefix(200))
        persistHistory()
        appendConsole(plan.message)
        return plan
    }

    func clearConsole() {
        console.removeAll()
    }

    static func runPlan(
        sql: String,
        profile: DatabaseConnectionProfile?,
        preferences: DatabaseWorkbenchPreferences,
        fileManager: FileManager = .default
    ) -> DatabaseWorkbenchRunPlan {
        let kind = classify(sql)
        guard kind != .empty else {
            return DatabaseWorkbenchRunPlan(
                status: .blocked,
                statementKind: kind,
                message: "SQL editor is empty.",
                requiresWriteConfirmation: false
            )
        }
        guard let profile else {
            return DatabaseWorkbenchRunPlan(
                status: .blocked,
                statementKind: kind,
                message: "Select a connection profile before running SQL.",
                requiresWriteConfirmation: false
            )
        }
        let validation = DatabaseConnectionProfileStore.validationErrors(for: profile)
        guard validation.isEmpty else {
            return DatabaseWorkbenchRunPlan(
                status: .blocked,
                statementKind: kind,
                message: validation.joined(separator: " "),
                requiresWriteConfirmation: false
            )
        }

        let requiresConfirmation = preferences.safeMode != .silent && (kind == .write || kind == .schema || kind == .transaction)
        guard let engine = profile.engine else {
            return DatabaseWorkbenchRunPlan(
                status: .blocked,
                statementKind: kind,
                message: "Unsupported engine.",
                requiresWriteConfirmation: requiresConfirmation
            )
        }

        if engine.supportsFileOpen {
            let path = DatabaseConnectionProfileStore.expanded(profile.hostOrPath)
            guard fileManager.fileExists(atPath: path) else {
                return DatabaseWorkbenchRunPlan(
                    status: .blocked,
                    statementKind: kind,
                    message: "Database file does not exist.",
                    requiresWriteConfirmation: requiresConfirmation
                )
            }
            return DatabaseWorkbenchRunPlan(
                status: .readyForFileProfile,
                statementKind: kind,
                message: "Dry run ready for \(engine.label) file profile. Execution remains disabled until a local runner is wired.",
                requiresWriteConfirmation: requiresConfirmation
            )
        }

        return DatabaseWorkbenchRunPlan(
            status: .externalPending,
            statementKind: kind,
            message: "EXTERNAL PENDING: SQL is prepared, but real connectivity requires explicit approval before opening a network session.",
            requiresWriteConfirmation: requiresConfirmation
        )
    }

    static func classify(_ sql: String) -> DatabaseWorkbenchRunPlan.StatementKind {
        let stripped = sql
            .components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("--") ? "" : line
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return .empty }
        let token = stripped
            .split { !$0.isLetter }
            .first
            .map { String($0).uppercased() } ?? ""
        switch token {
        case "SELECT", "WITH", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "PRAGMA":
            return .readOnly
        case "INSERT", "UPDATE", "DELETE", "MERGE", "REPLACE", "CALL":
            return .write
        case "CREATE", "ALTER", "DROP", "TRUNCATE", "GRANT", "REVOKE":
            return .schema
        case "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT":
            return .transaction
        default:
            return .unknown
        }
    }

    static func formatSQL(_ sql: String) -> String {
        let keywords = [
            "select", "from", "where", "and", "or", "group by", "order by",
            "limit", "offset", "insert", "into", "values", "update", "set",
            "delete", "create", "alter", "drop", "join", "left join", "right join",
            "inner join", "outer join", "on", "having", "returning"
        ]
        var formatted = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        for keyword in keywords.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            formatted = formatted.replacingOccurrences(
                of: pattern,
                with: keyword.uppercased(),
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return formatted
            .replacingOccurrences(of: "\\s+FROM\\s+", with: "\nFROM ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+WHERE\\s+", with: "\nWHERE ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+ORDER BY\\s+", with: "\nORDER BY ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+GROUP BY\\s+", with: "\nGROUP BY ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+LIMIT\\s+", with: "\nLIMIT ", options: .regularExpression)
    }

    static func statementPreview(_ sql: String) -> String {
        let compact = sql
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if compact.count <= 96 { return compact }
        return "\(compact.prefix(93))..."
    }

    static func automaticTitle(for sql: String) -> String {
        let preview = statementPreview(sql)
        return preview.isEmpty ? "Untitled query" : preview
    }

    private func appendConsole(_ line: String) {
        console.insert(line, at: 0)
        console = Array(console.prefix(100))
    }

    private func persistActiveState() {
        defaults.set(activeSQL, forKey: activeSQLKey)
        if let selectedProfileID {
            defaults.set(selectedProfileID.uuidString, forKey: selectedProfileKey)
        } else {
            defaults.removeObject(forKey: selectedProfileKey)
        }
    }

    private func loadDrafts() {
        guard let data = defaults.data(forKey: draftsKey),
              let decoded = try? decoder.decode([DatabaseWorkbenchQueryDraft].self, from: data) else { return }
        drafts = decoded
    }

    private func persistDrafts() {
        guard let data = try? encoder.encode(drafts) else { return }
        defaults.set(data, forKey: draftsKey)
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? decoder.decode([DatabaseWorkbenchHistoryEntry].self, from: data) else { return }
        history = decoded
    }

    private func persistHistory() {
        guard let data = try? encoder.encode(history) else { return }
        defaults.set(data, forKey: historyKey)
    }
}
