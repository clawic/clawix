import XCTest
@testable import Clawix

@MainActor
final class DatabaseConnectionProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "DatabaseConnectionProfileStoreTests"

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

    func test_upsertPersistsConnectionMetadataWithoutSecrets() {
        let store = DatabaseConnectionProfileStore(defaults: defaults)
        var profile = DatabaseConnectionProfile.draft()
        profile.name = "Local app database"
        profile.hostOrPath = "127.0.0.1"
        profile.username = "app"
        profile.databaseName = "app_db"
        profile.authStorage = .secretVault
        profile.bootstrapSQL = "select 1;"

        store.upsert(profile)

        let reloaded = DatabaseConnectionProfileStore(defaults: defaults)
        XCTAssertEqual(reloaded.profiles.count, 1)
        XCTAssertEqual(reloaded.profiles[0].name, "Local app database")
        XCTAssertEqual(reloaded.profiles[0].authStorage, .secretVault)
        XCTAssertEqual(reloaded.profiles[0].bootstrapSQL, "select 1;")
    }

    func test_networkProfileDryRunDoesNotOpenNetworkSession() {
        var profile = DatabaseConnectionProfile.draft()
        profile.name = "Local PostgreSQL"
        profile.hostOrPath = "127.0.0.1"
        profile.port = 5432

        let result = DatabaseConnectionProfileStore.dryRun(profile)

        XCTAssertEqual(result.status, .externalPending)
        XCTAssertTrue(result.message.contains("explicit approval"))
    }

    func test_fileProfileDryRunChecksLocalFileExistence() throws {
        let sqlite = try XCTUnwrap(DatabaseWorkbenchPreferences.supportedEngines.first { $0.id == "sqlite" })
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-db-profile-\(UUID().uuidString).\(ClawixPersistentSurfacePaths.components.sqliteExtension)")
        FileManager.default.createFile(atPath: temp.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: temp) }

        var profile = DatabaseConnectionProfile.draft(engine: sqlite)
        profile.name = "Local SQLite"
        profile.hostOrPath = temp.path

        let result = DatabaseConnectionProfileStore.dryRun(profile)

        XCTAssertEqual(result.status, .passed)
    }

    func test_validationRejectsIncompleteProfiles() {
        var profile = DatabaseConnectionProfile.draft()
        profile.name = ""
        profile.hostOrPath = ""
        profile.port = 70_000

        let errors = DatabaseConnectionProfileStore.validationErrors(for: profile)

        XCTAssertTrue(errors.contains("Name is required."))
        XCTAssertTrue(errors.contains("Host is required."))
        XCTAssertTrue(errors.contains("Port must be between 1 and 65535."))
    }
}
