import Foundation
import ClawixCore

@MainActor
public enum BridgeIntent {

    /// Routes an authenticated inbound frame to the right `EngineHost`
    /// or `BridgeBus` operation. Frames that are server-only or that
    /// have no authenticated meaning are ignored.
    public static func dispatch(
        body: BridgeBody,
        host: EngineHost?,
        bus: BridgeBus,
        session: BridgeSession
    ) {
        switch body {
        case .listSessions:
            session.send(BridgeFrame(.sessionsSnapshot(sessions: bus.currentSessions())))

        case .openSession(let sessionIdString, let limit):
            guard let uuid = UUID(uuidString: sessionIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            // Mirror what selecting a chat in the Mac UI does: pull
            // the rollout file off disk so `chat.messages` is populated
            // before we hand it to the bridge subscriber. Without this
            // every `notLoaded` thread shows up empty on the iPhone.
            host?.handleHydrateHistory(sessionId: uuid)
            let page = bus.subscribe(sessionId: sessionIdString, limit: limit)
            // `hasMore: nil` for legacy callers (no `limit`) so iOS
            // clients on the old code path behave identically.
            session.send(BridgeFrame(.messagesSnapshot(
                sessionId: sessionIdString,
                messages: page.messages,
                hasMore: limit == nil ? nil : page.hasMore
            )))

        case .loadOlderMessages(let sessionIdString, let before, let limit):
            guard UUID(uuidString: sessionIdString) != nil else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            let page = bus.page(sessionId: sessionIdString, before: before, limit: limit)
            session.send(BridgeFrame(.messagesPage(
                sessionId: sessionIdString,
                messages: page.messages,
                hasMore: page.hasMore
            )))

        case .sendMessage(let sessionIdString, let text, let attachments):
            guard let uuid = UUID(uuidString: sessionIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            host?.handleSendMessage(sessionId: uuid, text: text, attachments: attachments)

        case .newSession(let sessionIdString, let text, let attachments):
            guard let uuid = UUID(uuidString: sessionIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            // Auto-subscribe so the bus pushes message-level deltas for
            // the freshly created chat without an extra `openSession` round
            // trip from the client.
            _ = bus.subscribe(sessionId: sessionIdString)
            host?.handleNewSession(sessionId: uuid, text: text, attachments: attachments)

        case .interruptTurn(let sessionIdString):
            guard let uuid = UUID(uuidString: sessionIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            host?.handleInterruptTurn(sessionId: uuid)

        case .editPrompt(let sessionIdString, let messageIdString, let text):
            guard let chatUuid = UUID(uuidString: sessionIdString),
                  let msgUuid = UUID(uuidString: messageIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badId", message: sessionIdString)))
                return
            }
            host?.handleEditPrompt(sessionId: chatUuid, messageId: msgUuid, text: text)

        case .archiveSession(let sessionIdString):
            guard let uuid = UUID(uuidString: sessionIdString) else { return }
            host?.handleArchiveSession(sessionId: uuid, archived: true)
        case .unarchiveSession(let sessionIdString):
            guard let uuid = UUID(uuidString: sessionIdString) else { return }
            host?.handleArchiveSession(sessionId: uuid, archived: false)
        case .pinSession(let sessionIdString):
            guard let uuid = UUID(uuidString: sessionIdString) else { return }
            host?.handlePinSession(sessionId: uuid, pinned: true)
        case .unpinSession(let sessionIdString):
            guard let uuid = UUID(uuidString: sessionIdString) else { return }
            host?.handlePinSession(sessionId: uuid, pinned: false)

        case .renameSession(let sessionIdString, let title):
            guard let uuid = UUID(uuidString: sessionIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badSessionId", message: sessionIdString)))
                return
            }
            host?.handleRenameSession(sessionId: uuid, title: title)

        case .pairingStart:
            if let payload = host?.handlePairingStart() {
                session.send(BridgeFrame(.pairingPayload(qrJson: payload.qrJson, bearer: payload.bearer)))
            } else {
                session.send(BridgeFrame(.errorEvent(
                    code: "notImplemented",
                    message: "host does not mint pairing tokens"
                )))
            }

        case .listProjects:
            let projects = host?.currentProjects() ?? []
            session.send(BridgeFrame(.projectsSnapshot(projects: projects)))

        case .readFile(let path):
            session.send(BridgeFrame(BridgeFileReader.read(path: path)))

        case .transcribeAudio(let requestId, let audioBase64, let mimeType, let language):
            host?.handleTranscribeAudio(
                requestId: requestId,
                audioBase64: audioBase64,
                mimeType: mimeType,
                language: language,
                reply: { [weak session] text, errorMessage in
                    session?.send(BridgeFrame(.transcriptionResult(
                        requestId: requestId,
                        text: text,
                        errorMessage: errorMessage
                    )))
                }
            )

        case .requestAudio(let audioId):
            host?.handleRequestAudio(
                audioId: audioId,
                reply: { [weak session] audioBase64, mimeType, errorMessage in
                    session?.send(BridgeFrame(.audioSnapshot(
                        audioId: audioId,
                        audioBase64: audioBase64,
                        mimeType: mimeType,
                        errorMessage: errorMessage
                    )))
                }
            )

        case .requestGeneratedImage(let path):
            host?.handleRequestGeneratedImage(
                path: path,
                reply: { [weak session] dataBase64, mimeType, errorMessage in
                    session?.send(BridgeFrame(.generatedImageSnapshot(
                        path: path,
                        dataBase64: dataBase64,
                        mimeType: mimeType,
                        errorMessage: errorMessage
                    )))
                }
            )

        case .requestRateLimits:
            // The bus caches the daemon's most recent snapshot so the
            // reply is synchronous; subsequent pushes flow through
            // `rateLimitsUpdated` automatically.
            session.send(bus.currentRateLimitsFrame())

        // v7 audio catalog. Routes through the host's `audioCatalogClient`
        // when configured; otherwise the default impl replies with a
        // structured error so clients surface a precise reason instead
        // of hanging on a missing response.
        case .audioRegister(let requestId, let request):
            host?.handleAudioRegister(
                requestId: requestId,
                request: request,
                reply: { [weak session] asset, errorMessage in
                    session?.send(BridgeFrame(.audioRegisterResult(
                        requestId: requestId,
                        asset: asset,
                        errorMessage: errorMessage
                    )))
                }
            )
        case .audioAttachTranscript(let requestId, let audioId, let input):
            host?.handleAudioAttachTranscript(
                requestId: requestId,
                audioId: audioId,
                input: input,
                reply: { [weak session] transcript, errorMessage in
                    session?.send(BridgeFrame(.audioAttachTranscriptResult(
                        requestId: requestId,
                        transcript: transcript,
                        errorMessage: errorMessage
                    )))
                }
            )
        case .audioGet(let requestId, let audioId, let appId):
            host?.handleAudioGet(
                requestId: requestId,
                audioId: audioId,
                appId: appId,
                reply: { [weak session] asset, errorMessage in
                    session?.send(BridgeFrame(.audioGetResult(
                        requestId: requestId,
                        asset: asset,
                        errorMessage: errorMessage
                    )))
                }
            )
        case .audioGetBytes(let requestId, let audioId, let appId):
            host?.handleAudioGetBytes(
                requestId: requestId,
                audioId: audioId,
                appId: appId,
                reply: { [weak session] audioBase64, mimeType, durationMs, errorMessage in
                    session?.send(BridgeFrame(.audioBytesResult(
                        requestId: requestId,
                        audioBase64: audioBase64,
                        mimeType: mimeType,
                        durationMs: durationMs,
                        errorMessage: errorMessage
                    )))
                }
            )
        case .audioList(let requestId, let filter):
            host?.handleAudioList(
                requestId: requestId,
                filter: filter,
                reply: { [weak session] list, errorMessage in
                    session?.send(BridgeFrame(.audioListResult(
                        requestId: requestId,
                        list: list,
                        errorMessage: errorMessage
                    )))
                }
            )
        case .audioDelete(let requestId, let audioId, let appId):
            host?.handleAudioDelete(
                requestId: requestId,
                audioId: audioId,
                appId: appId,
                reply: { [weak session] deleted, errorMessage in
                    session?.send(BridgeFrame(.audioDeleteResult(
                        requestId: requestId,
                        deleted: deleted,
                        errorMessage: errorMessage
                    )))
                }
            )

        case .auth, .authOk, .authFailed, .versionMismatch,
             .sessionsSnapshot, .sessionUpdated, .messagesSnapshot,
             .messagesPage,
             .messageAppended, .messageStreaming, .errorEvent,
             .pairingPayload, .projectsSnapshot, .fileSnapshot,
             .transcriptionResult, .audioSnapshot,
             .generatedImageSnapshot, .bridgeState,
             .rateLimitsSnapshot, .rateLimitsUpdated,
             .skillsList, .skillsView, .skillsCreate,
             .skillsCreateResult, .skillsUpdate,
             .skillsUpdateResult, .skillsRemove,
             .skillsRemoveResult, .skillsActivate,
             .skillsDeactivate, .skillsSync,
             .skillsSyncProgress, .skillsImport,
             .skillsListResult, .skillsViewResult,
             .skillsActiveChanged,
             .audioRegisterResult, .audioAttachTranscriptResult,
             .audioGetResult, .audioBytesResult,
             .audioListResult, .audioDeleteResult:
            // Either already handled (auth) or server-only.
            break
        }
    }
}

/// Reads a text file off disk for the bridge `readFile` request.
///
/// Mirrors the macOS `FileViewerPanel.load` rules: report a friendly
/// reason for missing files / binary blobs / undecodable bytes instead
/// of leaking raw NSError descriptions, mark `.md` / `.markdown` files
/// so the iPhone renders them with the assistant's markdown view.
///
/// In dummy / fixture mode, the rollouts reference paths that don't
/// exist on this Mac (e.g. `/Users/demo/Code/Sample App/src/search/query.sql`).
/// To keep the file viewer functional, set the env var
/// `CLAWIX_FILE_FIXTURE_DIR=<dir>`. The reader then falls back, in order,
/// to: (a) a real file mirrored under `<dir>/<absolute path>`, so the
/// user can drop hand-crafted content for specific paths, and (b) a
/// synthesized body inferred from the basename and extension, so every
/// pill resolves to plausible content even without curation.
public enum BridgeFileReader {

    /// Opaque result used both by the bridge wire reply and the macOS
    /// `FileViewerPanel`. Keeps the on-disk → fixture → synthesized
    /// resolution in one place.
    public struct Result: Sendable {
        public let content: String?
        public let isMarkdown: Bool
        public let error: String?
        public init(content: String?, isMarkdown: Bool, error: String?) {
            self.content = content
            self.isMarkdown = isMarkdown
            self.error = error
        }
    }

    public static func read(path: String) -> BridgeBody {
        let result = load(path: path)
        return .fileSnapshot(
            path: path,
            content: result.content,
            isMarkdown: result.isMarkdown,
            error: result.error
        )
    }

    public static func load(path: String) -> Result {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        let onDisk = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let fixtureDir = ClawixEnv.value(ClawixEnv.fileFixtureDir)
            .flatMap { $0.isEmpty ? nil : $0 }

        if onDisk {
            if isDirectory.boolValue {
                return directorySnapshot(url: url)
            }
            return decode(url: url, originalPath: path)
        }

        if let dir = fixtureDir {
            let mirrored = URL(fileURLWithPath: dir)
                .appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            var mirroredIsDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: mirrored.path, isDirectory: &mirroredIsDirectory) {
                if mirroredIsDirectory.boolValue {
                    return directorySnapshot(url: mirrored)
                }
                return decode(url: mirrored, originalPath: path)
            }
            let synthesized = FixtureFileSynthesizer.synthesize(for: path)
            let isMarkdown = isMarkdownExtension(url.pathExtension)
            return Result(content: synthesized, isMarkdown: isMarkdown, error: nil)
        }

        return Result(content: nil, isMarkdown: false, error: "File not found")
    }

    private static func directorySnapshot(url: URL) -> Result {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Result(content: nil, isMarkdown: false, error: "Couldn't read file")
        }

        let sorted = children.sorted { lhs, rhs in
            let lhsIsDir = ((try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            let rhsIsDir = ((try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            if lhsIsDir != rhsIsDir {
                return lhsIsDir && !rhsIsDir
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        let limit = 200
        let visible = sorted.prefix(limit).map { child in
            let isDir = ((try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            return child.lastPathComponent + (isDir ? "/" : "")
        }
        var body = visible.joined(separator: "\n")
        if sorted.count > limit {
            body += "\n... \(sorted.count - limit) more"
        }
        if body.isEmpty {
            body = "(empty folder)"
        }
        return Result(content: body, isMarkdown: false, error: nil)
    }

    private static func decode(url: URL, originalPath: String) -> Result {
        guard let data = try? Data(contentsOf: url) else {
            return Result(content: nil, isMarkdown: false, error: "Couldn't read file")
        }
        if data.prefix(4096).contains(0) {
            return Result(content: nil, isMarkdown: false, error: "Preview not available for binary files")
        }
        guard let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .utf16) else {
            return Result(content: nil, isMarkdown: false, error: "Couldn't decode file as text")
        }
        let ext = URL(fileURLWithPath: originalPath).pathExtension
        return Result(content: raw, isMarkdown: isMarkdownExtension(ext), error: nil)
    }

    private static func isMarkdownExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "md" || lower == "markdown"
    }
}
