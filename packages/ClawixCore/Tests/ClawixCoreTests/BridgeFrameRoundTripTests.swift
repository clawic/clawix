import XCTest
@testable import ClawixCore

final class BridgeFrameRoundTripTests: XCTestCase {

    private func roundTrip(_ body: BridgeBody, file: StaticString = #file, line: UInt = #line) throws {
        let original = BridgeFrame(body)
        let data = try BridgeCoder.encode(original)
        let decoded = try BridgeCoder.decode(data)
        XCTAssertEqual(decoded.protocolVersion, bridgeProtocolVersion, file: file, line: line)
        XCTAssertEqual(decoded.body, body, file: file, line: line)
    }

    func testAuth() throws {
        try roundTrip(.auth(token: "deadbeef", deviceName: "iPhone Studio", clientKind: .companion, clientId: "client-1", installationId: "install-1", deviceId: "device-1"))
        try roundTrip(.auth(token: "x", deviceName: nil, clientKind: nil, clientId: nil, installationId: nil, deviceId: nil))
        try roundTrip(.auth(token: "y", deviceName: "macOS GUI", clientKind: .desktop, clientId: nil, installationId: nil, deviceId: nil))
    }

    func testEditPrompt() throws {
        try roundTrip(.editPrompt(sessionId: "uuid-1", messageId: "m2", text: "rewritten"))
    }

