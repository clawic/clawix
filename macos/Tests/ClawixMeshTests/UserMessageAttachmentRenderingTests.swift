import XCTest
import ClawixCore
@testable import Clawix

final class UserMessageAttachmentRenderingTests: XCTestCase {
    func testFilesMentionedWrapperRendersImagesAndCleanRequestText() {
        let first = "/tmp/screenshot-one.png"
        let second = "/tmp/screenshot-two.png"
        let raw = """
        # Files mentioned by the user:

        ## screenshot-one.png: \(first)

        ## screenshot-two.png: \(second)

        ## My request for Codex:
        Disable the workflow.

        Keep the repo quiet.
        """

        let parsed = UserBubbleContent.parse(raw)

        XCTAssertEqual(parsed.images.count, 2)
        XCTAssertEqual(parsed.files.count, 0)
        XCTAssertEqual(parsed.text, "Disable the workflow.\n\nKeep the repo quiet.")
        XCTAssertFalse(parsed.text.contains("Files mentioned by the user"))
        XCTAssertFalse(parsed.text.contains("My request for Codex"))
    }

    func testRolloutReaderUsesLocalImagesAndTaskDuration() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let imageURL = tmp.appendingPathComponent("mention.png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try png.write(to: imageURL)

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        let userText = """
        # Files mentioned by the user:

        ## mention.png: \(imageURL.path)

        ## My request for Codex:
        Disable the workflow.
        """
        let lines = [
            #"{"timestamp":"2026-05-09T10:52:25.716Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#,
            jsonLine(timestamp: "2026-05-09T10:52:25.723Z", type: "event_msg", payload: [
                "type": "user_message",
                "message": userText,
                "local_images": [imageURL.path]
            ]),
            jsonLine(timestamp: "2026-05-09T10:52:43.925Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Working on it.",
                "phase": "commentary"
            ]),
            jsonLine(timestamp: "2026-05-09T10:54:33.629Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Done.",
                "phase": "final_answer"
            ]),
            jsonLine(timestamp: "2026-05-09T10:54:33.659Z", type: "event_msg", payload: [
                "type": "task_complete",
                "duration_ms": 129_980
            ])
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let result = RolloutReader.readWithStatus(path: rollout, now: ISO8601DateFormatter().date(from: "2026-05-09T10:54:34Z")!)

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].attachments.count, 1)
        XCTAssertEqual(result.entries[0].attachments[0].filename, "mention.png")
        XCTAssertEqual(result.entries[1].workSummary?.elapsedSeconds(asOf: Date.distantFuture), 129)
    }

    private func jsonLine(timestamp: String, type: String, payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "timestamp": timestamp,
            "type": type,
            "payload": payload
        ], options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
