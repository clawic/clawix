import Foundation
import Network
import ClawixCore
import os
#if canImport(UIKit)
import UIKit
#endif

/// Companion logger to `BridgeStore`'s. Same subsystem so a single
/// `log show` predicate captures the whole timeline. Remove with the
/// rest of the diagnostic plumbing once the new-chat-disappears bug
/// is closed.
fileprivate let clientDbg = Logger(subsystem: "clawix.bridge.dbg", category: "client")

/// Bridge client for the iOS companion. Speaks WebSocket to the Mac
/// over `NWConnection + NWProtocolWebSocket`, the same primitive the
/// Mac side uses, which is what unlocks:
///
/// - **Native Local Network permission**: an `NWBrowser` inside this
///   client triggers the iOS Local Network dialog the first time we
///   try to connect; URLSession would have stayed silently blocked.
/// - **Multi-path racing**: every connect attempt fires connections
///   to *all* known candidates in parallel (Bonjour-resolved LAN
///   service, the LAN IPv4 baked into the QR, and the Tailscale CGNAT
///   IPv4 if the Mac advertised one). The first to complete the WS
///   handshake AND authenticate wins, the others are cancelled. This
///   is what makes "at home → fast LAN" and "leaving the house →
///   automatic Tailscale fallback" feel instant without the user
///   touching anything.
/// - **Self-healing LAN discovery**: the `NWBrowser` keeps running
///   while paired, so if the Mac's DHCP lease changes or it moves
///   networks, the next reconnect already has the fresh address.
/// - **App-layer keepalive**: a 15s WS ping is sent on the active
///   connection. If we go 30s without any inbound traffic the
///   connection is considered dead and we restart the race. This
///   catches the "iPhone WiFi silently dropped, TCP doesn't notice
///   for minutes" case that plain TCP keepalive misses.
@MainActor
final class BridgeClient: NSObject {

    private let store: BridgeStore

    private var creds: Credentials?

    /// In-flight connections being raced. The first to receive
    /// `authOk` becomes `winner` and the rest are cancelled.
    private var candidates: [Candidate] = []

    /// The candidate that won the race; messages flow through this
    /// connection until it dies.
    private var winner: Candidate?

    /// Always-on while paired. Feeds Bonjour-resolved endpoints into
    /// the candidate pool, and is what causes iOS to surface the
    /// Local Network permission dialog.
    private var browser: NWBrowser?

    private var reconnectAttempt: Int = 0
    private var reconnectWork: DispatchWorkItem?

    private var keepaliveTimer: Timer?
    private var lastInboundAt: Date?

    private static let perCandidateTimeout: TimeInterval = 5
    private static let visibleConnectionFailureAfter = 2
    private static let keepalivePingInterval: TimeInterval = 15
    private static let keepaliveDeadAfter: TimeInterval = 30

    /// Coalesce window for `messageStreaming` chunks. A turn typically
    /// emits a few chunks per second; without coalescing each one
    /// reassigns `store.messagesByChat[chatId]` and causes every view
    /// observing the array to redraw, including the markdown parser
    /// in `AssistantMarkdownView`. Batching at 80ms keeps the visible
    /// streaming smooth (~12fps text growth, well under typing speed)
    /// while collapsing redraws by an order of magnitude when chunks
    /// arrive faster than the eye can read.
    private static let streamCoalesceNanos: UInt64 = 80_000_000

    /// Pending streaming updates keyed by `messageId`. Each new chunk
    /// for the same message overwrites the previous (last-wins); a
    /// `finished == true` chunk forces an immediate flush so the user
    /// sees the final text without the 80ms delay.
    private var pendingStreamUpdates: [String: PendingStreamUpdate] = [:]
    private var streamFlushScheduled: Bool = false

    private struct PendingStreamUpdate {
        let chatId: String
        let messageId: String
        let content: String
        let reasoning: String
        let finished: Bool
    }

    init(store: BridgeStore) {
        self.store = store
        super.init()
    }

    // MARK: - Lifecycle

    func connect(_ creds: Credentials) {
        self.creds = creds
        cancelReconnect()
        reconnectAttempt = 0
        startBrowser()
        startRace()
    }

    func disconnect() {
        cancelReconnect()
        stopKeepalive()
        cancelAllCandidates()
        if let winner {
            winner.connection.cancel()
        }
        winner = nil
        stopBrowser()
        creds = nil
        store.connection = .unpaired
    }

