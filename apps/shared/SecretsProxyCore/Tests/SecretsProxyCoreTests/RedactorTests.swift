import XCTest
@testable import SecretsProxyCore

final class RedactorTests: XCTestCase {

    func testReplacesSingleSecret() {
        let entry = RedactionEntry(value: "sk-deadbeef", label: "[REDACTED:openai]")
        let redacted = Redactor.redact("Authorization: Bearer sk-deadbeef\n", with: [entry])
        XCTAssertEqual(redacted, "Authorization: Bearer [REDACTED:openai]\n")
    }

    func testLongerSecretsReplacedFirst() {
        // The longer value contains the shorter one as a substring. Without the
        // length-desc sort, the shorter replacement would mask the longer one
        // partially. With it, both are masked correctly.
        let entries = [
            RedactionEntry(value: "abc", label: "[REDACTED:short]"),
            RedactionEntry(value: "abcdef", label: "[REDACTED:long]")
        ]
        let redacted = Redactor.redact("xx abcdef yy abc zz", with: entries)
        XCTAssertEqual(redacted, "xx [REDACTED:long] yy [REDACTED:short] zz")
    }

    func testEmptyEntriesUnchanged() {
        XCTAssertEqual(Redactor.redact("hello", with: []), "hello")
        XCTAssertEqual(Redactor.redact("hello", with: [RedactionEntry(value: "", label: "[X]")]), "hello")
    }

    func testHandlesUTF8Data() {
        let entry = RedactionEntry(value: "secret🔐value", label: "[REDACTED:x]")
        let payload = Data("body=secret🔐value\n".utf8)
        let redacted = Redactor.redact(data: payload, with: [entry])
        XCTAssertEqual(String(data: redacted, encoding: .utf8), "body=[REDACTED:x]\n")
    }

    func testNonUtf8DataPassesThrough() {
        let bytes: [UInt8] = [0xFF, 0xFE, 0x00, 0x01]
        let original = Data(bytes)
        let redacted = Redactor.redact(data: original, with: [RedactionEntry(value: "x", label: "[X]")])
        XCTAssertEqual(redacted, original)
    }

    func testLabelHelper() {
        XCTAssertEqual(Redactor.label(forSecretInternalName: "openai_main"), "[REDACTED:openai_main]")
        XCTAssertEqual(Redactor.label(forSecretInternalName: "x", customLabel: "[GH_TOKEN]"), "[GH_TOKEN]")
        XCTAssertEqual(Redactor.label(forSecretInternalName: "x", customLabel: ""), "[REDACTED:x]")
    }
}
