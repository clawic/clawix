import XCTest
import ClawixCore
@testable import Clawix

@MainActor
final class DaemonMessageReconciliationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func test_daemonUserEchoReplacesOptimisticMessage() {
        let state = AppState()
        let chatId = UUID()
        let local = ChatMessage(role: .user, content: "Hello", timestamp: Date())
        state.chats = [
            Chat(id: chatId, title: "Echo", messages: [local], createdAt: Date())
        ]
        state.trackOptimisticUserMessage(chatId: chatId, messageId: local.id)

        let remoteId = UUID()
        state.appendDaemonMessage(
            chatId: chatId.uuidString,
            message: WireMessage(
                id: remoteId.uuidString,
                role: .user,
                content: "Hello",
                streamingFinished: true,
                timestamp: Date()
            )
        )

        XCTAssertEqual(state.chats.first?.messages.count, 1)
        XCTAssertEqual(state.chats.first?.messages.first?.id, remoteId)
        XCTAssertEqual(state.chats.first?.messages.first?.content, "Hello")
    }

    func test_untrackedDaemonUserMessageStillAppends() {
        let state = AppState()
        let chatId = UUID()
        let existing = ChatMessage(role: .user, content: "All good", timestamp: Date())
        state.chats = [
            Chat(id: chatId, title: "Remote", messages: [existing], createdAt: Date())
        ]

        let remoteId = UUID()
        state.appendDaemonMessage(
            chatId: chatId.uuidString,
            message: WireMessage(
                id: remoteId.uuidString,
                role: .user,
                content: "All good",
                streamingFinished: true,
                timestamp: Date()
            )
        )

        XCTAssertEqual(state.chats.first?.messages.count, 2)
        XCTAssertEqual(state.chats.first?.messages.last?.id, remoteId)
    }

    func test_emptyDaemonSnapshotDoesNotWipeHydratedThreadMessages() {
        let state = AppState()
        let chatId = UUID()
        let existing = ChatMessage(role: .assistant, content: "Recovered history", timestamp: Date())
        state.chats = [
            Chat(
                id: chatId,
                title: "Historical",
                messages: [existing],
                createdAt: Date(),
                clawixThreadId: "thread-with-history",
                historyHydrated: true
            )
        ]

        state.applyDaemonMessages(chatId: chatId.uuidString, messages: [], hasMore: false)

        XCTAssertEqual(state.chats.first?.messages.map(\.content), ["Recovered history"])
        XCTAssertEqual(state.chats.first?.historyHydrated, true)
    }
}
