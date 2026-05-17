import Foundation
import ClawixCore

@main
enum BridgeFixtureExporter {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: BridgeFixtureExporter <output-dir>\n", stderr)
            Foundation.exit(64)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for url in try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        where url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }

        for (index, fixture) in fixtures.enumerated() {
            let fileName = "\(String(format: "%03d", index + 1))-\(fixture.name).json"
            let data = try BridgeCoder.encode(fixture.frame)
            try data.write(to: output.appendingPathComponent(fileName), options: .atomic)
        }

        print("Wrote \(fixtures.count) bridge fixtures to \(output.path)")
    }

    private static var fixtures: [(name: String, frame: BridgeFrame)] {
        let attachment = WireAttachment(
            id: "att-image-1",
            mimeType: "image/png",
            filename: "screen.png",
            dataBase64: "ZmFrZUltYWdl"
        )
        let audioAttachment = WireAttachment(
            id: "att-audio-1",
            kind: .audio,
            mimeType: "audio/m4a",
            filename: "voice.m4a",
            dataBase64: "ZmFrZUF1ZGlv"
        )
        let session = WireSession(
            id: "session-1",
            title: "Fixture session",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: true,
            hasActiveTurn: true,
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_120),
            lastMessagePreview: "Done",
            branch: "main",
            cwd: "/tmp/clawix-fixture",
            threadId: "thread-1",
            agentId: "agent.default.codex"
        )
        let message = WireMessage(
            id: "message-1",
            role: .assistant,
            content: "Fixture response",
            reasoningText: "thinking",
            streamingFinished: true,
            timestamp: Date(timeIntervalSince1970: 1_700_000_030),
            timeline: [.tools(id: "tools-1", items: [
                WireWorkItem(id: "work-1", kind: "command", status: .completed, commandText: "pwd", commandActions: ["read"])
            ])],
            audioRef: WireAudioRef(id: "audio-1", mimeType: "audio/m4a", durationMs: 2_400)
        )
        let project = WireProject(
            id: "project-1",
            title: "Clawix",
            cwd: "/tmp/clawix-fixture",
            hasGitRepo: true,
            branch: "main",
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let rateLimit = WireRateLimitSnapshot(
            primary: WireRateLimitWindow(usedPercent: 14, resetsAt: 1_778_222_391, windowDurationMins: 300),
            secondary: nil,
            credits: WireCreditsSnapshot(hasCredits: true, unlimited: false, balance: "12.34"),
            limitId: "codex",
            limitName: nil
        )
        let audioAsset = sampleAudioAsset()
        let transcript = audioAsset.transcripts[0]

        return [
            ("auth", BridgeFrame(.auth(token: "token-abc", deviceName: "Windows", clientKind: .desktop, clientId: "client-win", installationId: "install-win", deviceId: "device-win"))),
            ("listSessions", BridgeFrame(.listSessions)),
            ("openSession", BridgeFrame(.openSession(sessionId: "session-1", limit: 60))),
            ("loadOlderMessages", BridgeFrame(.loadOlderMessages(sessionId: "session-1", beforeMessageId: "message-0", limit: 40))),
            ("sendMessage", BridgeFrame(.sendMessage(sessionId: "session-1", text: "hello", attachments: [attachment]))),
            ("newSession", BridgeFrame(.newSession(sessionId: "session-2", text: "start", attachments: [audioAttachment]))),
            ("interruptTurn", BridgeFrame(.interruptTurn(sessionId: "session-1"))),
            ("authOk", BridgeFrame(.authOk(hostDisplayName: "Fixture Mac"))),
            ("authFailed", BridgeFrame(.authFailed(reason: "bad-token"))),
            ("versionMismatch", BridgeFrame(.versionMismatch(serverVersion: 2))),
            ("sessionsSnapshot", BridgeFrame(.sessionsSnapshot(sessions: [session]))),
            ("sessionUpdated", BridgeFrame(.sessionUpdated(session: session))),
            ("messagesSnapshot", BridgeFrame(.messagesSnapshot(sessionId: "session-1", messages: [message], hasMore: false))),
            ("messagesPage", BridgeFrame(.messagesPage(sessionId: "session-1", messages: [message], hasMore: true))),
            ("messageAppended", BridgeFrame(.messageAppended(sessionId: "session-1", message: message))),
            ("messageStreaming", BridgeFrame(.messageStreaming(sessionId: "session-1", messageId: "message-1", content: "partial", reasoningText: "thinking", finished: false))),
            ("errorEvent", BridgeFrame(.errorEvent(code: "internal", message: "boom"))),
            ("editPrompt", BridgeFrame(.editPrompt(sessionId: "session-1", messageId: "message-0", text: "rewrite"))),
            ("archiveSession", BridgeFrame(.archiveSession(sessionId: "session-1"))),
            ("unarchiveSession", BridgeFrame(.unarchiveSession(sessionId: "session-1"))),
            ("pinSession", BridgeFrame(.pinSession(sessionId: "session-1"))),
            ("unpinSession", BridgeFrame(.unpinSession(sessionId: "session-1"))),
            ("renameSession", BridgeFrame(.renameSession(sessionId: "session-1", title: "Renamed"))),
            ("pairingStart", BridgeFrame(.pairingStart)),
            ("listProjects", BridgeFrame(.listProjects)),
            ("readFile", BridgeFrame(.readFile(path: "/tmp/clawix-fixture/README.md"))),
            ("pairingPayload", BridgeFrame(.pairingPayload(qrJson: #"{"v":1,"host":"127.0.0.1","port":24080,"token":"token-abc","shortCode":"ABC-234-XYZ","hostDisplayName":"Fixture Mac"}"#, token: "token-abc", shortCode: "ABC-234-XYZ"))),
            ("projectsSnapshot", BridgeFrame(.projectsSnapshot(projects: [project]))),
            ("fileSnapshot", BridgeFrame(.fileSnapshot(path: "/tmp/clawix-fixture/README.md", content: "# Fixture", isMarkdown: true, error: nil))),
            ("transcribeAudio", BridgeFrame(.transcribeAudio(requestId: "req-1", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", language: "en"))),
            ("transcriptionResult", BridgeFrame(.transcriptionResult(requestId: "req-1", text: "hello audio", errorMessage: nil))),
            ("requestAudio", BridgeFrame(.requestAudio(audioId: "audio-1"))),
            ("audioSnapshot", BridgeFrame(.audioSnapshot(audioId: "audio-1", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", errorMessage: nil))),
            ("requestGeneratedImage", BridgeFrame(.requestGeneratedImage(path: "/Users/me/.codex/generated_images/image.png"))),
            ("generatedImageSnapshot", BridgeFrame(.generatedImageSnapshot(path: "/Users/me/.codex/generated_images/image.png", dataBase64: "ZmFrZUltYWdl", mimeType: "image/png", errorMessage: nil))),
            ("bridgeState", BridgeFrame(.bridgeState(state: "ready", chatCount: 1, message: nil))),
            ("requestRateLimits", BridgeFrame(.requestRateLimits)),
            ("rateLimitsSnapshot", BridgeFrame(.rateLimitsSnapshot(snapshot: rateLimit, byLimitId: ["codex": rateLimit]))),
            ("rateLimitsUpdated", BridgeFrame(.rateLimitsUpdated(snapshot: rateLimit, byLimitId: [:]))),
            ("audioRegister", BridgeFrame(.audioRegister(requestId: "req-audio-1", request: WireAudioRegisterRequest(kind: .user_message, appId: "clawix", originActor: .user, mimeType: "audio/m4a", bytesBase64: "ZmFrZUF1ZGlv", durationMs: 2_400, deviceId: "device-win", sessionId: "session-1", threadId: "thread-1", linkedMessageId: "message-1", metadataJson: #"{"source":"fixture"}"#, transcript: WireAudioRegisterTranscript(text: "hello audio", role: .transcription, provider: "whisper", language: "en"))))),
            ("audioAttachTranscript", BridgeFrame(.audioAttachTranscript(requestId: "req-audio-2", audioId: "audio-1", transcript: WireAudioAttachTranscriptInput(text: "better transcript", role: .transcription, provider: "whisper-large", language: "en", markAsPrimary: true)))),
            ("audioGet", BridgeFrame(.audioGet(requestId: "req-audio-3", audioId: "audio-1", appId: "clawix"))),
            ("audioGetBytes", BridgeFrame(.audioGetBytes(requestId: "req-audio-4", audioId: "audio-1", appId: "clawix"))),
            ("audioList", BridgeFrame(.audioList(requestId: "req-audio-5", filter: WireAudioListFilter(appId: "clawix", kind: .user_message, originActor: .user, deviceId: "device-win", sessionId: "session-1", threadId: "thread-1", linkedMessageId: "message-1", fromCreatedAt: 1_750_000_000_000, toCreatedAt: 1_750_000_100_000, limit: 50, offset: 0)))),
            ("audioDelete", BridgeFrame(.audioDelete(requestId: "req-audio-6", audioId: "audio-1", appId: "clawix"))),
            ("audioRegisterResult", BridgeFrame(.audioRegisterResult(requestId: "req-audio-1", asset: audioAsset, errorMessage: nil))),
            ("audioAttachTranscriptResult", BridgeFrame(.audioAttachTranscriptResult(requestId: "req-audio-2", transcript: transcript, errorMessage: nil))),
            ("audioGetResult", BridgeFrame(.audioGetResult(requestId: "req-audio-3", asset: audioAsset, errorMessage: nil))),
            ("audioBytesResult", BridgeFrame(.audioBytesResult(requestId: "req-audio-4", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", durationMs: 2_400, errorMessage: nil))),
            ("audioListResult", BridgeFrame(.audioListResult(requestId: "req-audio-5", list: WireAudioListResult(items: [audioAsset], total: 1), errorMessage: nil))),
            ("audioDeleteResult", BridgeFrame(.audioDeleteResult(requestId: "req-audio-6", deleted: true, errorMessage: nil)))
        ]
    }

    private static func sampleAudioAsset() -> WireAudioAssetWithTranscripts {
        let asset = WireAudioAsset(
            id: "audio-1",
            kind: .user_message,
            appId: "clawix",
            originActor: .user,
            mimeType: "audio/m4a",
            bytesRelPath: "clawix/audio-1.m4a",
            durationMs: 2_400,
            createdAt: 1_750_000_000_000,
            deviceId: "device-win",
            sessionId: "session-1",
            threadId: "thread-1",
            linkedMessageId: "message-1",
            metadataJson: #"{"source":"fixture"}"#
        )
        let transcript = WireAudioTranscript(
            id: "transcript-1",
            audioId: "audio-1",
            role: .transcription,
            text: "hello audio",
            provider: "whisper",
            language: "en",
            createdAt: 1_750_000_001_000,
            isPrimary: true
        )
        return WireAudioAssetWithTranscripts(asset: asset, transcripts: [transcript])
    }
}
