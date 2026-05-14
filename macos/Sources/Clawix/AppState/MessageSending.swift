import Foundation
import ClawixCore
import ClawixEngine

extension AppState {
    func sendMessage() {
        let trimmed = composer.text.trimmingCharacters(in: .whitespaces)
        let attachments = composer.attachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let mentions = attachments.map { "@\($0.url.path)" }.joined(separator: " ")
        let combined: String
        if trimmed.isEmpty {
            combined = mentions
        } else if mentions.isEmpty {
            combined = trimmed
        } else {
            combined = mentions + "\n\n" + trimmed
        }

        let userMsg = ChatMessage(role: .user, content: combined, timestamp: Date())
        let chatId: UUID
        if case .chat(let id) = currentRoute,
           let idx = chats.firstIndex(where: { $0.id == id }) {
            chats[idx].messages.append(userMsg)
            chats[idx].lastMessageAt = userMsg.timestamp
            chatId = id
        } else {
            // Create a new chat from home screen — inherits the project
            // currently selected in the composer pill (if any).
            let titleSeed = trimmed.isEmpty ? (attachments.first?.filename ?? "Attachments") : trimmed
            let newChat = Chat(
                id: UUID(),
                title: String(titleSeed.prefix(40)),
                messages: [userMsg],
                createdAt: Date(),
                projectId: selectedProject?.id,
                agentId: selectedAgentId,
                lastMessageAt: userMsg.timestamp
            )
            chats.insert(newChat, at: 0)
            currentRoute = .chat(newChat.id)
            chatId = newChat.id
        }
        composer.text = ""
        composer.attachments = []

        if let localModel = localModelName(forSelected: selectedModel) {
            let history = chats.first(where: { $0.id == chatId })?.messages ?? []
            LocalModelChat.shared.send(
                chatId: chatId,
                model: localModel,
                history: history,
                appState: self
            )
            return
        }

        if !FeatureFlags.shared.isVisible(.remoteMesh), !selectedMeshTarget.isLocal {
            selectedMeshTarget = .local
        }

        if FeatureFlags.shared.isVisible(.remoteMesh),
           case .peer(let nodeId) = selectedMeshTarget,
           let peer = meshStore.peers.first(where: { $0.nodeId == nodeId }) {
            dispatchRemoteMeshJob(peer: peer, chatId: chatId, prompt: combined)
            return
        }

        if clawJSSessionsCanonicalActive {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            Task { @MainActor in
                if await self.sendMessageViaClawJSSessions(chatId: chatId, text: combined, attachments: attachments) {
                    return
                }
                if let daemonBridgeClient = self.daemonBridgeClient {
                    daemonBridgeClient.sendPrompt(chatId: chatId, text: combined, attachments: self.wireAttachments(from: attachments))
                } else if let clawix = self.clawix {
                    await clawix.sendUserMessage(chatId: chatId, text: combined)
                    self.clawixBackendStatus = clawix.status
                }
            }
            return
        }

        if let daemonBridgeClient {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: combined, attachments: wireAttachments(from: attachments))
        } else if selectedAgentRuntime == .opencode {
            appendAssistantSystemMessage(
                to: chatId,
                text: "OpenCode runs through the background bridge. Enable the bridge, restart it, then send again."
            )
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    private func sendMessageViaClawJSSessions(
        chatId: UUID,
        text: String,
        attachments: [ComposerAttachment]
    ) async -> Bool {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return false }
        let client = ClawJSSessionsClient.local()
        let sessionId = chats[idx].clawixThreadId ?? chatId.uuidString
        let projectPath = chats[idx].projectId.flatMap { projectId in
            projects.first(where: { $0.id == projectId })?.path
        }
        do {
            let response = try await client.startTurn(
                sessionId: sessionId,
                input: .init(
                    prompt: text,
                    projectId: nil,
                    projectPath: projectPath,
                    cwd: projectPath,
                    title: chats[idx].title,
                    attachments: attachments.map { attachment in
                        .object([
                            "id": .string(attachment.id.uuidString),
                            "path": .string(attachment.url.path),
                            "filename": .string(attachment.filename)
                        ])
                    },
                    audioRef: nil,
                    fakeReply: nil
                )
            )
            guard let currentIdx = chats.firstIndex(where: { $0.id == chatId }) else { return true }
            chats[currentIdx].clawixThreadId = response.session?.id ?? sessionId
            chats[currentIdx].hasActiveTurn = false
            if let assistant = response.assistantMessage, !assistant.contentText.isEmpty {
                let now = Date()
                let summary = WorkSummary(
                    startedAt: now,
                    endedAt: now,
                    items: [
                        WorkItem(
                            id: assistant.id,
                            kind: .dynamicTool(name: "Codex"),
                            status: assistant.streamingState == "complete" ? .completed : .failed
                        )
                    ]
                )
                chats[currentIdx].messages.append(ChatMessage(
                    role: .assistant,
                    content: assistant.contentText,
                    timestamp: now,
                    workSummary: summary,
                    timeline: [
                        .tools(id: UUID(), items: summary.items),
                        .message(id: UUID(), text: assistant.contentText)
                    ]
                ))
                chats[currentIdx].lastMessageAt = now
            }
            return true
        } catch {
            appendErrorBubble(chatId: chatId, message: "Could not send through ClawJS sessions: \(error.localizedDescription)")
            return false
        }
    }

