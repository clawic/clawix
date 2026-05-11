import XCTest
@testable import Clawix

final class BrowserURLNormalizationTests: XCTestCase {
    @MainActor
    func testFileURLStaysFileURL() {
        let url = BrowserTabController.normalize("file:///tmp/clawix-fixture.html")

        XCTAssertEqual(url?.scheme, "file")
        XCTAssertEqual(url?.path, "/tmp/clawix-fixture.html")
        XCTAssertFalse(url?.absoluteString.hasPrefix("https://file") ?? true)
    }

    @MainActor
    func testAbsolutePathBecomesFileURL() {
        let url = BrowserTabController.normalize("/tmp/clawix-fixture.html")

        XCTAssertEqual(url?.scheme, "file")
        XCTAssertEqual(url?.path, "/tmp/clawix-fixture.html")
    }

    @MainActor
    func testHostWithoutSchemeDefaultsToHTTPS() {
        let url = BrowserTabController.normalize("example.com")

        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }
}
