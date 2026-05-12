import Combine
import Foundation

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
        let record = DatabaseWorkbenchOperationRecord(
            id: UUID(),
            kind: kind,
            profileName: profile?.displayName ?? "No profile",
            message: plan.message,
            createdAt: Date()
        )
        records.insert(record, at: 0)
        records = Array(records.prefix(100))
        persistRecords()
        return plan
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
