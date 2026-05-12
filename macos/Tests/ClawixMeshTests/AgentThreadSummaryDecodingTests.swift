import XCTest
@testable import Clawix

final class AgentThreadSummaryDecodingTests: XCTestCase {
    func testDecodesCodexTitleFieldAsName() throws {
        let data = Data("""
        {
          "id": "thread-1",
          "cwd": "/tmp/project",
          "title": "Codex generated title",
          "preview": "First user message",
          "path": "/tmp/rollout.jsonl",
          "createdAt": 1710000000,
          "updatedAt": 1710000100,
          "archived": false
        }
        """.utf8)

        let thread = try JSONDecoder().decode(AgentThreadSummary.self, from: data)

        XCTAssertEqual(thread.name, "Codex generated title")
        XCTAssertEqual(thread.preview, "First user message")
    }

    func testNameWinsOverTitleField() throws {
        let data = Data("""
        {
          "id": "thread-1",
          "name": "Manual name",
          "title": "Codex generated title",
          "preview": "First user message",
          "createdAt": 1710000000,
          "updatedAt": 1710000100
        }
        """.utf8)

        let thread = try JSONDecoder().decode(AgentThreadSummary.self, from: data)

        XCTAssertEqual(thread.name, "Manual name")
    }
}
