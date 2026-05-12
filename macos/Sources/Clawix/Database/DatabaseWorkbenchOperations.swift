import Combine
import Foundation
import GRDB

enum DatabaseWorkbenchOperationKind: String, Codable, CaseIterable, Identifiable {
    case importCSV
    case importSQLDump
    case exportTable
    case exportQuery
    case backupDatabase
    case restoreDatabase
    case userManagement
    case processList
    case databaseSearch
    case pluginScript

    var id: String { rawValue }

    var label: String {
        switch self {
        case .importCSV:      return "Import CSV"
        case .importSQLDump:  return "Import SQL dump"
        case .exportTable:    return "Export table"
        case .exportQuery:    return "Export query"
        case .backupDatabase: return "Backup database"
        case .restoreDatabase:return "Restore database"
        case .userManagement: return "User management"
        case .processList:    return "Process list"
        case .databaseSearch: return "Search database"
        case .pluginScript:   return "Run plugin script"
        }
    }

    var detail: String {
        switch self {
        case .importCSV:
            return "Prepare a CSV import from the configured local input path."
        case .importSQLDump:
            return "Prepare a SQL dump import from the configured local input path."
        case .exportTable:
            return "Prepare an export for a table or view into the configured output path."
        case .exportQuery:
            return "Prepare an export for the active query into the configured output path."
        case .backupDatabase:
            return "Prepare a database backup into the configured output path."
        case .restoreDatabase:
            return "Prepare a restore from the configured local input path."
        case .userManagement:
            return "Open the user and permissions workflow for the selected profile."
        case .processList:
            return "Open the active sessions and query process workflow."
        case .databaseSearch:
            return "Search metadata/data using the configured search term."
        case .pluginScript:
            return "Prepare a local plugin script run without executing it."
        }
    }

    var usesInputPath: Bool {
        switch self {
        case .importCSV, .importSQLDump, .restoreDatabase:
            return true
        case .exportTable, .exportQuery, .backupDatabase, .userManagement, .processList, .databaseSearch, .pluginScript:
            return false
        }
    }

    var usesOutputPath: Bool {
        switch self {
        case .exportTable, .exportQuery, .backupDatabase:
            return true
        case .importCSV, .importSQLDump, .restoreDatabase, .userManagement, .processList, .databaseSearch, .pluginScript:
            return false
        }
    }
}

struct DatabaseWorkbenchOperationPlan: Equatable {
    enum Status: Equatable {
        case localReady
        case externalPending
        case blocked
    }

    var kind: DatabaseWorkbenchOperationKind
    var status: Status
    var message: String
}

struct DatabaseWorkbenchOperationRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: DatabaseWorkbenchOperationKind
    var profileName: String
    var message: String
    var createdAt: Date
}

@MainActor
final class DatabaseWorkbenchOperationStore: ObservableObject {
    static let shared = DatabaseWorkbenchOperationStore()