    func testArchiveSessionToggles() throws {
        try roundTrip(.archiveSession(sessionId: "uuid-1"))
        try roundTrip(.unarchiveSession(sessionId: "uuid-1"))
        try roundTrip(.pinSession(sessionId: "uuid-1"))
        try roundTrip(.unpinSession(sessionId: "uuid-1"))
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

    func testListSessions() throws {
        try roundTrip(.listSessions)
    }

    func testOpenSession() throws {
        try roundTrip(.openSession(sessionId: "AB-123", limit: nil))
        try roundTrip(.openSession(sessionId: "AB-123", limit: 60))
    }

    func testLoadOlderMessages() throws {
        try roundTrip(.loadOlderMessages(
            sessionId: "AB-123",
            beforeMessageId: "msg-oldest-known",
            limit: 40
        ))
    }

    func testSendMessage() throws {
        try roundTrip(.sendMessage(sessionId: "AB-123", text: "hello world\nwith newline", attachments: []))
        try roundTrip(.sendMessage(
            sessionId: "AB-123",
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

    func testNewSession() throws {
        try roundTrip(.newSession(sessionId: "DE-456", text: "first message from the iPhone FAB", attachments: []))
    }

    func testAuthOk() throws {
        try roundTrip(.authOk(hostDisplayName: "studio Mac"))
        try roundTrip(.authOk(hostDisplayName: nil))
    }

    func testAuthFailed() throws {
        try roundTrip(.authFailed(reason: "bad bearer"))
    }

    func testVersionMismatch() throws {
        try roundTrip(.versionMismatch(serverVersion: 7))
    }

    func testSessionsSnapshot() throws {
        let chat = WireSession(
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
        try roundTrip(.sessionsSnapshot(sessions: [chat]))
        try roundTrip(.sessionsSnapshot(sessions: []))
    }

    func testSessionUpdated() throws {
        let chat = WireSession(
            id: "uuid-2",
            title: "Renamed",
            createdAt: .init(timeIntervalSince1970: 1_700_000_000)
        )
        try roundTrip(.sessionUpdated(session: chat))
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
        try roundTrip(.messagesSnapshot(sessionId: "uuid-1", messages: msgs, hasMore: nil))
        try roundTrip(.messagesSnapshot(sessionId: "uuid-1", messages: msgs, hasMore: true))
        try roundTrip(.messagesSnapshot(sessionId: "uuid-1", messages: msgs, hasMore: false))
    }

    func testMessagesPage() throws {
        let msgs = [
            WireMessage(id: "old-1", role: .user, content: "older", timestamp: .init(timeIntervalSince1970: 1_700_000_005)),
            WireMessage(id: "old-2", role: .assistant, content: "older reply", streamingFinished: true, timestamp: .init(timeIntervalSince1970: 1_700_000_006))
        ]
        try roundTrip(.messagesPage(sessionId: "uuid-1", messages: msgs, hasMore: true))
        try roundTrip(.messagesPage(sessionId: "uuid-1", messages: [], hasMore: false))
    }

    /// Old peers (clients without paginated `openSession`) MUST keep
    /// decoding cleanly under the current schema: `limit` is missing,
    /// the field defaults to nil, and the server treats it as "send
    /// the whole transcript". Same story for `messagesSnapshot`
    /// missing `hasMore` — decodes as nil, the iPhone treats it as
    /// "no scroll-up available".
    func testOpenSessionDecodesWithoutLimit() throws {
        let data = """
        {"protocolVersion":\(bridgeProtocolVersion),"type":"openSession","sessionId":"abc"}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(data)
        XCTAssertEqual(frame.body, .openSession(sessionId: "abc", limit: nil))
    }

    func testLegacyMessagesSnapshotDecodesWithoutHasMore() throws {
        let data = """
        {"protocolVersion":\(bridgeProtocolVersion),"type":"messagesSnapshot","sessionId":"abc","messages":[]}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(data)
        XCTAssertEqual(frame.body, .messagesSnapshot(sessionId: "abc", messages: [], hasMore: nil))
    }

    func testMessageAppended() throws {
        let msg = WireMessage(id: "m3", role: .user, content: "new", timestamp: .init(timeIntervalSince1970: 1_700_000_030))
        try roundTrip(.messageAppended(sessionId: "uuid-1", message: msg))
    }

    func testMessageStreaming() throws {
        try roundTrip(.messageStreaming(
            sessionId: "uuid-1",
            messageId: "m4",
            content: "hello",
            reasoningText: "",
            finished: false
        ))
        try roundTrip(.messageStreaming(
            sessionId: "uuid-1",
            messageId: "m4",
            content: "hello world",
            reasoningText: "thinking about it...",
            finished: false
        ))
        try roundTrip(.messageStreaming(
            sessionId: "uuid-1",
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

    func testRequestAudio() throws {
        try roundTrip(.requestAudio(audioId: "audio-abc"))
    }

    func testAudioSnapshot() throws {
        try roundTrip(.audioSnapshot(
            audioId: "audio-abc",
            audioBase64: "ZmFrZUF1ZGlv",
            mimeType: "audio/m4a",
            errorMessage: nil
        ))
        try roundTrip(.audioSnapshot(
            audioId: "audio-missing",
            audioBase64: nil,
            mimeType: nil,
            errorMessage: "Audio no longer available"
        ))
    }

    func testSendMessageCarriesAudioAttachment() throws {
        let audio = WireAttachment(
            id: "att-1",
            kind: .audio,
            mimeType: "audio/m4a",
            filename: "voice.m4a",
            dataBase64: "AAAAAA=="
        )
        try roundTrip(.sendMessage(sessionId: "uuid-1", text: "hello", attachments: [audio]))
    }

    func testWireMessageCarriesAudioRef() throws {
        let msg = WireMessage(
            id: "m-voice",
            role: .user,
            content: "hello transcript",
            timestamp: .init(timeIntervalSince1970: 1_700_000_400),
            audioRef: WireAudioRef(id: "audio-abc", mimeType: "audio/m4a", durationMs: 3200)
        )
        try roundTrip(.messageAppended(sessionId: "uuid-1", message: msg))
    }

    /// Old peers without `kind` should decode as image attachments so
    /// existing v2 senders keep working when v3 daemons receive them.
    func testWireAttachmentLegacyDecodeDefaultsToImage() throws {
        let legacy = """
        {"id":"att-1","mimeType":"image/jpeg","filename":"photo.jpg","dataBase64":"AAAA"}
        """
        let attachment = try BridgeCoder.decoder.decode(
            WireAttachment.self,
            from: Data(legacy.utf8)
        )
        XCTAssertEqual(attachment.kind, .image)
    }

    func testWireFormatIsFlat() throws {
        let frame = BridgeFrame(.sendMessage(sessionId: "abc", text: "hello", attachments: []))
        let data = try BridgeCoder.encode(frame)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"protocolVersion\":\(bridgeProtocolVersion)"))
        XCTAssertTrue(json.contains("\"type\":\"sendMessage\""))
        XCTAssertTrue(json.contains("\"sessionId\":\"abc\""))
        XCTAssertTrue(json.contains("\"text\":\"hello\""))
        XCTAssertFalse(json.contains("\"attachments\""))
        XCTAssertFalse(json.contains("\"payload\""))
    }

    func testLegacyPromptFramesDecodeWithoutAttachments() throws {
        let data = """
        {"protocolVersion":8,"type":"sendMessage","sessionId":"abc","text":"hello"}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(data)
        XCTAssertEqual(frame.body, .sendMessage(sessionId: "abc", text: "hello", attachments: []))
    }

    func testAuthFrameDecodesWithoutOptionalClientFields() throws {
        let currentJson = """
        {"protocolVersion":8,"type":"auth","token":"abc","deviceName":"iPhone"}
        """.data(using: .utf8)!
        let frame = try BridgeCoder.decode(currentJson)
        guard case .auth(let token, let device, let kind, let clientId, let installationId, let deviceId) = frame.body else {
            XCTFail("expected auth")
            return
        }
        XCTAssertEqual(token, "abc")
        XCTAssertEqual(device, "iPhone")
        XCTAssertNil(kind, "current auth omits clientKind, decodes as nil")
        XCTAssertNil(clientId)
        XCTAssertNil(installationId)
        XCTAssertNil(deviceId)
        XCTAssertEqual(frame.protocolVersion, bridgeProtocolVersion)
    }

    func testRejectsUnknownType() {
        let bogus = #"{"protocolVersion":8,"type":"madeUp"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try BridgeCoder.decode(bogus)) { err in
            guard case BridgeDecodingError.unknownType(let t) = err else {
                XCTFail("expected unknownType, got \(err)")
                return
            }
            XCTAssertEqual(t, "madeUp")
        }
    }

    // MARK: - Rate limits (v5)

    func testRequestRateLimitsRoundTrip() throws {
        try roundTrip(.requestRateLimits)
    }

    func testRateLimitsSnapshotRoundTrip() throws {
        let primary = WireRateLimitWindow(usedPercent: 14, resetsAt: 1_778_222_391, windowDurationMins: 300)
        let secondary = WireRateLimitWindow(usedPercent: 14, resetsAt: 1_778_539_180, windowDurationMins: 10_080)
        let credits = WireCreditsSnapshot(hasCredits: false, unlimited: false, balance: "0")
        let general = WireRateLimitSnapshot(
            primary: primary,
            secondary: secondary,
            credits: credits,
            limitId: "codex",
            limitName: nil
        )
        let model = WireRateLimitSnapshot(
            primary: WireRateLimitWindow(usedPercent: 0, resetsAt: 1_778_227_957, windowDurationMins: 300),
            secondary: WireRateLimitWindow(usedPercent: 0, resetsAt: 1_778_814_757, windowDurationMins: 10_080),
            credits: nil,
            limitId: "codex_bengalfox",
            limitName: "GPT-5.3-Codex-Spark"
        )
        try roundTrip(.rateLimitsSnapshot(snapshot: general, byLimitId: ["codex": general, "codex_bengalfox": model]))
        // Empty / not-yet-fetched payload also survives the round trip.
        try roundTrip(.rateLimitsSnapshot(snapshot: nil, byLimitId: [:]))
    }

    func testRateLimitsUpdatedRoundTrip() throws {
        let snap = WireRateLimitSnapshot(
            primary: WireRateLimitWindow(usedPercent: 67, resetsAt: 1_780_000_000, windowDurationMins: 300),
            secondary: nil,
            credits: WireCreditsSnapshot(hasCredits: true, unlimited: false, balance: "12.34"),
            limitId: "codex",
            limitName: nil
        )
        try roundTrip(.rateLimitsUpdated(snapshot: snap, byLimitId: [:]))
    }

    // MARK: - v7 audio catalog

    private func sampleAudioAssetWithTranscripts() -> WireAudioAssetWithTranscripts {
        let asset = WireAudioAsset(
            id: "audio-1",
            kind: .user_message,
            appId: "clawix",
            originActor: .user,
            mimeType: "audio/mp4",
            bytesRelPath: "clawix/audio-1.m4a",
            durationMs: 2_400,
            createdAt: 1_750_000_000_000,
            deviceId: "dev-A",
            sessionId: "sess-1",
            threadId: "thread-1",
            linkedMessageId: "msg-1",
            metadataJson: nil
        )
        let transcript = WireAudioTranscript(
            id: "t-1",
            audioId: "audio-1",
            role: .transcription,
            text: "hello audio",
            provider: "whisper",
            language: "en",
            createdAt: 1_750_000_000_000,
            isPrimary: true
        )
        return WireAudioAssetWithTranscripts(asset: asset, transcripts: [transcript])
    }

    func testAudioRegisterRoundTrip() throws {
        try roundTrip(.audioRegister(
            requestId: "req-1",
            request: WireAudioRegisterRequest(
                id: nil,
                kind: .user_message,
                appId: "clawix",
                originActor: .user,
                mimeType: "audio/mp4",
                bytesBase64: "ZmFrZQ==",
                durationMs: 2_400,
                deviceId: "dev-A",
                sessionId: "sess-1",
                threadId: "thread-1",
                linkedMessageId: "msg-1",
                metadataJson: nil,
                transcript: WireAudioRegisterTranscript(text: "hello", role: .transcription, provider: "whisper", language: "en")
            )
        ))
    }

    func testAudioRegisterResultRoundTrip() throws {
        try roundTrip(.audioRegisterResult(
            requestId: "req-1",
            asset: sampleAudioAssetWithTranscripts(),
            errorMessage: nil
        ))
        try roundTrip(.audioRegisterResult(requestId: "req-2", asset: nil, errorMessage: "blob too large"))
    }

    func testAudioAttachTranscriptRoundTrip() throws {
        try roundTrip(.audioAttachTranscript(
            requestId: "req-1",
            audioId: "audio-1",
            transcript: WireAudioAttachTranscriptInput(
                text: "v2 better",
                role: .transcription,
                provider: "whisper-large",
                language: "en",
                markAsPrimary: true
            )
        ))
    }

    func testAudioAttachTranscriptResultRoundTrip() throws {
        let transcript = WireAudioTranscript(
            id: "t-2",
            audioId: "audio-1",
            role: .transcription,
            text: "v2",
            provider: "whisper-large",
            language: "en",
            createdAt: 1_750_000_001_000,
            isPrimary: true
        )
        try roundTrip(.audioAttachTranscriptResult(requestId: "req-1", transcript: transcript, errorMessage: nil))
        try roundTrip(.audioAttachTranscriptResult(requestId: "req-2", transcript: nil, errorMessage: "audio not found"))
    }

    func testAudioGetRoundTrip() throws {
        try roundTrip(.audioGet(requestId: "req-1", audioId: "audio-1", appId: "clawix"))
    }

    func testAudioGetResultRoundTrip() throws {
        try roundTrip(.audioGetResult(requestId: "req-1", asset: sampleAudioAssetWithTranscripts(), errorMessage: nil))
        try roundTrip(.audioGetResult(requestId: "req-2", asset: nil, errorMessage: "not found"))
    }

    func testAudioGetBytesRoundTrip() throws {
        try roundTrip(.audioGetBytes(requestId: "req-1", audioId: "audio-1", appId: "clawix"))
    }

    func testAudioBytesResultRoundTrip() throws {
        try roundTrip(.audioBytesResult(
            requestId: "req-1",
            audioBase64: "ZmFrZQ==",
            mimeType: "audio/mp4",
            durationMs: 2_400,
            errorMessage: nil
        ))
        try roundTrip(.audioBytesResult(requestId: "req-2", audioBase64: nil, mimeType: nil, durationMs: nil, errorMessage: "missing blob"))
    }

    func testAudioListRoundTrip() throws {
        let filter = WireAudioListFilter(
            appId: "clawix",
            kind: .user_message,
            originActor: nil,
            deviceId: nil,
            sessionId: nil,
            threadId: "thread-1",
            linkedMessageId: nil,
            fromCreatedAt: nil,
            toCreatedAt: nil,
            limit: 50,
            offset: 0
        )
        try roundTrip(.audioList(requestId: "req-1", filter: filter))
    }

    func testAudioListResultRoundTrip() throws {
        let result = WireAudioListResult(items: [sampleAudioAssetWithTranscripts()], total: 1)
        try roundTrip(.audioListResult(requestId: "req-1", list: result, errorMessage: nil))
        try roundTrip(.audioListResult(requestId: "req-2", list: nil, errorMessage: "filter rejected"))
    }

    func testAudioDeleteRoundTrip() throws {
        try roundTrip(.audioDelete(requestId: "req-1", audioId: "audio-1", appId: "clawix"))
    }

    func testAudioDeleteResultRoundTrip() throws {
        try roundTrip(.audioDeleteResult(requestId: "req-1", deleted: true, errorMessage: nil))
        try roundTrip(.audioDeleteResult(requestId: "req-2", deleted: false, errorMessage: "no row"))
    }
}
