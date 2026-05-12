import AppKit
import XCTest
@testable import Clawix

final class ScreenToolCrosshairModeTests: XCTestCase {
    func testCrosshairModeVisibility() {
        XCTAssertTrue(ScreenToolService.CrosshairMode.always.isVisible(modifierFlags: []))
        XCTAssertTrue(ScreenToolService.CrosshairMode.command.isVisible(modifierFlags: [.command]))
        XCTAssertFalse(ScreenToolService.CrosshairMode.command.isVisible(modifierFlags: []))
        XCTAssertFalse(ScreenToolService.CrosshairMode.disabled.isVisible(modifierFlags: [.command]))
    }

    func testCrosshairModeTitlesMatchSettingsOptions() {
        XCTAssertEqual(ScreenToolService.CrosshairMode.always.title, "Always enabled")
        XCTAssertEqual(ScreenToolService.CrosshairMode.command.title, "When Command is pressed")
        XCTAssertEqual(ScreenToolService.CrosshairMode.disabled.title, "Disabled")
    }
}
