import XCTest
@testable import ClawixCore

final class BridgeFrameRoundTripTests: XCTestCase {

    private func roundTrip(_ body: BridgeBody, file: StaticString = #file, line: UInt = #line) throws {
        let original = BridgeFrame(body)
        let data = try BridgeCoder.encode(original)
        let decoded = try BridgeCoder.decode(data)
        XCTAssertEqual(decoded.schemaVersion, bridgeSchemaVersion, file: file, line: line)
        XCTAssertEqual(decoded.body, body, file: file, line: line)
    }

    func testAuth() throws {
        try roundTrip(.auth(token: "deadbeef", deviceName: "iPhone Studio"))
        try roundTrip(.auth(token: "x", deviceName: nil))
    }

    func testListChats() throws {
        try roundTrip(.listChats)
    }

    func testOpenChat() throws {
        try roundTrip(.openChat(chatId: "AB-123"))
    }

    func testSendPrompt() throws {
        try roundTrip(.sendPrompt(chatId: "AB-123", text: "hello world\nwith newline"))
    }

    func testAuthOk() throws {
        try roundTrip(.authOk(macName: "studio Mac"))
        try roundTrip(.authOk(macName: nil))
    }

    func testAuthFailed() throws {
        try roundTrip(.authFailed(reason: "bad bearer"))
    }

    func testVersionMismatch() throws {
        try roundTrip(.versionMismatch(serverVersion: 7))
    }

    func testChatsSnapshot() throws {
        let chat = WireChat(
            id: "uuid-1",
            title: "First chat",
            createdAt: .init(timeIntervalSince1970: 1_700_000_000),
            isPinned: true,
            isArchived: false,
            hasActiveTurn: true,
            lastMessageAt: .init(timeIntervalSince1970: 1_700_001_000),
            lastMessagePreview: "Sure, done.",
            branch: "main",
            cwd: "/Users/me/proj"
        )
        try roundTrip(.chatsSnapshot(chats: [chat]))
        try roundTrip(.chatsSnapshot(chats: []))
    }

    func testChatUpdated() throws {
        let chat = WireChat(
            id: "uuid-2",
            title: "Renamed",
            createdAt: .init(timeIntervalSince1970: 1_700_000_000)
        )
        try roundTrip(.chatUpdated(chat: chat))
    }

    func testMessagesSnapshot() throws {
        let msgs = [
            WireMessage(id: "m1", role: .user, content: "hi", timestamp: .init(timeIntervalSince1970: 1_700_000_010)),
            WireMessage(
                id: "m2",
                role: .assistant,
                content: "hello",
                reasoningText: "thinking",
                streamingFinished: true,
                timestamp: .init(timeIntervalSince1970: 1_700_000_020)
            )
        ]
        try roundTrip(.messagesSnapshot(chatId: "uuid-1", messages: msgs))
    }

    func testMessageAppended() throws {
        let msg = WireMessage(id: "m3", role: .user, content: "new", timestamp: .init(timeIntervalSince1970: 1_700_000_030))
        try roundTrip(.messageAppended(chatId: "uuid-1", message: msg))
    }

    func testMessageStreaming() throws {
        try roundTrip(.messageStreaming(
            chatId: "uuid-1",
            messageId: "m4",
            content: "hello",
            reasoningText: "",
            finished: false
        ))
        try roundTrip(.messageStreaming(
            chatId: "uuid-1",
            messageId: "m4",
            content: "hello world",
            reasoningText: "thinking about it...",
            finished: false
        ))
        try roundTrip(.messageStreaming(
            chatId: "uuid-1",
            messageId: "m4",
            content: "hello world. done.",
            reasoningText: "thinking about it...",
            finished: true
        ))
    }

    func testErrorEvent() throws {
        try roundTrip(.errorEvent(code: "internal", message: "boom"))
    }

    func testWireFormatIsFlat() throws {
        let frame = BridgeFrame(.sendPrompt(chatId: "abc", text: "hello"))
        let data = try BridgeCoder.encode(frame)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\":1"))
        XCTAssertTrue(json.contains("\"type\":\"sendPrompt\""))
        XCTAssertTrue(json.contains("\"chatId\":\"abc\""))
        XCTAssertTrue(json.contains("\"text\":\"hello\""))
        XCTAssertFalse(json.contains("\"payload\""))
    }

    func testRejectsUnknownType() {
        let bogus = #"{"schemaVersion":1,"type":"madeUp"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try BridgeCoder.decode(bogus)) { err in
            guard case BridgeDecodingError.unknownType(let t) = err else {
                XCTFail("expected unknownType, got \(err)")
                return
            }
            XCTAssertEqual(t, "madeUp")
        }
    }
}
