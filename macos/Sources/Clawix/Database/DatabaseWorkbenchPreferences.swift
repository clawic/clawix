import Combine
import Foundation

struct DatabaseWorkbenchEngine: Identifiable, Equatable {
    let id: String
    let label: String
    let defaultPort: Int?
    let supportsFileOpen: Bool
    let supportsSSH: Bool
    let supportsSSL: Bool
}

final class DatabaseWorkbenchPreferences: ObservableObject {
    static let shared = DatabaseWorkbenchPreferences()

    enum CompleteKey: String, CaseIterable, Identifiable {
        case enterOrTab
        case tab
        case enter

        var id: String { rawValue }

        var label: String {
            switch self {
            case .enterOrTab: return "Enter or Tab"
            case .tab:        return "Tab"
            case .enter:      return "Enter"
            }
        }
    }

    enum CSVDelimiter: String, CaseIterable, Identifiable {
        case tab
        case comma
        case semicolon
        case pipe

        var id: String { rawValue }

        var label: String {
            switch self {
            case .tab:       return "Tab"
            case .comma:     return "Comma"
            case .semicolon: return "Semicolon"
            case .pipe:      return "Pipe"
            }
        }
    }

    enum CSVLineBreak: String, CaseIterable, Identifiable {
        case lf
        case crlf
        case cr

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lf:   return "\\n"
            case .crlf: return "\\r\\n"
            case .cr:   return "\\r"
            }
        }
    }

    enum SafeMode: String, CaseIterable, Identifiable {
        case silent
        case confirmWrites
        case requirePassword

        var id: String { rawValue }

        var label: String {
            switch self {
            case .silent:          return "Silent"
            case .confirmWrites:   return "Confirm writes"
            case .requirePassword: return "Require password"
            }
        }
    }

    enum OpenTarget: String, CaseIterable, Identifiable {
        case queryEditor
        case dataBrowser
        case lastWorkspace

        var id: String { rawValue }

        var label: String {
            switch self {
            case .queryEditor:   return "Query editor"
            case .dataBrowser:   return "Data browser"
            case .lastWorkspace: return "Last workspace"
            }
        }
    }

    enum TextEncoding: String, CaseIterable, Identifiable {
        case utf8mb4
        case utf8
        case utf32
        case utf16le
        case utf16
        case ucs2
        case macroman
        case latin1
        case latin2
        case cp1250
        case latin5
        case hebrew
        case greek
        case cp1256
        case cp1257
        case cp1253
        case cp1251
        case ujis
        case sjis
        case euckr
        case big5

        var id: String { rawValue }
        var label: String { rawValue }
    }

    static let supportedEngines: [DatabaseWorkbenchEngine] = [
        .init(id: "postgresql", label: "PostgreSQL", defaultPort: 5432, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "redshift", label: "Amazon Redshift", defaultPort: 5439, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "mysql", label: "MySQL", defaultPort: 3306, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "mariadb", label: "MariaDB & SingleStore", defaultPort: 3306, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "sqlserver", label: "Microsoft SQL Server", defaultPort: 1433, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "cassandra", label: "Cassandra", defaultPort: 9042, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "clickhouse", label: "ClickHouse", defaultPort: 8123, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "bigquery", label: "BigQuery", defaultPort: nil, supportsFileOpen: false, supportsSSH: false, supportsSSL: true),
        .init(id: "dynamodb", label: "DynamoDB", defaultPort: nil, supportsFileOpen: false, supportsSSH: false, supportsSSL: true),
        .init(id: "libsql", label: "LibSQL", defaultPort: nil, supportsFileOpen: true, supportsSSH: false, supportsSSL: true),
        .init(id: "cloudflare-d1", label: "Cloudflare D1", defaultPort: nil, supportsFileOpen: false, supportsSSH: false, supportsSSL: true),
        .init(id: "mongo", label: "Mongo", defaultPort: 27017, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "snowflake", label: "Snowflake", defaultPort: nil, supportsFileOpen: false, supportsSSH: false, supportsSSL: true),
        .init(id: "redis", label: "Redis", defaultPort: 6379, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "sqlite", label: "SQLite", defaultPort: nil, supportsFileOpen: true, supportsSSH: false, supportsSSL: false),
        .init(id: "duckdb", label: "DuckDB", defaultPort: nil, supportsFileOpen: true, supportsSSH: false, supportsSSL: false),
        .init(id: "oracle", label: "Oracle", defaultPort: 1521, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "cockroach", label: "Cockroach", defaultPort: 26257, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "greenplum", label: "Greenplum", defaultPort: 5432, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
        .init(id: "vertica", label: "Vertica", defaultPort: 5433, supportsFileOpen: false, supportsSSH: true, supportsSSL: true),
    ]

    private enum Key {
        static let showItemList = "clawix.databaseWorkbench.showItemList"
        static let showConsoleLog = "clawix.databaseWorkbench.showConsoleLog"
        static let showRowDetail = "clawix.databaseWorkbench.showRowDetail"
        static let autoSaveQueries = "clawix.databaseWorkbench.autoSaveQueries"
        static let uppercaseKeywords = "clawix.databaseWorkbench.uppercaseKeywords"
        static let insertClosingPairs = "clawix.databaseWorkbench.insertClosingPairs"
        static let indentWithTabs = "clawix.databaseWorkbench.indentWithTabs"
        static let indentWidth = "clawix.databaseWorkbench.indentWidth"
        static let completeKey = "clawix.databaseWorkbench.completeKey"
        static let alternatingRows = "clawix.databaseWorkbench.alternatingRows"
        static let autoHideTableScrollers = "clawix.databaseWorkbench.autoHideTableScrollers"
        static let estimateCountThreshold = "clawix.databaseWorkbench.estimateCountThreshold"
        static let csvDelimiter = "clawix.databaseWorkbench.csvDelimiter"
        static let csvLineBreak = "clawix.databaseWorkbench.csvLineBreak"
        static let defaultEncoding = "clawix.databaseWorkbench.defaultEncoding"
        static let queryTimeoutSeconds = "clawix.databaseWorkbench.queryTimeoutSeconds"
        static let keepConnectionAlive = "clawix.databaseWorkbench.keepConnectionAlive"
        static let safeMode = "clawix.databaseWorkbench.safeMode"
        static let passcodeEnabled = "clawix.databaseWorkbench.passcodeEnabled"
        static let openTarget = "clawix.databaseWorkbench.openTarget"
        static let assistantSidebar = "clawix.databaseWorkbench.assistantSidebar"
    }

    private let defaults: UserDefaults

    @Published var showItemList: Bool { didSet { defaults.set(showItemList, forKey: Key.showItemList) } }
    @Published var showConsoleLog: Bool { didSet { defaults.set(showConsoleLog, forKey: Key.showConsoleLog) } }
    @Published var showRowDetail: Bool { didSet { defaults.set(showRowDetail, forKey: Key.showRowDetail) } }
    @Published var autoSaveQueries: Bool { didSet { defaults.set(autoSaveQueries, forKey: Key.autoSaveQueries) } }
    @Published var uppercaseKeywords: Bool { didSet { defaults.set(uppercaseKeywords, forKey: Key.uppercaseKeywords) } }
    @Published var insertClosingPairs: Bool { didSet { defaults.set(insertClosingPairs, forKey: Key.insertClosingPairs) } }
    @Published var indentWithTabs: Bool { didSet { defaults.set(indentWithTabs, forKey: Key.indentWithTabs) } }
    @Published var indentWidth: Int { didSet { defaults.set(indentWidth, forKey: Key.indentWidth) } }
    @Published var completeKey: CompleteKey { didSet { defaults.set(completeKey.rawValue, forKey: Key.completeKey) } }
    @Published var alternatingRows: Bool { didSet { defaults.set(alternatingRows, forKey: Key.alternatingRows) } }
    @Published var autoHideTableScrollers: Bool { didSet { defaults.set(autoHideTableScrollers, forKey: Key.autoHideTableScrollers) } }
    @Published var estimateCountThreshold: Int { didSet { defaults.set(estimateCountThreshold, forKey: Key.estimateCountThreshold) } }
    @Published var csvDelimiter: CSVDelimiter { didSet { defaults.set(csvDelimiter.rawValue, forKey: Key.csvDelimiter) } }
    @Published var csvLineBreak: CSVLineBreak { didSet { defaults.set(csvLineBreak.rawValue, forKey: Key.csvLineBreak) } }
    @Published var defaultEncoding: TextEncoding { didSet { defaults.set(defaultEncoding.rawValue, forKey: Key.defaultEncoding) } }
    @Published var queryTimeoutSeconds: Int { didSet { defaults.set(queryTimeoutSeconds, forKey: Key.queryTimeoutSeconds) } }
    @Published var keepConnectionAlive: Bool { didSet { defaults.set(keepConnectionAlive, forKey: Key.keepConnectionAlive) } }
    @Published var safeMode: SafeMode { didSet { defaults.set(safeMode.rawValue, forKey: Key.safeMode) } }
    @Published var passcodeEnabled: Bool { didSet { defaults.set(passcodeEnabled, forKey: Key.passcodeEnabled) } }
    @Published var openTarget: OpenTarget { didSet { defaults.set(openTarget.rawValue, forKey: Key.openTarget) } }
    @Published var assistantSidebar: Bool { didSet { defaults.set(assistantSidebar, forKey: Key.assistantSidebar) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showItemList = defaults.object(forKey: Key.showItemList) as? Bool ?? true
        showConsoleLog = defaults.object(forKey: Key.showConsoleLog) as? Bool ?? true
        showRowDetail = defaults.object(forKey: Key.showRowDetail) as? Bool ?? true
        autoSaveQueries = defaults.object(forKey: Key.autoSaveQueries) as? Bool ?? true
        uppercaseKeywords = defaults.object(forKey: Key.uppercaseKeywords) as? Bool ?? true
        insertClosingPairs = defaults.object(forKey: Key.insertClosingPairs) as? Bool ?? true
        indentWithTabs = defaults.object(forKey: Key.indentWithTabs) as? Bool ?? true
        indentWidth = Self.clamped(defaults.integer(forKey: Key.indentWidth), defaultValue: 4, range: 1...12)
        completeKey = Self.enumValue(CompleteKey.self, defaults: defaults, key: Key.completeKey, fallback: .enterOrTab)
        alternatingRows = defaults.object(forKey: Key.alternatingRows) as? Bool ?? true
        autoHideTableScrollers = defaults.object(forKey: Key.autoHideTableScrollers) as? Bool ?? false
        estimateCountThreshold = Self.clamped(defaults.integer(forKey: Key.estimateCountThreshold), defaultValue: 500_000, range: 100...50_000_000)
        csvDelimiter = Self.enumValue(CSVDelimiter.self, defaults: defaults, key: Key.csvDelimiter, fallback: .tab)
        csvLineBreak = Self.enumValue(CSVLineBreak.self, defaults: defaults, key: Key.csvLineBreak, fallback: .lf)
        defaultEncoding = Self.enumValue(TextEncoding.self, defaults: defaults, key: Key.defaultEncoding, fallback: .utf8mb4)
        queryTimeoutSeconds = Self.clamped(defaults.integer(forKey: Key.queryTimeoutSeconds), defaultValue: 300, range: 1...86_400)
        keepConnectionAlive = defaults.object(forKey: Key.keepConnectionAlive) as? Bool ?? true
        safeMode = Self.enumValue(SafeMode.self, defaults: defaults, key: Key.safeMode, fallback: .silent)
        passcodeEnabled = defaults.object(forKey: Key.passcodeEnabled) as? Bool ?? false
        openTarget = Self.enumValue(OpenTarget.self, defaults: defaults, key: Key.openTarget, fallback: .queryEditor)
        assistantSidebar = defaults.object(forKey: Key.assistantSidebar) as? Bool ?? false
    }

    func toggleSafeMode() {
        safeMode = safeMode == .silent ? .confirmWrites : .silent
    }

    func reset() {
        showItemList = true
        showConsoleLog = true
        showRowDetail = true
        autoSaveQueries = true
        uppercaseKeywords = true
        insertClosingPairs = true
        indentWithTabs = true
        indentWidth = 4
        completeKey = .enterOrTab
        alternatingRows = true
        autoHideTableScrollers = false
        estimateCountThreshold = 500_000
        csvDelimiter = .tab
        csvLineBreak = .lf
        defaultEncoding = .utf8mb4
        queryTimeoutSeconds = 300
        keepConnectionAlive = true
        safeMode = .silent
        passcodeEnabled = false
        openTarget = .queryEditor
        assistantSidebar = false
    }

    private static func enumValue<T: RawRepresentable>(
        _ type: T.Type,
        defaults: UserDefaults,
        key: String,
        fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else {
            return fallback
        }
        return value
    }

    private static func clamped(_ value: Int, defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let candidate = value == 0 ? defaultValue : value
        return min(max(candidate, range.lowerBound), range.upperBound)
    }
}