    /// Tears down the active socket and pending reconnect timers without
    /// dropping the cached credentials, so a later `connect(creds)`
    /// (typically driven by `scenePhase == .active`) can resume the
    /// session immediately.
    ///
    /// Calling `suspend()` on background does two things that
    /// `disconnect()` also does: cancels the WebSocket and stops the
    /// browser. The difference is that we keep `creds` cached and we
    /// do NOT zero out the credential store, so the UI never flips
    /// back to the pairing screen.
    func suspend() {
        cancelReconnect()
        stopKeepalive()
        cancelAllCandidates()
        if let winner {
            winner.connection.cancel()
        }
        winner = nil
        stopBrowser()
        store.connection = .unpaired
        // creds intentionally preserved for resume.
    }

    // MARK: - Outbound from UI

    func openChat(_ chatId: String) {
        guard let winner else { return }
        // Always opt into pagination on the iPhone: the initial paint
        // only needs the trailing window; older history streams in via
        // `loadOlderMessages` if the user scrolls up. Old daemons that
        // don't understand `limit` ignore it and send the whole
        // transcript, which still works (`hasMore` arrives as nil and
        // the store treats that as "no scroll-up available").
        send(BridgeFrame(.openChat(chatId: chatId, limit: bridgeInitialPageLimit)), on: winner)
    }

    /// Fetch the next page of older messages for `chatId`. The cursor
    /// is the id of the oldest message the iPhone currently has; the
    /// daemon replies with `messagesPage` carrying the slice prior to
    /// it (oldest first). No-op when not yet connected.
    func loadOlderMessages(chatId: String, beforeMessageId: String) {
        guard let winner else { return }
        send(BridgeFrame(.loadOlderMessages(
            chatId: chatId,
            beforeMessageId: beforeMessageId,
            limit: bridgeOlderPageLimit
        )), on: winner)
    }

    func sendPrompt(chatId: String, text: String, attachments: [WireAttachment]) {
        guard let winner else { return }
        send(BridgeFrame(.sendPrompt(chatId: chatId, text: text, attachments: attachments)), on: winner)
    }

    func sendNewChat(chatId: String, text: String, attachments: [WireAttachment]) {
        guard let winner else {
            clientDbg.notice("sendNewChat DROPPED (no winner) id=\(chatId, privacy: .public)")
            return
        }
        clientDbg.notice("TX newChat id=\(chatId, privacy: .public) winner=\(winner.label, privacy: .public)")
        send(BridgeFrame(.newChat(chatId: chatId, text: text, attachments: attachments)), on: winner)
    }

    func interruptTurn(chatId: String) {
        guard let winner else { return }
        send(BridgeFrame(.interruptTurn(chatId: chatId)), on: winner)
    }

    func renameChat(chatId: String, title: String) {
        guard let winner else { return }
        send(BridgeFrame(.renameChat(chatId: chatId, title: title)), on: winner)
    }

    func archiveChat(chatId: String) {
        guard let winner else { return }
        send(BridgeFrame(.archiveChat(chatId: chatId)), on: winner)
    }

    func readFile(path: String) {
        guard let winner else { return }
        send(BridgeFrame(.readFile(path: path)), on: winner)
    }

    func transcribeAudio(
        requestId: String,
        audioBase64: String,
        mimeType: String,
        language: String?
    ) {
        guard let winner else { return }
        send(
            BridgeFrame(.transcribeAudio(
                requestId: requestId,
                audioBase64: audioBase64,
                mimeType: mimeType,
                language: language
            )),
            on: winner
        )
    }

    func requestAudio(audioId: String) {
        guard let winner else { return }
        send(BridgeFrame(.requestAudio(audioId: audioId)), on: winner)
    }

    func requestGeneratedImage(path: String) {
        guard let winner else { return }
        send(BridgeFrame(.requestGeneratedImage(path: path)), on: winner)
    }

    // MARK: - Bonjour browser