    @Published var inputPath: String {
        didSet { persistState() }
    }
    @Published var outputPath: String {
        didSet { persistState() }
    }
    @Published var objectName: String {
        didSet { persistState() }
    }
    @Published var searchTerm: String {
        didSet { persistState() }
    }
    @Published var pluginScript: String {
        didSet { persistState() }
    }
    @Published private(set) var records: [DatabaseWorkbenchOperationRecord] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let inputPathKey = "clawix.databaseWorkbench.operationInputPath.v1"
    private let outputPathKey = "clawix.databaseWorkbench.operationOutputPath.v1"
    private let objectNameKey = "clawix.databaseWorkbench.operationObjectName.v1"
    private let searchTermKey = "clawix.databaseWorkbench.operationSearchTerm.v1"
    private let pluginScriptKey = "clawix.databaseWorkbench.operationPluginScript.v1"
    private let recordsKey = "clawix.databaseWorkbench.operationRecords.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        inputPath = defaults.string(forKey: inputPathKey) ?? ""
        outputPath = defaults.string(forKey: outputPathKey) ?? ""
        objectName = defaults.string(forKey: objectNameKey) ?? ""
        searchTerm = defaults.string(forKey: searchTermKey) ?? ""
        pluginScript = defaults.string(forKey: pluginScriptKey) ?? ""
        loadRecords()
    }

    @discardableResult
    func perform(
        _ kind: DatabaseWorkbenchOperationKind,
        profile: DatabaseConnectionProfile?,
        activeSQL: String,
        preferences: DatabaseWorkbenchPreferences = .shared
    ) -> DatabaseWorkbenchOperationPlan {
        let plan = Self.perform(
            kind,
            profile: profile,
            activeSQL: activeSQL,
            preferences: preferences,
            inputPath: inputPath,
            outputPath: outputPath,
            objectName: objectName,
            searchTerm: searchTerm,
            pluginScript: pluginScript,
            fileManager: fileManager
        )
        record(plan, profile: profile)
        return plan
    }

    @discardableResult
    func plan(
        _ kind: DatabaseWorkbenchOperationKind,
        profile: DatabaseConnectionProfile?
    ) -> DatabaseWorkbenchOperationPlan {
        let plan = Self.plan(
            kind,
            profile: profile,
            inputPath: inputPath,
            outputPath: outputPath,
            objectName: objectName,
            searchTerm: searchTerm,
            pluginScript: pluginScript,
            fileManager: fileManager
        )
        record(plan, profile: profile)
        return plan
    }

    static func perform(
        _ kind: DatabaseWorkbenchOperationKind,
        profile: DatabaseConnectionProfile?,
        activeSQL: String,
        preferences: DatabaseWorkbenchPreferences,
        inputPath: String,
        outputPath: String,
        objectName: String,
        searchTerm: String,
        pluginScript: String,
        fileManager: FileManager = .default
    ) -> DatabaseWorkbenchOperationPlan {
        let prepared = plan(
            kind,
            profile: profile,
            inputPath: inputPath,
            outputPath: outputPath,
            objectName: objectName,
            searchTerm: searchTerm,
            pluginScript: pluginScript,
            fileManager: fileManager
        )
        guard prepared.status == .externalPending, let profile else {
            return prepared
        }
        guard profile.engineId == "sqlite" else {
            return prepared
        }

        switch kind {
        case .importCSV:
            return importSQLiteCSV(
                inputPath: inputPath,
                objectName: objectName,
                profile: profile,
                preferences: preferences,
                fileManager: fileManager
            )
        case .importSQLDump:
            return importSQLiteSQLDump(
                inputPath: inputPath,
                profile: profile,
                fileManager: fileManager
            )
        case .exportQuery:
            return exportSQLiteQuery(
                activeSQL,
                profile: profile,
                outputPath: outputPath,
                preferences: preferences,
                fileManager: fileManager
            )
        case .exportTable:
            return exportSQLiteTable(
                objectName,
                profile: profile,
                outputPath: outputPath,
                preferences: preferences,
                fileManager: fileManager
            )
        case .backupDatabase:
            return backupSQLiteDatabase(
                profile,
                outputPath: outputPath,
                fileManager: fileManager
            )
        default:
            return prepared
        }
    }

    private func record(_ plan: DatabaseWorkbenchOperationPlan, profile: DatabaseConnectionProfile?) {
        let record = DatabaseWorkbenchOperationRecord(
            id: UUID(),
            kind: plan.kind,
            profileName: profile?.displayName ?? "No profile",
            message: plan.message,
            createdAt: Date()
        )
        records.insert(record, at: 0)
        records = Array(records.prefix(100))
        persistRecords()
    }

    static func plan(
        _ kind: DatabaseWorkbenchOperationKind,
        profile: DatabaseConnectionProfile?,
        inputPath: String,
        outputPath: String,
        objectName: String,
        searchTerm: String,
        pluginScript: String,
        fileManager: FileManager = .default
    ) -> DatabaseWorkbenchOperationPlan {
        guard let profile else {
            return .init(kind: kind, status: .blocked, message: "Select a connection profile before preparing \(kind.label.lowercased()).")
        }
        let validation = DatabaseConnectionProfileStore.validationErrors(for: profile)
        guard validation.isEmpty else {
            return .init(kind: kind, status: .blocked, message: validation.joined(separator: " "))
        }

        if kind.usesInputPath {
            let resolved = DatabaseConnectionProfileStore.expanded(inputPath)
            guard !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(kind: kind, status: .blocked, message: "Choose an input file before preparing \(kind.label.lowercased()).")
            }
            guard fileManager.fileExists(atPath: resolved) else {
                return .init(kind: kind, status: .blocked, message: "Input file does not exist.")
            }
        }

        if kind.usesOutputPath {
            let resolved = DatabaseConnectionProfileStore.expanded(outputPath)
            guard !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(kind: kind, status: .blocked, message: "Choose an output path before preparing \(kind.label.lowercased()).")
            }
        }

        switch kind {
        case .importCSV where objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .init(kind: kind, status: .blocked, message: "Enter a table name before preparing CSV import.")
        case .exportTable where objectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .init(kind: kind, status: .blocked, message: "Enter a table or view name before preparing export.")
        case .databaseSearch where searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .init(kind: kind, status: .blocked, message: "Enter a search term before preparing database search.")
        case .pluginScript where pluginScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .init(kind: kind, status: .blocked, message: "Enter a plugin script before preparing a plugin run.")
        default:
            break
        }

        return .init(
            kind: kind,
            status: .externalPending,
            message: "EXTERNAL PENDING: \(kind.label) is prepared for \(profile.displayName). Real execution requires explicit approval."
        )
    }

    private static func importSQLiteCSV(
        inputPath: String,
        objectName: String,
        profile: DatabaseConnectionProfile,
        preferences: DatabaseWorkbenchPreferences,
        fileManager: FileManager
    ) -> DatabaseWorkbenchOperationPlan {
        let source = DatabaseConnectionProfileStore.expanded(inputPath)
        guard let table = quotedSQLiteIdentifier(objectName) else {
            return .init(kind: .importCSV, status: .blocked, message: "Use a simple table name before importing locally.")
        }

        do {
            let csv = try String(contentsOfFile: source, encoding: .utf8)
            let rows = try parseCSV(
                csv,
                delimiter: csvDelimiter(preferences.csvDelimiter)
            )
            guard let header = rows.first, !header.isEmpty else {
                return .init(kind: .importCSV, status: .blocked, message: "CSV import failed: CSV header is empty.")
            }
            let columns = try header.map { column -> String in
                guard let quoted = quotedSQLiteIdentifier(column) else {
                    throw DatabaseWorkbenchLocalOperationError.invalidCSVHeader
                }
                return quoted
            }
            let dataRows = rows.dropFirst().filter { row in
                row.count > 1 || row.first?.isEmpty == false
            }
            guard dataRows.allSatisfy({ $0.count == header.count }) else {
                return .init(kind: .importCSV, status: .blocked, message: "CSV import failed: row column counts do not match the header.")
            }

            let databasePath = DatabaseConnectionProfileStore.expanded(profile.hostOrPath)
            guard fileManager.fileExists(atPath: databasePath) else {
                return .init(kind: .importCSV, status: .blocked, message: "SQLite import failed: database file does not exist.")
            }

            let queue = try DatabaseQueue(path: databasePath)
            try queue.write { db in
                let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
                let sql = "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"
                for row in dataRows {
                    try db.execute(sql: sql, arguments: StatementArguments(row))
                }
            }
            return .init(kind: .importCSV, status: .localReady, message: "SQLite CSV import wrote \(dataRows.count) row\(dataRows.count == 1 ? "" : "s").")
        } catch {
            return .init(kind: .importCSV, status: .blocked, message: "SQLite CSV import failed: \(error.localizedDescription)")
        }
    }

    private static func importSQLiteSQLDump(
        inputPath: String,
        profile: DatabaseConnectionProfile,
        fileManager: FileManager
    ) -> DatabaseWorkbenchOperationPlan {
        let source = DatabaseConnectionProfileStore.expanded(inputPath)
        let databasePath = DatabaseConnectionProfileStore.expanded(profile.hostOrPath)
        guard fileManager.fileExists(atPath: databasePath) else {
            return .init(kind: .importSQLDump, status: .blocked, message: "SQLite SQL dump import failed: database file does not exist.")
        }

        do {
            let sql = try String(contentsOfFile: source, encoding: .utf8)
            guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(kind: .importSQLDump, status: .blocked, message: "SQL dump import failed: SQL file is empty.")
            }
            let queue = try DatabaseQueue(path: databasePath)
            try queue.write { db in
                try db.execute(sql: sql)
            }
            return .init(kind: .importSQLDump, status: .localReady, message: "SQLite SQL dump import finished.")
        } catch {
            return .init(kind: .importSQLDump, status: .blocked, message: "SQLite SQL dump import failed: \(error.localizedDescription)")
        }
    }

    private static func exportSQLiteQuery(
        _ sql: String,
        profile: DatabaseConnectionProfile,
        outputPath: String,
        preferences: DatabaseWorkbenchPreferences,
        fileManager: FileManager
    ) -> DatabaseWorkbenchOperationPlan {
        guard DatabaseWorkbenchSessionStore.classify(sql) == .readOnly else {
            return .init(kind: .exportQuery, status: .blocked, message: "Only read-only SQLite queries can be exported locally.")
        }

        do {
            let result = try DatabaseWorkbenchSessionStore.runSQLiteReadOnly(
                sql: sql,
                profile: profile,
                fileManager: fileManager,
                rowLimit: 10_000
            )
            try writeCSV(result, outputPath: outputPath, preferences: preferences, fileManager: fileManager)
            return .init(kind: .exportQuery, status: .localReady, message: "SQLite query export wrote \(result.rows.count) row\(result.rows.count == 1 ? "" : "s").")
        } catch {
            return .init(kind: .exportQuery, status: .blocked, message: "SQLite query export failed: \(error.localizedDescription)")
        }
    }

    private static func exportSQLiteTable(
        _ objectName: String,
        profile: DatabaseConnectionProfile,
        outputPath: String,
        preferences: DatabaseWorkbenchPreferences,
        fileManager: FileManager
    ) -> DatabaseWorkbenchOperationPlan {
        guard let identifier = quotedSQLiteIdentifier(objectName) else {
            return .init(kind: .exportTable, status: .blocked, message: "Use a simple table or view name before exporting locally.")
        }

        do {
            let result = try DatabaseWorkbenchSessionStore.runSQLiteReadOnly(
                sql: "SELECT * FROM \(identifier)",
                profile: profile,
                fileManager: fileManager,
                rowLimit: 10_000
            )
            try writeCSV(result, outputPath: outputPath, preferences: preferences, fileManager: fileManager)
            return .init(kind: .exportTable, status: .localReady, message: "SQLite table export wrote \(result.rows.count) row\(result.rows.count == 1 ? "" : "s").")
        } catch {
            return .init(kind: .exportTable, status: .blocked, message: "SQLite table export failed: \(error.localizedDescription)")
        }
    }

    private static func backupSQLiteDatabase(
        _ profile: DatabaseConnectionProfile,
        outputPath: String,
        fileManager: FileManager
    ) -> DatabaseWorkbenchOperationPlan {
        let source = DatabaseConnectionProfileStore.expanded(profile.hostOrPath)
        let target = DatabaseConnectionProfileStore.expanded(outputPath)
        do {
            try validateNewOutputPath(target, fileManager: fileManager)
            guard source != target else {
                return .init(kind: .backupDatabase, status: .blocked, message: "Backup output must be different from the source database.")
            }
            try fileManager.copyItem(atPath: source, toPath: target)
            return .init(kind: .backupDatabase, status: .localReady, message: "SQLite backup wrote \(target).")
        } catch {
            return .init(kind: .backupDatabase, status: .blocked, message: "SQLite backup failed: \(error.localizedDescription)")
        }
    }

    private static func writeCSV(
        _ result: DatabaseWorkbenchResultSet,
        outputPath: String,
        preferences: DatabaseWorkbenchPreferences,
        fileManager: FileManager
    ) throws {
        let target = DatabaseConnectionProfileStore.expanded(outputPath)
        try validateNewOutputPath(target, fileManager: fileManager)
        let delimiter = csvDelimiter(preferences.csvDelimiter)
        let lineBreak = csvLineBreak(preferences.csvLineBreak)
        var lines: [String] = []
        lines.append(result.columns.map { csvCell($0, delimiter: delimiter) }.joined(separator: delimiter))
        for row in result.rows {
            lines.append(row.map { csvCell($0, delimiter: delimiter) }.joined(separator: delimiter))
        }
        let body = lines.joined(separator: lineBreak) + lineBreak
        try body.write(toFile: target, atomically: true, encoding: .utf8)
    }

    private static func validateNewOutputPath(_ path: String, fileManager: FileManager) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseWorkbenchLocalOperationError.emptyOutputPath
        }
        guard !fileManager.fileExists(atPath: trimmed) else {
            throw DatabaseWorkbenchLocalOperationError.outputAlreadyExists
        }
        let parent = (trimmed as NSString).deletingLastPathComponent
        guard parent.isEmpty || fileManager.fileExists(atPath: parent) else {
            throw DatabaseWorkbenchLocalOperationError.outputDirectoryMissing
        }
    }

    private static func quotedSQLiteIdentifier(_ raw: String) -> String? {
        let parts = raw
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...2).contains(parts.count) else { return nil }
        let allowed = try? NSRegularExpression(pattern: #"^[A-Za-z_][A-Za-z0-9_]*$"#)
        let quoted = parts.compactMap { part -> String? in
            let range = NSRange(part.startIndex..<part.endIndex, in: part)
            guard allowed?.firstMatch(in: part, range: range) != nil else { return nil }
            return "\"\(part)\""
        }
        guard quoted.count == parts.count else { return nil }
        return quoted.joined(separator: ".")
    }

    private static func csvCell(_ value: String, delimiter: String) -> String {
        let needsQuotes = value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ body: String, delimiter: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var index = body.startIndex
        var quoted = false

        func appendField() {
            row.append(field)
            field.removeAll(keepingCapacity: true)
        }

        func appendRow() {
            appendField()
            if row.count > 1 || row.first?.isEmpty == false {
                rows.append(row)
            }
            row.removeAll(keepingCapacity: true)
        }

        while index < body.endIndex {
            let character = body[index]
            let nextIndex = body.index(after: index)

            if quoted {
                if character == "\"" {
                    if nextIndex < body.endIndex, body[nextIndex] == "\"" {
                        field.append("\"")
                        index = body.index(after: nextIndex)
                    } else {
                        quoted = false
                        index = nextIndex
                    }
                } else {
                    field.append(character)
                    index = nextIndex
                }
                continue
            }

            if character == "\"" && field.isEmpty {
                quoted = true
                index = nextIndex
            } else if String(character) == delimiter {
                appendField()
                index = nextIndex
            } else if character == "\n" {
                appendRow()
                index = nextIndex
            } else if character == "\r" {
                appendRow()
                if nextIndex < body.endIndex, body[nextIndex] == "\n" {
                    index = body.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            } else {
                field.append(character)
                index = nextIndex
            }
        }

        if quoted {
            throw DatabaseWorkbenchLocalOperationError.malformedCSV
        }
        if !field.isEmpty || !row.isEmpty {
            appendRow()
        }
        return rows
    }

    private static func csvDelimiter(_ delimiter: DatabaseWorkbenchPreferences.CSVDelimiter) -> String {
        switch delimiter {
        case .tab:       return "\t"
        case .comma:     return ","
        case .semicolon: return ";"
        case .pipe:      return "|"
        }
    }

    private static func csvLineBreak(_ lineBreak: DatabaseWorkbenchPreferences.CSVLineBreak) -> String {
        switch lineBreak {
        case .lf:   return "\n"
        case .crlf: return "\r\n"
        case .cr:   return "\r"
        }
    }

    private func persistState() {
        defaults.set(inputPath, forKey: inputPathKey)
        defaults.set(outputPath, forKey: outputPathKey)
        defaults.set(objectName, forKey: objectNameKey)
        defaults.set(searchTerm, forKey: searchTermKey)
        defaults.set(pluginScript, forKey: pluginScriptKey)
    }

    private func loadRecords() {
        guard let data = defaults.data(forKey: recordsKey),
              let decoded = try? decoder.decode([DatabaseWorkbenchOperationRecord].self, from: data) else { return }
        records = decoded
    }

    private func persistRecords() {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: recordsKey)
    }
}

enum DatabaseWorkbenchLocalOperationError: LocalizedError, Equatable {
    case emptyOutputPath
    case outputAlreadyExists
    case outputDirectoryMissing
    case invalidCSVHeader
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .emptyOutputPath:
            return "Choose an output path before running the local operation."
        case .outputAlreadyExists:
            return "Output file already exists."
        case .outputDirectoryMissing:
            return "Output folder does not exist."
        case .invalidCSVHeader:
            return "CSV header contains a column name that cannot be mapped safely."
        case .malformedCSV:
            return "CSV contains an unclosed quoted field."
        }
    }
}
