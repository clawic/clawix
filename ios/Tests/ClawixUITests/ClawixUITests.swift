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
}