    private func startBrowser() {
        if browser != nil { return }
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: "_clawix-bridge._tcp",
            domain: nil
        )
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowse(results)
            }
        }
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func stopBrowser() {
        browser?.cancel()
        browser = nil
    }

    private func handleBrowse(_ results: Set<NWBrowser.Result>) {
        guard winner == nil, let creds else { return }
        let target = creds.macName
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            // If we know the Mac's name, only accept that service. If
            // we don't (very old pairing payload), accept any match —
            // there is rarely more than one Clawix on a LAN.
            if let target, name != target { continue }
            if candidates.contains(where: { $0.endpointKey == endpointKey(for: result.endpoint) }) {
                continue
            }
            addCandidate(endpoint: result.endpoint, route: .lan, label: "bonjour:\(name)")
        }
    }

    // MARK: - Connection race

    private func startRace() {
        guard let creds, winner == nil else { return }
        cancelAllCandidates()
        store.connection = .connecting
        // Reconnecting: forget the daemon's last claimed sync state.
        // Otherwise an empty `chats` would briefly read as ".ready"
        // (cached from the previous session) and the chat list would
        // flash "no chats" while the new socket finishes auth.
        store.resetBridgeSyncForReconnect()

        // Direct IPv4 candidates from the QR. Bonjour candidates are
        // added asynchronously by `handleBrowse` as soon as the
        // browser yields a match; we don't block on it.
        if !creds.host.isEmpty, creds.host != "0.0.0.0" {
            let route: BridgeStore.Route = isTailscaleHost(creds.host) ? .tailscale : .lan
            for (endpoint, suffix) in makeDirectEndpoints(host: creds.host, port: creds.port) {
                addCandidate(
                    endpoint: endpoint,
                    route: route,
                    label: "\(route.rawValue):\(creds.host):\(suffix)"
                )
            }
        }
        if let ts = creds.tailscaleHost, !ts.isEmpty, ts != creds.host {
            for (endpoint, suffix) in makeDirectEndpoints(host: ts, port: creds.port) {
                addCandidate(
                    endpoint: endpoint,
                    route: .tailscale,
                    label: "tailscale:\(ts):\(suffix)"
                )
            }
        }

        // No direct host means this pairing came in via the short-code
        // flow, which deliberately leaves the host empty: the `browser`
        // launched above will feed Bonjour-resolved candidates into
        // `handleBrowse` as soon as the Mac advertises itself on the
        // current Wi-Fi. Stay in `.connecting` until that happens; the
        // per-candidate timeouts + `scheduleReconnect` keep retrying
        // forever, which is the right behaviour when the user roams
        // between networks.
    }

    private func makeDirectEndpoints(host: String, port: Int) -> [(NWEndpoint, String)] {
        var endpoints: [(NWEndpoint, String)] = []
        // NWProtocolWebSocket clients need a URL endpoint to set the
        // `Host` header and request path of the upgrade GET. With a bare
        // `hostPort` endpoint the upgrade aborts on iOS 26 with
        // ECONNABORTED right after the TCP handshake, even against a
        // server that the same payload reaches fine over Python `ws://`.
        if let url = URL(string: "ws://\(host):\(port)/") {
            endpoints.append((.url(url), "url"))
        }
        endpoints.append((.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? .any
        ), "hostport"))
        return endpoints
    }

    private func endpointKey(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, let type, let domain, _):
            return "service:\(name).\(type).\(domain)"
        case .hostPort(let host, let port):
            return "host:\(host):\(port)"
        case .unix(let path):
            return "unix:\(path)"
        case .url(let url):
            return "url:\(url.absoluteString)"
        case .opaque(let value):
            return "opaque:\(value.debugDescription)"
        @unknown default:
            return "unknown:\(endpoint.debugDescription)"
        }
    }

    private func isTailscaleHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    private func addCandidate(endpoint: NWEndpoint, route: BridgeStore.Route, label: String) {
        let parameters = makeWebSocketParameters()
        let connection = NWConnection(to: endpoint, using: parameters)
        let candidate = Candidate(
            connection: connection,
            route: route,
            label: label,
            endpointKey: endpointKey(for: endpoint)
        )
        candidates.append(candidate)

        connection.stateUpdateHandler = { [weak self, weak candidate] state in
            Task { @MainActor in
                guard let self, let candidate else { return }
                self.handleCandidateState(candidate, state: state)
            }
        }

        // Per-candidate timeout. NWConnection has a `.waiting` state
        // for "no path right now"; we don't want to sit there waiting
        // for IPv6 to come up while a sibling candidate has already
        // connected via IPv4. If we are not authenticated within the
        // timeout window, the candidate is killed and removed.
        let work = DispatchWorkItem { [weak self, weak candidate] in
            Task { @MainActor in
                guard let self, let candidate else { return }
                if self.winner == nil,
                   self.candidates.contains(where: { $0.id == candidate.id }) {
                    candidate.connection.cancel()
                }
            }
        }
        candidate.timeoutWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.perCandidateTimeout,
            execute: work
        )

        connection.start(queue: .main)
    }

    private func makeWebSocketParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        return parameters
    }

    private func handleCandidateState(_ candidate: Candidate, state: NWConnection.State) {
        switch state {
        case .ready:
            sendAuth(on: candidate)
            receive(on: candidate)
        case .failed, .cancelled:
            candidate.timeoutWork?.cancel()
            candidate.timeoutWork = nil
            if winner?.id == candidate.id {
                clientDbg.notice("WINNER DROPPED label=\(candidate.label, privacy: .public) — restarting race")
                // Active connection died, restart the race.
                winner = nil
                stopKeepalive()
                store.connection = .connecting
                store.resetBridgeSyncForReconnect()
                scheduleReconnect()
            } else {
                candidates.removeAll { $0.id == candidate.id }
                if winner == nil, candidates.isEmpty {
                    scheduleReconnect()
                }
            }
        default:
            break
        }
    }

    // MARK: - WebSocket I/O

    private func sendAuth(on candidate: Candidate) {
        guard let creds else { return }
        let frame = BridgeFrame(.auth(
            token: creds.token,
            deviceName: deviceName(),
            clientKind: .ios
        ))
        send(frame, on: candidate)
    }

    private func receive(on candidate: Candidate) {
        candidate.connection.receiveMessage { [weak self, weak candidate] data, context, _, error in
            Task { @MainActor in
                guard let self, let candidate else { return }
                if let error {
                    candidate.connection.cancel()
                    return
                }
                if let data {
                    self.handleInbound(data: data, context: context, on: candidate)
                }
                // Re-arm only if the connection is still alive.
                let s = candidate.connection.state
                if case .ready = s {
                    self.receive(on: candidate)
                } else if case .preparing = s {
                    self.receive(on: candidate)
                }
            }
        }
    }

    private func handleInbound(
        data: Data,
        context: NWConnection.ContentContext?,
        on candidate: Candidate
    ) {
        lastInboundAt = Date()

        // Filter to text/binary frames; pongs and control frames have
        // their opcode set in the metadata and no application payload.
        if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata {
            switch metadata.opcode {
            case .text, .binary:
                break
            case .ping, .pong, .close, .cont:
                return
            @unknown default:
                return
            }
        }

        guard !data.isEmpty else { return }

        let frame: BridgeFrame
        do {
            frame = try BridgeCoder.decode(data)
        } catch {
            return
        }
        guard frame.schemaVersion == bridgeSchemaVersion else {
            clientDbg.error("RX schema mismatch frame=\(frame.schemaVersion, privacy: .public) ours=\(bridgeSchemaVersion, privacy: .public) cand=\(candidate.label, privacy: .public)")
            store.connection = .error(message: "Update Clawix on the Mac")
            store.bridgeSync = .error("Update Clawix on the Mac")
            store.bridgeSyncUpdatedAt = Date()
            candidate.connection.cancel()
            return
        }

        // Until a candidate wins, only authOk / authFailed should
        // mutate the store. After it wins, every snapshot frame is
        // accepted from the winner only (other candidates are
        // already cancelled at that point).
        switch frame.body {
        case .authOk(let macName):
            if winner == nil {
                promote(candidate, macName: macName)
            }
        case .authFailed(let reason):
            clientDbg.error("RX authFailed reason=\(reason, privacy: .public) cand=\(candidate.label, privacy: .public)")
            store.connection = .error(message: "Pairing rejected (\(reason))")
            store.bridgeSync = .error("Pairing rejected (\(reason))")
            store.bridgeSyncUpdatedAt = Date()
            cancelAllCandidates()
            stopBrowser()
            CredentialStore.shared.clear()
            creds = nil
        case .versionMismatch:
            clientDbg.error("RX versionMismatch cand=\(candidate.label, privacy: .public)")
            store.connection = .error(message: "Update Clawix on the Mac")
            store.bridgeSync = .error("Update Clawix on the Mac")
            store.bridgeSyncUpdatedAt = Date()
            candidate.connection.cancel()
        case .chatsSnapshot(let chats):
            if winner?.id == candidate.id {
                clientDbg.notice("RX chatsSnapshot count=\(chats.count, privacy: .public) winner=\(candidate.label, privacy: .public)")
                store.applyChatsSnapshot(chats)
                store.persistSnapshotDebounced()
            } else {
                clientDbg.notice("RX chatsSnapshot DROPPED (not winner) cand=\(candidate.label, privacy: .public)")
            }
        case .chatUpdated(let chat):
            if winner?.id == candidate.id {
                clientDbg.notice("RX chatUpdated id=\(chat.id, privacy: .public) hasActiveTurn=\(chat.hasActiveTurn, privacy: .public)")
                store.applyChatUpdate(chat)
                store.persistSnapshotDebounced()
            }
        case .messagesSnapshot(let chatId, let messages, let hasMore):
            if winner?.id == candidate.id {
                clientDbg.notice("RX messagesSnapshot chat=\(chatId, privacy: .public) count=\(messages.count, privacy: .public) hasMore=\(hasMore.map { "\($0)" } ?? "nil", privacy: .public)")
                store.applyMessagesSnapshot(
                    chatId: chatId,
                    messages: messages,
                    hasMore: hasMore
                )
                store.persistSnapshotDebounced()
            }
        case .messagesPage(let chatId, let messages, let hasMore):
            if winner?.id == candidate.id {
                store.applyMessagesPage(
                    chatId: chatId,
                    messages: messages,
                    hasMore: hasMore
                )
                store.persistSnapshotDebounced()
            }
        case .messageAppended(let chatId, let message):
            if winner?.id == candidate.id {
                store.applyMessageAppended(chatId: chatId, message: message)
                store.persistSnapshotDebounced()
            }
        case .messageStreaming(let chatId, let messageId, let content, let reasoning, let finished):
            if winner?.id == candidate.id {
                pendingStreamUpdates[messageId] = PendingStreamUpdate(
                    chatId: chatId,
                    messageId: messageId,
                    content: content,
                    reasoning: reasoning,
                    finished: finished
                )
                if finished {
                    flushPendingStreamUpdates()
                } else if !streamFlushScheduled {
                    streamFlushScheduled = true
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: BridgeClient.streamCoalesceNanos)
                        self?.flushPendingStreamUpdates()
                    }
                }
            }
        case .errorEvent(let code, let message):
            if winner?.id == candidate.id {
                store.connection = .error(message: "\(code): \(message)")
            }
        case .fileSnapshot(let path, let content, let isMarkdown, let error):
            if winner?.id == candidate.id {
                if let content {
                    store.fileSnapshots[path] = .loaded(content: content, isMarkdown: isMarkdown)
                } else {
                    store.fileSnapshots[path] = .failed(reason: error ?? "Unknown error")
                }
            }
        case .transcriptionResult(let requestId, let text, let errorMessage):
            if winner?.id == candidate.id {
                store.applyTranscriptionResult(
                    requestId: requestId,
                    text: text,
                    errorMessage: errorMessage
                )
            }
        case .audioSnapshot(let audioId, let audioBase64, let mimeType, let errorMessage):
            if winner?.id == candidate.id {
                store.applyAudioSnapshot(
                    audioId: audioId,
                    audioBase64: audioBase64,
                    mimeType: mimeType,
                    errorMessage: errorMessage
                )
            }
        case .generatedImageSnapshot(let path, let dataBase64, let mimeType, let errorMessage):
            if winner?.id == candidate.id {
                store.applyGeneratedImageSnapshot(
                    path: path,
                    dataBase64: dataBase64,
                    mimeType: mimeType,
                    errorMessage: errorMessage
                )
            }
        case .bridgeState(let state, let chatCount, let message):
            if winner?.id == candidate.id {
                clientDbg.notice("RX bridgeState state=\(state, privacy: .public) chats=\(chatCount, privacy: .public) msg=\(message ?? "-", privacy: .public)")
                store.applyBridgeState(state: state, message: message)
            }
        case .auth, .listChats, .openChat, .loadOlderMessages,
             .sendPrompt, .newChat,
             .interruptTurn, .readFile, .editPrompt, .archiveChat,
             .unarchiveChat, .pinChat, .unpinChat, .renameChat,
             .pairingStart, .listProjects, .pairingPayload,
             .projectsSnapshot, .transcribeAudio,
             .requestAudio, .requestGeneratedImage,
             .requestRateLimits, .rateLimitsSnapshot, .rateLimitsUpdated:
            // Outbound-from-desktop or server-to-desktop frames the
            // iPhone client neither emits nor consumes. Ignore.
            break
        default:
            // Future bridge capabilities are ignored until iOS wires
            // matching UI/state handling for them.
            break
        }
    }

    /// Apply all pending streaming updates in a single pass. Each
    /// `messageId` mutates `store.messagesByChat[chatId]` once,
    /// regardless of how many chunks arrived during the coalesce
    /// window. The caller must clear `streamFlushScheduled` before
    /// returning so a subsequent chunk re-arms the timer.
    private func flushPendingStreamUpdates() {
        streamFlushScheduled = false
        guard !pendingStreamUpdates.isEmpty else { return }
        // Drain into a snapshot so callers can keep enqueuing onto a
        // fresh dict if a flush re-entry happens (defensive; under
        // current call sites this can't loop, but keeping the apply
        // pass against an immutable copy avoids surprises).
        let updates = pendingStreamUpdates
        pendingStreamUpdates.removeAll(keepingCapacity: true)
        for (_, u) in updates {
            var current = store.messagesByChat[u.chatId] ?? []
            if let idx = current.firstIndex(where: { $0.id == u.messageId }) {
                current[idx].content = u.content
                current[idx].reasoningText = u.reasoning
                current[idx].streamingFinished = u.finished
                store.messagesByChat[u.chatId] = current
            }
        }
    }

    private func promote(_ candidate: Candidate, macName: String?) {
        winner = candidate
        candidate.timeoutWork?.cancel()
        candidate.timeoutWork = nil
        candidates.removeAll { $0.id == candidate.id }
        // Cancel losers.
        for loser in candidates {
            loser.timeoutWork?.cancel()
            loser.connection.cancel()
        }
        candidates.removeAll()
        reconnectAttempt = 0
        store.connection = .connected(macName: macName, via: candidate.route)
        clientDbg.notice("PROMOTE winner=\(candidate.label, privacy: .public) mac=\(macName ?? "?", privacy: .public)")
        startKeepalive()
        send(BridgeFrame(.listChats), on: candidate)
    }

    private func send(_ frame: BridgeFrame, on candidate: Candidate) {
        guard let data = try? BridgeCoder.encode(frame) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "frame",
            metadata: [metadata]
        )
        candidate.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        lastInboundAt = Date()
        let timer = Timer(
            timeInterval: Self.keepalivePingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.keepaliveTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepaliveTimer = timer
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        lastInboundAt = nil
    }

    private func keepaliveTick() {
        guard let winner else { return }
        if let last = lastInboundAt,
           Date().timeIntervalSince(last) > Self.keepaliveDeadAfter {
            // No traffic for too long, kill it. The state handler
            // will then schedule a reconnect and the race restarts.
            winner.connection.cancel()
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(
            identifier: "ping",
            metadata: [metadata]
        )
        winner.connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    // MARK: - Reconnect scheduling

    private func scheduleReconnect() {
        cancelReconnect()
        guard creds != nil else { return }
        reconnectAttempt += 1
        // First few rounds are fast (network just blipped, Mac
        // restarted, etc.); after that exponential backoff up to 16s
        // so we don't drain battery banging on a Mac that's off.
        let delay: Double
        if reconnectAttempt <= 2 {
            delay = 0.5
        } else {
            let exp = pow(2.0, Double(min(reconnectAttempt - 2, 4)))
            delay = min(16.0, exp)
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.startRace()
                if self.reconnectAttempt >= Self.visibleConnectionFailureAfter {
                    let message = self.connectionFailureMessage()
                    self.store.connection = .error(message: message)
                    self.store.bridgeSync = .error(message)
                    self.store.bridgeSyncUpdatedAt = Date()
                }
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func connectionFailureMessage() -> String {
        guard let creds else { return "Pair with your Mac again." }
        if creds.host.isEmpty {
            return "Open Clawix on your Mac and keep both devices on the same network."
        }
        return "Open Clawix on your Mac and check that the bridge is running."
    }

    private func cancelReconnect() {
        reconnectWork?.cancel()
        reconnectWork = nil
    }

    private func cancelAllCandidates() {
        for candidate in candidates {
            candidate.timeoutWork?.cancel()
            candidate.connection.cancel()
        }
        candidates.removeAll()
    }
}

// MARK: - Candidate

@MainActor
private final class Candidate {
    let id = UUID()
    let connection: NWConnection
    let route: BridgeStore.Route
    let label: String
    let endpointKey: String
    var timeoutWork: DispatchWorkItem?

    init(
        connection: NWConnection,
        route: BridgeStore.Route,
        label: String,
        endpointKey: String
    ) {
        self.connection = connection
        self.route = route
        self.label = label
        self.endpointKey = endpointKey
    }
}

// MARK: - Helpers

@MainActor
private func deviceName() -> String {
    #if canImport(UIKit)
    return UIDevice.current.name
    #else
    return "iPhone"
    #endif
}
