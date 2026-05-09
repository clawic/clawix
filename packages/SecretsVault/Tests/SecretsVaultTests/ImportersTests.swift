import XCTest
import SecretsModels
@testable import SecretsVault

final class ImportersTests: XCTestCase {

    func testCSVParserHandlesQuotesAndCommas() {
        let text = "a,\"b,c\",\"d\"\"e\"\nx,y,z\n"
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows, [["a", "b,c", "d\"e"], ["x", "y", "z"]])
    }

    func testOnePasswordCSVMinimalFiveColumn() throws {
        let csv = """
        Title,URL,Username,Password,Notes
        Service,https://api.example.com,me@example.com,sk-deadbeef,api key for tests
        GitHub,https://github.com,alice,p@ss,
        """
        let preview = try OnePasswordCSVImporter.parse(csv)
        XCTAssertEqual(preview.drafts.count, 2)
        let service = preview.drafts[0]
        XCTAssertEqual(service.internalName, "service")
        XCTAssertEqual(service.title, "Service")
        XCTAssertEqual(service.kind, .passwordLogin)
        XCTAssertEqual(service.fields.count, 3)
        XCTAssertEqual(service.fields.first { $0.name == "password" }?.secretValue, "sk-deadbeef")
        XCTAssertEqual(service.notes, "api key for tests")
    }

    func testOnePasswordCSVRecognizesOTPColumn() throws {
        let csv = """
        Title,Username,Password,One-time password
        Cloud,user,pass,JBSWY3DPEHPK3PXP
        """
        let preview = try OnePasswordCSVImporter.parse(csv)
        let secret = try XCTUnwrap(preview.drafts.first)
        let otp = secret.fields.first { $0.name == "otp" }
        XCTAssertEqual(otp?.fieldKind, .otp)
        XCTAssertEqual(otp?.secretValue, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(otp?.otpDigits, 6)
    }

    func testBitwardenCSV() throws {
        let csv = """
        folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
        Work,0,login,GitHub,backup token,ghp_extra: ghp-extra-value,0,https://github.com,alice,super-secret,
        Personal,0,note,Wifi,SSID and password,,0,,,,
        """
        let preview = try BitwardenCSVImporter.parse(csv)
        XCTAssertEqual(preview.drafts.count, 2)
        let github = try XCTUnwrap(preview.drafts.first { $0.internalName == "github" })
        XCTAssertEqual(github.kind, .passwordLogin)
        XCTAssertEqual(github.fields.first { $0.name == "username" }?.publicValue, "alice")
        XCTAssertEqual(github.fields.first { $0.name == "password" }?.secretValue, "super-secret")
        XCTAssertEqual(github.fields.first { $0.name == "ghp_extra" }?.secretValue, "ghp-extra-value")
        XCTAssertEqual(github.tags, ["Work"])
        let note = try XCTUnwrap(preview.drafts.first { $0.internalName == "wifi" })
        XCTAssertEqual(note.kind, .secureNote)
        XCTAssertEqual(note.notes, "SSID and password")
    }

    func testEnvImporterTriagesByName() throws {
        let env = """
        # production
        export SERVICE_API_KEY="sk-deadbeef"
        DB_PASSWORD='hunter2'
        APP_NAME=Clawix
        EMPTY_LINE_BELOW=

        """
        let preview = try EnvFileImporter.parse(env)
        XCTAssertEqual(preview.drafts.count, 4)
        let service = try XCTUnwrap(preview.drafts.first { $0.internalName == "service_api_key" })
        XCTAssertEqual(service.kind, .apiKey)
        XCTAssertEqual(service.fields.first?.secretValue, "sk-deadbeef")
        XCTAssertEqual(service.fields.first?.placement, .env)
        let appName = try XCTUnwrap(preview.drafts.first { $0.internalName == "app_name" })
        XCTAssertEqual(appName.kind, .secureNote)
    }

    func testEnvImporterRejectsEmpty() {
        XCTAssertThrowsError(try EnvFileImporter.parse("# only comments\n\n"))
    }

    func testSlugCleansTitles() {
        XCTAssertEqual(OnePasswordCSVImporter.slug("Service · main"), "service_main")
        XCTAssertEqual(OnePasswordCSVImporter.slug("GitHub-Token (work)"), "github_token_work")
        XCTAssertTrue(OnePasswordCSVImporter.slug("").hasPrefix("imported_"))
    }
}
