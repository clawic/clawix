import XCTest
@testable import Clawix

final class TerminalTabTests: XCTestCase {
    func testDerivedLabelUsesDirectoryBasename() {
        XCTAssertEqual(TerminalTab.deriveLabel(from: "/tmp/project"), "project")
    }

    func testDerivedLabelUsesHomeMarker() {
        XCTAssertEqual(TerminalTab.deriveLabel(from: NSHomeDirectory()), "~")
    }

    func testDerivedLabelUsesRootMarker() {
        XCTAssertEqual(TerminalTab.deriveLabel(from: "/"), "/")
    }
}
