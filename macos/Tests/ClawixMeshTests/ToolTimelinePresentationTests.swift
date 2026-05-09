import XCTest
@testable import Clawix

final class ToolTimelinePresentationTests: XCTestCase {
    func testComputerUseMcpServerGetsCanonicalRow() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "computer-1",
                kind: .mcpTool(server: "computer_use", tool: "get_app_state"),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "mcp0",
                icon: "clawix.computerUse",
                text: L10n.usedTool("Computer Use")
            )
        ])
    }

    func testComputerUseNamespaceAliasGetsCanonicalName() {
        XCTAssertEqual(prettyMcpServer("mcp__computer_use__"), "Computer Use")
        XCTAssertTrue(isComputerUseMcpServer("computer-use@openai-bundled"))
    }
}
