import XCTest
import GRDB
@testable import Clawix

@MainActor
final class DatabaseWorkbenchOperationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DatabaseWorkbenchOperationTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_allAuditedOperationEntrypointsAreRepresented() {
        let labels = Set(DatabaseWorkbenchOperationKind.allCases.map(\.label))

        XCTAssertTrue(labels.contains("Import CSV"))
        XCTAssertTrue(labels.contains("Import SQL dump"))
        XCTAssertTrue(labels.contains("Export table"))
        XCTAssertTrue(labels.contains("Export query"))
        XCTAssertTrue(labels.contains("Backup database"))
        XCTAssertTrue(labels.contains("Restore database"))
        XCTAssertTrue(labels.contains("User management"))
        XCTAssertTrue(labels.contains("Process list"))
        XCTAssertTrue(labels.contains("Search database"))
        XCTAssertTrue(labels.contains("Run plugin script"))
    }

    func test_operationRequiresProfileBeforePlanning() {
        let plan = DatabaseWorkbenchOperationStore.plan(
            .exportQuery,
            profile: nil,
            inputPath: "",
            outputPath: "/tmp/query.csv",
            objectName: "",
            searchTerm: "",
            pluginScript: ""
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.message.contains("Select a connection profile"))
    }

    func test_importRequiresExistingInputFile() {
        let profile = DatabaseConnectionProfile.draft()
        let plan = DatabaseWorkbenchOperationStore.plan(
            .importCSV,
            profile: profile,
            inputPath: "/tmp/does-not-exist.csv",
            outputPath: "",
            objectName: "",
            searchTerm: "",
            pluginScript: ""
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertEqual(plan.message, "Input file does not exist.")
    }

    func test_networkOperationStaysExternalPendingAfterValidation() {
        let profile = DatabaseConnectionProfile.draft()
        let plan = DatabaseWorkbenchOperationStore.plan(
            .databaseSearch,
            profile: profile,
            inputPath: "",
            outputPath: "",
            objectName: "",
            searchTerm: "invoice",
            pluginScript: ""
        )

        XCTAssertEqual(plan.status, .externalPending)
        XCTAssertTrue(plan.message.contains("EXTERNAL PENDING"))
    }

    func test_storePersistsOperationRecordsAndFields() {
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.outputPath = "/tmp/export.csv"
        _ = store.plan(.exportQuery, profile: DatabaseConnectionProfile.draft())

        let reloaded = DatabaseWorkbenchOperationStore(defaults: defaults)
        XCTAssertEqual(reloaded.outputPath, "/tmp/export.csv")
        XCTAssertEqual(reloaded.records.first?.kind, .exportQuery)
    }

    func test_sqliteCSVImportWritesRows() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("users.csv")
        try "id,name\n1,Ada\n2,\"Linus, Torvalds\"\n".write(to: input, atomically: true, encoding: .utf8)
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.csvDelimiter = .comma
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path
        store.objectName = "users"

        let plan = store.perform(
            .importCSV,
            profile: paths.profile,
            activeSQL: "",
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertEqual(plan.message, "SQLite CSV import wrote 2 rows.")
        let queue = try DatabaseQueue(path: paths.database.path)
        let names = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM users ORDER BY id")
        }
        XCTAssertEqual(names, ["Ada", "Linus, Torvalds"])
    }

    func test_sqliteCSVImportRequiresTableName() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("users.csv")
        try "id,name\n1,Ada\n".write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path

        let plan = store.perform(
            .importCSV,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertEqual(plan.message, "Enter a table name before preparing CSV import.")
    }

    func test_sqliteCSVImportBlocksMismatchedRows() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("users.csv")
        try "id,name\n1,Ada,extra\n".write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path
        store.objectName = "users"
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.csvDelimiter = .comma

        let plan = store.perform(
            .importCSV,
            profile: paths.profile,
            activeSQL: "",
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.message.contains("row column counts do not match"), plan.message)
    }

    func test_sqliteCSVImportBlocksMalformedQuotedInput() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("users.csv")
        try "id,name\n1,\"Ada\n".write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path
        store.objectName = "users"
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.csvDelimiter = .comma

        let plan = store.perform(
            .importCSV,
            profile: paths.profile,
            activeSQL: "",
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.message.contains("unclosed quoted field"), plan.message)
    }

    func test_sqliteSQLDumpImportExecutesLocalDump() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("users.sql")
        try """
        INSERT INTO users (id, name) VALUES (1, 'Ada');
        INSERT INTO users (id, name) VALUES (2, 'Linus, Torvalds');
        """.write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path

        let plan = store.perform(
            .importSQLDump,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertEqual(plan.message, "SQLite SQL dump import finished.")
        let queue = try DatabaseQueue(path: paths.database.path)
        let names = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM users ORDER BY id")
        }
        XCTAssertEqual(names, ["Ada", "Linus, Torvalds"])
    }

    func test_sqliteSQLDumpImportBlocksEmptyInput() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("empty.sql")
        try "\n  \n".write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path

        let plan = store.perform(
            .importSQLDump,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertEqual(plan.message, "SQL dump import failed: SQL file is empty.")
    }

    func test_sqliteSQLDumpImportReportsMalformedSQL() throws {
        let paths = try makeSQLiteFixture(includeRows: false)
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let input = paths.directory.appendingPathComponent("bad.sql")
        try "INSERT INTO missing_table (id) VALUES (1);".write(to: input, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = input.path

        let plan = store.perform(
            .importSQLDump,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.message.contains("SQLite SQL dump import failed"), plan.message)
    }

    func test_sqliteQueryExportWritesCSV() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let output = paths.directory.appendingPathComponent("query.csv")
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.csvDelimiter = .comma
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.outputPath = output.path

        let plan = store.perform(
            .exportQuery,
            profile: paths.profile,
            activeSQL: "SELECT id, name FROM users ORDER BY id",
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertEqual(
            try String(contentsOf: output, encoding: .utf8),
            "id,name\n1,Ada\n2,\"Linus, Torvalds\"\n"
        )
        XCTAssertEqual(store.records.first?.kind, .exportQuery)
    }

    func test_sqliteTableExportEscapesCSVCells() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let output = paths.directory.appendingPathComponent("table.csv")
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.csvDelimiter = .comma
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.outputPath = output.path
        store.objectName = "users"

        let plan = store.perform(
            .exportTable,
            profile: paths.profile,
            activeSQL: "",
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertEqual(
            try String(contentsOf: output, encoding: .utf8),
            "id,name\n1,Ada\n2,\"Linus, Torvalds\"\n"
        )
    }

    func test_sqliteBackupCopiesDatabaseWithoutOverwriting() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let output = paths.directory.appendingPathComponent("backup.sqlite")
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.outputPath = output.path

        let plan = store.perform(
            .backupDatabase,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

        let overwrite = store.perform(
            .backupDatabase,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )
        XCTAssertEqual(overwrite.status, .blocked)
        XCTAssertTrue(overwrite.message.contains("Output file already exists"))
    }

    func test_sqliteRestoreReplacesLocalDatabase() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let restoreSource = paths.directory.appendingPathComponent("restore.sqlite")
        let sourceQueue = try DatabaseQueue(path: restoreSource.path)
        try sourceQueue.write { db in
            try db.execute(sql: "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO users (name) VALUES ('Grace')")
        }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = restoreSource.path

        let plan = store.perform(
            .restoreDatabase,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertTrue(plan.message.contains("SQLite restore replaced"))
        let restoredQueue = try DatabaseQueue(path: paths.database.path)
        let names = try restoredQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM users ORDER BY id")
        }
        XCTAssertEqual(names, ["Grace"])
    }

    func test_sqliteRestoreBlocksSameSourceAndDestination() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = paths.database.path

        let plan = store.perform(
            .restoreDatabase,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertEqual(plan.message, "Restore input must be different from the destination database.")
    }

    func test_sqliteRestoreReportsInvalidSource() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let restoreSource = paths.directory.appendingPathComponent("not-sqlite.txt")
        try "not sqlite".write(to: restoreSource, atomically: true, encoding: .utf8)
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.inputPath = restoreSource.path

        let plan = store.perform(
            .restoreDatabase,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.message.contains("SQLite restore failed"), plan.message)
    }

    func test_sqliteDatabaseSearchFindsRowData() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.searchTerm = "Linus"

        let plan = store.perform(
            .databaseSearch,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertTrue(plan.message.contains("users.name 1 row"), plan.message)
    }

    func test_sqliteDatabaseSearchFindsMetadata() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.searchTerm = "users"

        let plan = store.perform(
            .databaseSearch,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertTrue(plan.message.contains("table users"), plan.message)
    }

    func test_sqliteDatabaseSearchReportsNoMatches() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.searchTerm = "not-present"

        let plan = store.perform(
            .databaseSearch,
            profile: paths.profile,
            activeSQL: "",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .localReady)
        XCTAssertEqual(plan.message, "SQLite search found no matches.")
    }

    func test_sqliteQueryExportBlocksWriteSQL() throws {
        let paths = try makeSQLiteFixture()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        let store = DatabaseWorkbenchOperationStore(defaults: defaults)
        store.outputPath = paths.directory.appendingPathComponent("blocked.csv").path

        let plan = store.perform(
            .exportQuery,
            profile: paths.profile,
            activeSQL: "DELETE FROM users",
            preferences: DatabaseWorkbenchPreferences(defaults: defaults)
        )

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertEqual(plan.message, "Only read-only SQLite queries can be exported locally.")
    }

    private func makeSQLiteFixture(includeRows: Bool = true) throws -> (directory: URL, database: URL, profile: DatabaseConnectionProfile) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-workbench-ops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("fixture.sqlite")
        let queue = try DatabaseQueue(path: database.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            if includeRows {
                try db.execute(sql: "INSERT INTO users (name) VALUES ('Ada'), ('Linus, Torvalds')")
            }
        }
        var profile = DatabaseConnectionProfile.draft(
            engine: DatabaseWorkbenchPreferences.supportedEngines.first { $0.id == "sqlite" }
        )
        profile.name = "Local SQLite"
        profile.hostOrPath = database.path
        return (directory, database, profile)
    }
}
