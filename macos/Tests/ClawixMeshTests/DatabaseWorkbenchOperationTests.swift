import XCTest
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
}
