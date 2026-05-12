import XCTest
@testable import Clawix

@MainActor
final class DatabaseWorkbenchSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DatabaseWorkbenchSessionTests"

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

    func test_classifyRecognizesAuditedStatementFamilies() {
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("select * from users"), .readOnly)
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("WITH rows AS (SELECT 1) SELECT * FROM rows"), .readOnly)
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("update users set name = 'A'"), .write)
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("drop table users"), .schema)
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("commit"), .transaction)
        XCTAssertEqual(DatabaseWorkbenchSessionStore.classify("   -- comment\n   "), .empty)
    }

    func test_formatSQLUppercasesCommonKeywordsAndBreaksClauses() {
        let formatted = DatabaseWorkbenchSessionStore.formatSQL("select * from users where id = 1 order by id limit 5")

        XCTAssertTrue(formatted.contains("SELECT *"))
        XCTAssertTrue(formatted.contains("\nFROM users"))
        XCTAssertTrue(formatted.contains("\nWHERE id = 1"))
        XCTAssertTrue(formatted.contains("\nORDER BY id"))
        XCTAssertTrue(formatted.contains("\nLIMIT 5"))
    }

    func test_networkRunPlanStaysExternalPending() {
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        let profile = DatabaseConnectionProfile.draft()

        let plan = DatabaseWorkbenchSessionStore.runPlan(
            sql: "select * from accounts",
            profile: profile,
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .externalPending)
        XCTAssertEqual(plan.statementKind, .readOnly)
        XCTAssertFalse(plan.requiresWriteConfirmation)
        XCTAssertTrue(plan.message.contains("EXTERNAL PENDING"))
    }

    func test_writeRunPlanTracksSafeModeConfirmation() {
        let prefs = DatabaseWorkbenchPreferences(defaults: defaults)
        prefs.safeMode = .confirmWrites
        let profile = DatabaseConnectionProfile.draft()

        let plan = DatabaseWorkbenchSessionStore.runPlan(
            sql: "delete from accounts",
            profile: profile,
            preferences: prefs
        )

        XCTAssertEqual(plan.status, .externalPending)
        XCTAssertEqual(plan.statementKind, .write)
        XCTAssertTrue(plan.requiresWriteConfirmation)
    }

    func test_storePersistsDraftsAndHistory() {
        let store = DatabaseWorkbenchSessionStore(defaults: defaults)
        store.activeSQL = "select 1"
        let draft = store.saveDraft(title: "Smoke query")
        _ = store.dryRun(profile: nil, preferences: DatabaseWorkbenchPreferences(defaults: defaults))

        let reloaded = DatabaseWorkbenchSessionStore(defaults: defaults)
        XCTAssertEqual(reloaded.drafts.first?.id, draft.id)
        XCTAssertEqual(reloaded.drafts.first?.title, "Smoke query")
        XCTAssertEqual(reloaded.history.first?.outcome, .blocked)
    }
}
