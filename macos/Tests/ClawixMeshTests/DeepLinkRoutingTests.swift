import XCTest
@testable import Clawix

final class DeepLinkRoutingTests: XCTestCase {
    func testParsesChatDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://chat/04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
        XCTAssertEqual(ClawixDeepLink.parse(url), .chat("04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
    }

    func testIgnoresOAuthCallbackURLs() throws {
        let url = try XCTUnwrap(URL(string: "clawix://oauth-callback/anthropic?code=abc"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }

    func testIgnoresNonClawixSchemes() throws {
        let url = try XCTUnwrap(URL(string: "https://chat/04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }
}
