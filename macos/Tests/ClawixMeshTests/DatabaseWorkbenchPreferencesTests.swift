import XCTest
@testable import Clawix

final class DatabaseWorkbenchPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DatabaseWorkbenchPreferencesTests"

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

    func test_defaultsMirrorAuditedWorkbenchBehavior() {
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)

        XCTAssertTrue(prefs.showItemList)
        XCTAssertTrue(prefs.showConsoleLog)
        XCTAssertTrue(prefs.showRowDetail)
        XCTAssertTrue(prefs.autoSaveQueries)
        XCTAssertTrue(prefs.uppercaseKeywords)
        XCTAssertTrue(prefs.insertClosingPairs)
        XCTAssertEqual(prefs.indentWidth, 4)
        XCTAssertEqual(prefs.completeKey, .enterOrTab)
        XCTAssertEqual(prefs.estimateCountThreshold, 500_000)
        XCTAssertEqual(prefs.csvDelimiter, .tab)
        XCTAssertEqual(prefs.csvLineBreak, .lf)
        XCTAssertEqual(prefs.defaultEncoding, .utf8mb4)
        XCTAssertEqual(prefs.queryTimeoutSeconds, 300)
        XCTAssertTrue(prefs.keepConnectionAlive)
        XCTAssertEqual(prefs.safeMode, .silent)
    }

    func test_changesPersistAcrossInstances() {
        var prefs: DatabaseWorkbenchPreferences? = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs?.showConsoleLog = false
        prefs?.safeMode = .confirmWrites
        prefs?.defaultEncoding = .latin1
        prefs?.queryTimeoutSeconds = 42
        prefs = nil

        let reloaded = DatabaseWorkbenchPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.showConsoleLog)
        XCTAssertEqual(reloaded.safeMode, .confirmWrites)
        XCTAssertEqual(reloaded.defaultEncoding, .latin1)
        XCTAssertEqual(reloaded.queryTimeoutSeconds, 42)
    }

    func test_supportedEnginesCoverAuditedConnectionTypes() {
        let labels = Set(DatabaseWorkbenchPreferences.supportedEngines.map(\.label))

        XCTAssertEqual(DatabaseWorkbenchPreferences.supportedEngines.count, 20)
        XCTAssertTrue(labels.contains("PostgreSQL"))
        XCTAssertTrue(labels.contains("Amazon Redshift"))
        XCTAssertTrue(labels.contains("MySQL"))
        XCTAssertTrue(labels.contains("MariaDB & SingleStore"))
        XCTAssertTrue(labels.contains("Microsoft SQL Server"))
        XCTAssertTrue(labels.contains("Cassandra"))
        XCTAssertTrue(labels.contains("ClickHouse"))
        XCTAssertTrue(labels.contains("BigQuery"))
        XCTAssertTrue(labels.contains("DynamoDB"))
        XCTAssertTrue(labels.contains("LibSQL"))
        XCTAssertTrue(labels.contains("Cloudflare D1"))
        XCTAssertTrue(labels.contains("Mongo"))
        XCTAssertTrue(labels.contains("Snowflake"))
        XCTAssertTrue(labels.contains("Redis"))
        XCTAssertTrue(labels.contains("SQLite"))
        XCTAssertTrue(labels.contains("DuckDB"))
        XCTAssertTrue(labels.contains("Oracle"))
        XCTAssertTrue(labels.contains("Cockroach"))
        XCTAssertTrue(labels.contains("Greenplum"))
        XCTAssertTrue(labels.contains("Vertica"))
    }

    func test_encodingMenuCoversAuditedEncodings() {
        let encodings = Set(DatabaseWorkbenchPreferences.TextEncoding.allCases.map(\.rawValue))

        XCTAssertEqual(encodings.count, 21)
        XCTAssertTrue(encodings.contains("utf8mb4"))
        XCTAssertTrue(encodings.contains("utf8"))
        XCTAssertTrue(encodings.contains("utf32"))
        XCTAssertTrue(encodings.contains("utf16le"))
        XCTAssertTrue(encodings.contains("utf16"))
        XCTAssertTrue(encodings.contains("ucs2"))
        XCTAssertTrue(encodings.contains("macroman"))
        XCTAssertTrue(encodings.contains("latin1"))
        XCTAssertTrue(encodings.contains("latin2"))
        XCTAssertTrue(encodings.contains("cp1250"))
        XCTAssertTrue(encodings.contains("latin5"))
        XCTAssertTrue(encodings.contains("hebrew"))
        XCTAssertTrue(encodings.contains("greek"))
        XCTAssertTrue(encodings.contains("cp1256"))
        XCTAssertTrue(encodings.contains("cp1257"))
        XCTAssertTrue(encodings.contains("cp1253"))
        XCTAssertTrue(encodings.contains("cp1251"))
        XCTAssertTrue(encodings.contains("ujis"))
        XCTAssertTrue(encodings.contains("sjis"))
        XCTAssertTrue(encodings.contains("euckr"))
        XCTAssertTrue(encodings.contains("big5"))
    }
}