    func wireAttachments(from attachments: [ComposerAttachment]) -> [WireAttachment] {
        attachments.compactMap { attachment in
            guard attachment.isImage,
                  let data = try? Data(contentsOf: attachment.url)
            else { return nil }
            return WireAttachment(
                id: attachment.id.uuidString,
                kind: .image,
                mimeType: mimeType(forImageURL: attachment.url),
                filename: attachment.filename,
                dataBase64: data.base64EncodedString()
            )
        }
    }

    private func mimeType(forImageURL url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    /// Outbound mesh dispatch. Validates that a remote workspace has
    /// been configured for this peer (without one, the remote daemon
    /// would always reject the job with `workspaceDenied`), starts
    /// the job through `MeshStore`, and surfaces a synthetic system
    /// message in the chat so the user has feedback that "this turn
    /// is running on a different Mac". The actual streaming card
    /// renders against `meshStore.activeJobs[…]` from `ChatView`.
    private func dispatchRemoteMeshJob(peer: PeerRecord, chatId: UUID, prompt: String) {
        let workspace = meshStore.remoteWorkspace(for: peer.nodeId)
        guard !workspace.isEmpty else {
            appendAssistantSystemMessage(
                to: chatId,
                text: "No remote workspace set for \(peer.displayName). Open Settings → Hosts and add one before sending."
            )
            return
        }
        Task { @MainActor in
            let result = await meshStore.startRemoteJob(
                peer: peer,
                workspacePath: workspace,
                prompt: prompt,
                chatId: chatId
            )
            switch result {
            case .success(let job):
                appendAssistantSystemMessage(
                    to: chatId,
                    text: "Running on \(peer.displayName) · job \(job.id.prefix(8))…"
                )
            case .failure(let error):
                appendAssistantSystemMessage(
                    to: chatId,
                    text: "Could not start remote job: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Append a transient system note to a chat. Used by the mesh
    /// dispatch path so the user always sees something happen even
    /// when the assistant reply is going to land on a remote Mac, and
    /// by the OpenCode-bridge nudge path that already called this
    /// helper before the function existed.
    func appendAssistantSystemMessage(to chatId: UUID, text: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let note = ChatMessage(role: .assistant, content: text, streamingFinished: true, timestamp: Date())
        chats[idx].messages.append(note)
    }

    /// Returns the bare Ollama model name (e.g. `llama3.2:3b`) when the
    /// composer's currently-selected model points at a local runtime
    /// model. The composer encodes this with the `ollama:` prefix so the
    /// rest of the app can keep treating `selectedModel` as an opaque
    /// string. Returns nil for the GPT/Codex options.
    func localModelName(forSelected raw: String) -> String? {
        guard FeatureFlags.shared.isVisible(.localModels) else { return nil }
        let prefix = "ollama:"
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    var openCodeModelSelection: String {
        if selectedModel.contains("/") { return selectedModel }
        return AgentRuntimeChoice.persistedOpenCodeModel()
    }

    func enforceExperimentalRuntimeVisibility() {
        guard !FeatureFlags.shared.isVisible(.openCode) else { return }
        if selectedAgentRuntime == .opencode {
            selectedAgentRuntime = .codex
        }
        if selectedModel.contains("/") {
            selectedModel = "5.5"
        }
        if let selectedAgent = AgentStore.shared.agent(id: selectedAgentId),
           selectedAgent.runtime != .codex {
            selectedAgentId = Agent.defaultCodexId
        }
        if QuickAskController.shared.quickAskDefaultModel?.contains("/") == true {
            QuickAskController.shared.quickAskDefaultModel = nil
        }
    }

    /// Submit a prompt from the QuickAsk HUD. Mirrors the home-route
    /// branch of `sendMessage()` (same daemon vs in-process dispatch)
    /// but takes the prompt directly so the main composer state is not
    /// touched. When `chatId` is nil a fresh chat is created and inserted
    /// at the top of the sidebar; the resolved id is returned so
    /// QuickAskController can persist it across hotkey presses.
    ///
    /// [QUICKASK<->CHAT PARITY] This function and `sendMessage()` are
    /// SISTER entry points to the same daemon dispatch. `sendMessage()`
    /// implicitly runs `openSession` via `currentRoute.didSet` because it
    /// switches the main route to `.chat(id)`. QuickAsk does NOT touch
    /// `currentRoute` (it would yank the user out of the HUD), so this
    /// function MUST call `daemonBridgeClient.openSession(resolvedId)` itself
    /// before `sendPrompt`. Without it the daemon receives the prompt but
    /// the BridgeBus has no subscription for this chatId, so
    /// `messageStreaming` / `messageAppended` frames are filtered out and
    /// the HUD never sees the assistant reply. References:
    ///   - BridgeIntent.swift `.sendPrompt` case (no auto-subscribe)
    ///   - BridgeBus.subscribe (idempotent set insert)
    ///   - BridgeProtocol.swift comment on `.newChat` ("auto-subscribes")
    ///   - sister bubble: `QuickAskMessageBubble` in QuickAskView.swift
    @discardableResult
    func submitQuickAsk(
        chatId: UUID?,
        text: String,
        attachments: [QuickAskAttachment] = [],
        temporary: Bool = false
    ) -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty || !attachments.isEmpty,
                     "submitQuickAsk requires non-empty text or at least one attachment")

        // Same convention as `sendMessage()` for the main composer:
        // attachments enter the prompt as `@<absolute-path>` mentions
        // so the daemon can resolve them server-side (image attachments
        // become `localImage` items, file paths get read into context).
        // Selection / clipboard chips that carry their own preview text
        // ride as a leading "Selected text:" / "Clipboard:" block
        // because the source isn't a file the agent can re-read.
        let mentions = attachments.compactMap { att -> String? in
            switch att.kind {
            case .file, .drop, .paste, .screenshot, .camera:
                return "@\(att.url.path)"
            case .clipboard:
                // Clipboard chips fall into two shapes: file URLs
                // (mention path) and inline text (skip; surfaced as
                // a "Clipboard:" prelude below).
                return att.previewText == nil ? "@\(att.url.path)" : nil
            case .selection:
                // Selection chips carry the verbatim text the user
                // wanted included; surface it as a quoted block
                // before the prompt rather than a path mention.
                return nil
            }
        }
        let preludes = attachments.compactMap { att -> String? in
            switch att.kind {
            case .selection:
                guard let text = att.previewText else { return nil }
                return "Selected text:\n\(text)"
            case .clipboard:
                guard let text = att.previewText else { return nil }
                return "Clipboard:\n\(text)"
            default:
                return nil
            }
        }

        let combined: String = {
            var parts: [String] = []
            if !preludes.isEmpty { parts.append(preludes.joined(separator: "\n\n")) }
            if !mentions.isEmpty { parts.append(mentions.joined(separator: " ")) }
            if !trimmed.isEmpty { parts.append(trimmed) }
            return parts.joined(separator: "\n\n")
        }()

        let userMsg = ChatMessage(role: .user, content: combined, timestamp: Date())
        let resolvedId: UUID
        if let id = chatId, let idx = chats.firstIndex(where: { $0.id == id }) {
            chats[idx].messages.append(userMsg)
            chats[idx].lastTurnInterrupted = false
            chats[idx].lastMessageAt = userMsg.timestamp
            resolvedId = id
        } else {
            let titleSeed = trimmed.isEmpty
                ? (attachments.first?.filename ?? "Attachments")
                : trimmed
            let newChat = Chat(
                id: UUID(),
                title: String(titleSeed.prefix(40)),
                messages: [userMsg],
                createdAt: Date(),
                projectId: selectedProject?.id,
                isQuickAskTemporary: temporary,
                agentId: selectedAgentId,
                lastMessageAt: userMsg.timestamp
            )
            chats.insert(newChat, at: 0)
            resolvedId = newChat.id
        }

        if let daemonBridgeClient {
            // sendMessage() reaches openSession implicitly via the
            // currentRoute didSet; QuickAsk doesn't switch the route
            // (the HUD stays on top of whatever the user was doing),
            // so we have to subscribe this chat to the bridge bus
            // explicitly. openSession is idempotent (Set.insert) so
            // calling it on every submit is safe and also covers the
            // re-subscribe-after-reconnect case.
            trackOptimisticUserMessage(chatId: resolvedId, messageId: userMsg.id)
            daemonBridgeClient.openSession(resolvedId)
            daemonBridgeClient.sendPrompt(chatId: resolvedId, text: combined)
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: resolvedId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }

        return resolvedId
    }

    /// Entry point used by the bridge that exposes the desktop app to the
    /// iOS companion. Mirrors the user-message half of `sendMessage()`
    /// but takes the chat id, text and inline attachments as parameters
    /// rather than reading from the composer.
    ///
    /// `attachments` carries images the iPhone composer encoded inline.
    /// They are spooled to a chat-scoped temp dir and forwarded as
    /// `localImage` items either through `daemonBridgeClient` (which
    /// reships the wire `WireAttachment`s to `clawix-bridge`) or
    /// straight into the in-process `ClawixService`. Sending an
    /// attachment-only message (empty `text`) is supported so the
    /// composer can ship a photo with no caption.
    /// Wrapper used by the Apps surface SDK (`window.clawix.agent.sendMessage`)
    /// to inject a synthetic user message into the chat that originally
    /// owned the app. Funnels through `sendUserMessageFromBridge` so
    /// the optimistic-message + bridge-roundtrip plumbing is shared.
    @MainActor
    func dispatchAppMessage(_ text: String, toChatId chatId: UUID) {
        sendUserMessageFromBridge(chatId: chatId, text: text, attachments: [])
    }

    @MainActor
    func sendUserMessageFromBridge(
        chatId: UUID,
        text: String,
        attachments: [WireAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }

        let imageAttachments = attachments.filter { $0.kind == .image }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        let preview = bridgeUserPreview(
            text: trimmed,
            imageCount: imageAttachments.count,
            hasAudio: !audioAttachments.isEmpty
        )
        let userMsg = ChatMessage(role: .user, content: preview, timestamp: Date())
        chats[idx].messages.append(userMsg)
        // Sending a fresh prompt closes any earlier interrupted-turn
        // pill: the user has acknowledged the gap and is moving on.
        chats[idx].lastTurnInterrupted = false

        // Audio attachments are stored locally (so the chat history
        // can replay the clip later) and never shipped to the model:
        // Codex doesn't accept audio, the iPhone composer already
        // transcribed via the `transcribeAudio` frame, and we use that
        // transcript as the prompt text.
        if !audioAttachments.isEmpty {
            ingestAudioFromBridge(
                attachments: audioAttachments,
                chatId: chatId,
                messageId: userMsg.id,
                transcript: trimmed
            )
        }

        if let daemonBridgeClient {
            // The daemon spools the attachments itself and emits
            // `localImage` paths to Codex; we just forward the raw
            // wire payload over loopback.
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        } else if let clawix {
            let imagePaths = AttachmentSpooler.write(
                attachments: imageAttachments,
                scope: chatId.uuidString
            )
            Task { @MainActor in
                await clawix.sendUserMessage(
                    chatId: chatId,
                    text: trimmed,
                    imagePaths: imagePaths
                )
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    /// Persist audio attachments coming off the bridge into
    /// `AudioMessageStore` and patch the user message with the
    /// resulting `audioRef` once the bytes land. Runs detached so the
    /// optimistic message bubble shows immediately; the bubble's
    /// playable state lights up as soon as ingest finishes.
    private func ingestAudioFromBridge(
        attachments: [WireAttachment],
        chatId: UUID,
        messageId: UUID,
        transcript: String
    ) {
        guard let attachment = attachments.first else { return }
        guard let data = Data(base64Encoded: attachment.dataBase64) else { return }
        let mime = attachment.mimeType
        // The local in-process server doesn't track Codex thread ids by
        // chat id (that lives inside `clawix`). Use the chat UUID as a
        // stable thread anchor instead — the store only uses it to
        // group entries for hydrate-time matching, which we don't
        // exercise in the in-process path (no rollout rebuild here).
        let threadId = chatId.uuidString
        let chatIdString = chatId.uuidString
        let messageIdString = messageId.uuidString
        Task { [weak self] in
            do {
                let entry = try await AudioMessageStore.shared.ingest(
                    threadId: threadId,
                    chatId: chatIdString,
                    messageId: messageIdString,
                    audioData: data,
                    mimeType: mime,
                    transcript: transcript
                )
                await MainActor.run {
                    guard let self else { return }
                    guard let cIdx = self.chats.firstIndex(where: { $0.id == chatId }),
                          let mIdx = self.chats[cIdx].messages.firstIndex(where: { $0.id == messageId })
                    else { return }
                    self.chats[cIdx].messages[mIdx].audioRef = entry.wireRef
                }
                // Dual-write into the framework audio catalog so new
                // ingests stay queryable via `audioGetBytes / audioList`
                // alongside the legacy on-disk store. Best effort: the
                // legacy store is still the source of truth this release.
                if let client = await MainActor.run(body: { AudioCatalogBootstrap.shared.currentClient }) {
                    _ = try? await client.register(.init(
                        id: entry.id,
                        kind: "user_message",
                        appId: "clawix",
                        originActor: "user",
                        mimeType: entry.mimeType,
                        bytesBase64: data.base64EncodedString(),
                        durationMs: entry.durationMs,
                        threadId: entry.threadId,
                        linkedMessageId: entry.messageId,
                        transcript: transcript.isEmpty ? nil : .init(
                            text: transcript,
                            role: "transcription",
                            provider: "transcribeAudio"
                        )
                    ))
                }
            } catch {
                // Soft fail: the user message is still in the chat;
                // the bubble simply won't have a play button.
            }
        }
    }

    /// Render a short preview for the optimistic user bubble that the
    /// macOS chat list (and the iPhone companion via bridge echo) shows
    /// while the turn is still running. Mirrors the daemon's preview so
    /// attachment counts read consistently across surfaces.
    private func bridgeUserPreview(text: String, imageCount: Int, hasAudio: Bool = false) -> String {
        guard imageCount > 0 else {
            return hasAudio && text.isEmpty ? "[voice]" : text
        }
        let label = imageCount == 1 ? "[image]" : "[\(imageCount) images]"
        return text.isEmpty ? label : "\(label) \(text)"
    }

    /// Bridge entry point for "tap the New Chat FAB on the iPhone": the
    /// client pre-mints the UUID and ships the first prompt in one shot.
    /// We create a Chat with that exact id, append the user message, and
    /// kick the turn off through whichever runtime is active. Mirrors
    /// the home-route branch of `sendMessage()` (lines around 1488),
    /// extended to forward inline image attachments to the active
    /// runtime via the same path `sendUserMessageFromBridge` uses.
    @MainActor
    func newChatFromBridge(
        chatId: UUID,
        text: String,
        attachments: [WireAttachment] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        // Idempotency: if the chat somehow already exists (re-delivery
        // or client retry), fall through to the "append to existing"
        // path so we don't duplicate it.
        if chats.contains(where: { $0.id == chatId }) {
            sendUserMessageFromBridge(chatId: chatId, text: trimmed, attachments: attachments)
            return
        }
        let imageAttachments = attachments.filter { $0.kind == .image }
        let audioAttachments = attachments.filter { $0.kind == .audio }
        let preview = bridgeUserPreview(
            text: trimmed,
            imageCount: imageAttachments.count,
            hasAudio: !audioAttachments.isEmpty
        )
        let userMsg = ChatMessage(role: .user, content: preview, timestamp: Date())
        let titleSeed: String = {
            if !trimmed.isEmpty { return String(trimmed.prefix(40)) }
            if !imageAttachments.isEmpty { return imageAttachments.count == 1 ? "Image" : "Images" }
            if !audioAttachments.isEmpty { return "Voice note" }
            return "Conversation"
        }()
        let newChat = Chat(
            id: chatId,
            title: titleSeed,
            messages: [userMsg],
            createdAt: Date()
        )
        chats.insert(newChat, at: 0)

        if !audioAttachments.isEmpty {
            ingestAudioFromBridge(
                attachments: audioAttachments,
                chatId: chatId,
                messageId: userMsg.id,
                transcript: trimmed
            )
        }

        if let daemonBridgeClient {
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.sendPrompt(chatId: chatId, text: trimmed, attachments: attachments)
        } else if let clawix {
            let imagePaths = AttachmentSpooler.write(
                attachments: imageAttachments,
                scope: chatId.uuidString
            )
            Task { @MainActor in
                await clawix.sendUserMessage(
                    chatId: chatId,
                    text: trimmed,
                    imagePaths: imagePaths
                )
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    func addComposerAttachments(_ urls: [URL]) {
        let existing = Set(composer.attachments.map { $0.url.standardizedFileURL.path })
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !existing.contains(path) else { continue }
            composer.attachments.append(ComposerAttachment(url: url))
        }
    }

    func removeComposerAttachment(id: UUID) {
        composer.attachments.removeAll { $0.id == id }
    }

    /// Pulls keyboard focus back into the composer text field. Used by
    /// ⌘N (when the home screen is already mounted), chat switches and
    /// other places where the same composer view stays mounted but the
    /// user's intent is "let me start typing now".
    func requestComposerFocus() {
        composer.focusToken &+= 1
    }

    /// Called by ComposerView's Stop button.
    func interruptActiveTurn() {
        guard case let .chat(id) = currentRoute else { return }
        interruptActiveTurn(chatId: id)
    }

    /// Stop the in-flight turn for `chatId` regardless of the current
    /// route. Used by the iPhone bridge so a remote stop affects the
    /// right chat even when the Mac UI is focused on a different one.
    func interruptActiveTurn(chatId: UUID) {
        // Update UI synchronously so the "Thinking" shimmer disappears
        // immediately on click. The backend interrupt is fire-and-forget;
        // late-arriving deltas for this turn are dropped by ClawixService
        // via its interruptedTurnIds gate.
        finalizeOrRemoveAssistantPlaceholder(chatId: chatId)
        if let daemonBridgeClient {
            daemonBridgeClient.interruptTurn(chatId: chatId)
            return
        }
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.interruptCurrentTurn(chatId: chatId)
        }
    }

    /// Drop the chat out of the "Pensando…" / streaming state right now.
    /// If the assistant placeholder is still empty (no text, no reasoning,
    /// no tool activity), remove it entirely so the chat ends on the user's
    /// message. If it has any visible content, freeze it as finished so the
    /// shimmer stops but the partial answer stays.
    func finalizeOrRemoveAssistantPlaceholder(chatId: UUID) {
        // Flush coalesced deltas first so the `isEmpty` check below sees
        // the actual streamed content instead of an empty string from
        // the placeholder.
        flushPendingAssistantTextDeltas(chatId: chatId)
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].hasActiveTurn = false
        guard let last = chats[idx].messages.indices.last,
              chats[idx].messages[last].role == .assistant,
              !chats[idx].messages[last].streamingFinished
        else { return }
        let msg = chats[idx].messages[last]
        // A workSummary that's been initialized but never received items
        // (turn/started fired, then user stopped before any delta) renders
        // nothing on its own: the WorkSummaryHeader requires items, and the
        // timeline mirrors items 1:1. Treat that as empty so we drop the
        // placeholder entirely instead of leaving an invisible row whose
        // only visible artifact would be the trailing action bar.
        let workSummaryEmpty = msg.workSummary?.items.isEmpty ?? true
        let isEmpty = msg.content.isEmpty
            && msg.reasoningText.isEmpty
            && msg.timeline.isEmpty
            && workSummaryEmpty
        if isEmpty {
            chats[idx].messages.remove(at: last)
        } else {
            chats[idx].messages[last].streamingFinished = true
            // Freeze the elapsed-seconds counter at the moment of stop.
            // Without this, WorkSummaryHeader's TimelineView keeps ticking
            // because `summary.isActive` stays true while `endedAt` is nil.
            if chats[idx].messages[last].workSummary != nil,
               chats[idx].messages[last].workSummary?.endedAt == nil {
                chats[idx].messages[last].workSummary?.endedAt = Date()
            }
        }
    }
}
