import XCTest

final class ClawixUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeControlsAndAttachmentSheetStayUsable() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launchEnvironment["CLAWIX_MOCK"] = "1"
        app.launchEnvironment["CLAWIX_DISABLE_AUTOFOCUS"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["Clawix"].waitForExistence(timeout: 8))

        app.buttons["Search"].tap()
        XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 3))
        app.buttons["Close search"].tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        app.buttons["New chat"].tap()
        XCTAssertTrue(app.buttons["Attachments"].waitForExistence(timeout: 3))

        let attachmentButton = app.buttons.matching(identifier: "Attachments").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(attachmentButton)
        attachmentButton?.tap()
        XCTAssertFalse(app.alerts.element.waitForExistence(timeout: 1))
    }

    func testSnapshotCacheDoesNotBleedAcrossBridgeIdentities() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLAWIX_DISABLE_AUTOFOCUS"] = "1"
        app.launchEnvironment["CLAWIX_TEST_CREDENTIALS_HOST"] = "127.0.0.1"
        app.launchEnvironment["CLAWIX_TEST_CREDENTIALS_PORT"] = "9"
        app.launchEnvironment["CLAWIX_TEST_CREDENTIALS_MAC"] = "Real Mac"
        app.launchEnvironment["CLAWIX_TEST_SNAPSHOT_TITLE"] = "Leaked cached chat"
        app.launchEnvironment["CLAWIX_TEST_SNAPSHOT_CWD"] = "/tmp/leaked-cached-project"
        app.launchEnvironment["CLAWIX_TEST_SNAPSHOT_KEY"] = "Other Mac|127.0.0.1|9|"
        app.launch()

        XCTAssertTrue(app.staticTexts["Clawix"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Leaked cached chat"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.staticTexts["leaked-cached-project"].waitForExistence(timeout: 1))
    }

    func testArchiveFromChatMenuReturnsHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLAWIX_MOCK"] = "1"
        app.launchEnvironment["CLAWIX_DISABLE_AUTOFOCUS"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["Clawix"].waitForExistence(timeout: 8))
        app.buttons["New chat"].tap()
        XCTAssertTrue(app.buttons["Chat actions"].waitForExistence(timeout: 3))

        app.buttons["Chat actions"].tap()
        app.buttons["Archive"].tap()

        XCTAssertTrue(app.staticTexts["Clawix"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Chat actions"].waitForExistence(timeout: 1))
    }
}
