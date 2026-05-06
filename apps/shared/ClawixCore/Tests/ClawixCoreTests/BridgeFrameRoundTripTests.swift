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
        try roundTrip(.auth(token: "deadbeef", deviceName: "iPhone Studio", clientKind: .ios))
        try roundTrip(.auth(token: "x", deviceName: nil, clientKind: nil))
        try roundTrip(.auth(token: "y", deviceName: "macOS GUI", clientKind: .desktop))
    }

    func testEditPrompt() throws {
        try roundTrip(.editPrompt(chatId: "uuid-1", messageId: "m2", text: "rewritten"))
    }

    func testArchiveChatToggles() throws {
        try roundTrip(.archiveChat(chatId: "uuid-1"))
        try roundTrip(.unarchiveChat(chatId: "uuid-1"))
        try roundTrip(.pinChat(chatId: "uuid-1"))
        try roundTrip(.unpinChat(chatId: "uuid-1"))
    }

    func testPairingHandshake() throws {
        try roundTrip(.pairingStart)
        try roundTrip(.pairingPayload(qrJson: "{\"v\":1}", bearer: "abc"))
    }

    func testProjectsSnapshot() throws {
        let project = WireProject(
            id: "proj-1",
            title: "monorepo",
            cwd: "/Users/me/code/monorepo",
            hasGitRepo: true,
            branch: "main",
            lastUsedAt: .init(timeIntervalSince1970: 1_700_002_000)
        )
        try roundTrip(.listProjects)
        try roundTrip(.projectsSnapshot(projects: [project]))
        try roundTrip(.projectsSnapshot(projects: []))
    }

    func testListChats() throws {
        try roundTrip(.listChats)
    }

    func testOpenChat() throws {
        try roundTrip(.openChat(chatId: "AB-123"))
    }

    func testSendPrompt() throws {
        try roundTrip(.sendPrompt(chatId: "AB-123", text: "hello world\nwith newline", attachments: []))
        try roundTrip(.sendPrompt(
            chatId: "AB-123",
            text: "look at this",
            attachments: [
                WireAttachment(
                    id: "img-1",
                    mimeType: "image/jpeg",
                    filename: "screen.jpg",
                    dataBase64: "ZmFrZQ=="
                )
            ]
        ))
    }

    func testNewChat() throws {
        try roundTrip(.newChat(chatId: "DE-456", text: "first message from the iPhone FAB", attachments: []))
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

    func testTranscribeAudio() throws {
        try roundTrip(.transcribeAudio(
            requestId: "req-1",
            audioBase64: "ZmFrZUF1ZGlv",
            mimeType: "audio/m4a",
            language: "en"
        ))
        try roundTrip(.transcribeAudio(
            requestId: "req-2",
            audioBase64: "AAAA",
            mimeType: "audio/wav",
            language: nil
        ))
    }

    func testTranscriptionResult() throws {
        try roundTrip(.transcriptionResult(
            requestId: "req-1",
            text: "hello world",
            errorMessage: nil
        ))
        try roundTrip(.transcriptionResult(
            requestId: "req-2",
            text: "",
            errorMessage: "no model downloaded"
        ))
    }

    func testWireFormatIsFlat() throws {
        let frame = BridgeFrame(.sendPrompt(chatId: "abc", text: "hello", attachments: []))
        let data = try BridgeCoder.encode(frame)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\":\(bridgeSchemaVersion)"))
        XCTAssertTrue(json.contains("\"type\":\"sendPrompt\""))
        XCTAssertTrue(json.contains("\"chatId\":\"abc\""))
        XCTAssertTrue(json.contains("\"text\":\"hello\""))
        XCTAssertFalse(json.contains("\"attachments\""))
        XCTAssertFalse(json.contains("\"payload\""))
    }

    func testLegacyPromptFramesDecodeWithoutAttachments() throws {
        let data = """
        {"schemaVersion":2,"type":"sendPrompt","chatId":"abc","text":"hello"}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(data)
        XCTAssertEqual(frame.body, .sendPrompt(chatId: "abc", text: "hello", attachments: []))
    }

    /// v1 frames (no `clientKind` on `auth`) decode cleanly into v2.
    /// Required so a v1 iPhone (in the wild between releases) can
    /// connect to a v2 server, and so v2 frames remain readable by
    /// the v1 round-trip path.
    func testV1AuthFrameDecodesUnderV2() throws {
        let v1Json = """
        {"schemaVersion":1,"type":"auth","token":"abc","deviceName":"iPhone"}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(v1Json)
        guard case .auth(let token, let device, let kind) = frame.body else {
            XCTFail("expected auth")
            return
        }
        XCTAssertEqual(token, "abc")
        XCTAssertEqual(device, "iPhone")
        XCTAssertNil(kind, "v1 auth omits clientKind, decodes as nil")
        XCTAssertEqual(frame.schemaVersion, 1)
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
