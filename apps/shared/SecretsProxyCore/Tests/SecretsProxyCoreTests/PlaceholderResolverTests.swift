import XCTest
@testable import SecretsProxyCore

final class PlaceholderResolverTests: XCTestCase {

    func testFindsBareName() {
        let tokens = PlaceholderResolver.tokens(in: "Bearer {{openai_main}}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.secretInternalName, "openai_main")
        XCTAssertNil(tokens.first?.fieldName)
        XCTAssertEqual(tokens.first?.raw, "{{openai_main}}")
    }

    func testFindsFieldAccess() {
        let tokens = PlaceholderResolver.tokens(in: "key={{aso_pb.private_key_p8}}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.secretInternalName, "aso_pb")
        XCTAssertEqual(tokens.first?.fieldName, "private_key_p8")
    }

    func testTolerantToWhitespace() {
        let tokens = PlaceholderResolver.tokens(in: "{{ openai_main . token }}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.secretInternalName, "openai_main")
        XCTAssertEqual(tokens.first?.fieldName, "token")
    }

    func testDeduplicatesByRaw() {
        let tokens = PlaceholderResolver.tokens(in: "{{a}} {{a}} {{a.b}} {{a.b}}")
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(Set(tokens.map { $0.raw }), ["{{a}}", "{{a.b}}"])
    }

    func testIgnoresMalformed() {
        let tokens = PlaceholderResolver.tokens(in: "{{}} {{ }} { {a} } {{a}")
        XCTAssertEqual(tokens.count, 0)
    }

    func testSubstituteReplacesAllOccurrences() {
        let result = PlaceholderResolver.substitute(
            "url=https://api.com?key={{openai_main}}&also={{openai_main}}",
            with: ["{{openai_main}}": "sk-deadbeef"]
        )
        XCTAssertEqual(result, "url=https://api.com?key=sk-deadbeef&also=sk-deadbeef")
    }

    func testCollectionScan() {
        let tokens = PlaceholderResolver.tokens(in: [
            "host=api.openai.com",
            "Authorization: Bearer {{openai_main}}",
            "X-Other: {{namecheap.api_key}}"
        ])
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(Set(tokens.map { $0.secretInternalName }), ["openai_main", "namecheap"])
    }
}
