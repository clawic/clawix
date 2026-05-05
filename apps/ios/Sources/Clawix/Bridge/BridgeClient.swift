import Foundation
import Network
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

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
    private static let keepalivePingInterval: TimeInterval = 15
    private static let keepaliveDeadAfter: TimeInterval = 30

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
        send(BridgeFrame(.openChat(chatId: chatId)), on: winner)
    }

    func sendPrompt(chatId: String, text: String) {
        guard let winner else { return }
        send(BridgeFrame(.sendPrompt(chatId: chatId, text: text)), on: winner)
    }

    func readFile(path: String) {
        guard let winner else { return }
        send(BridgeFrame(.readFile(path: path)), on: winner)
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

        // Direct IPv4 candidates from the QR. Bonjour candidates are
        // added asynchronously by `handleBrowse` as soon as the
        // browser yields a match; we don't block on it.
        if !creds.host.isEmpty, creds.host != "0.0.0.0" {
            let route: BridgeStore.Route = isTailscaleHost(creds.host) ? .tailscale : .lan
            addCandidate(
                endpoint: makeEndpoint(host: creds.host, port: creds.port),
                route: route,
                label: "\(route.rawValue):\(creds.host)"
            )
        }
        if let ts = creds.tailscaleHost, !ts.isEmpty, ts != creds.host {
            addCandidate(
                endpoint: makeEndpoint(host: ts, port: creds.port),
                route: .tailscale,
                label: "tailscale:\(ts)"
            )
        }

        if candidates.isEmpty {
            store.connection = .error(message: "Pairing has no host")
        }
    }

    private func makeEndpoint(host: String, port: Int) -> NWEndpoint {
        // NWProtocolWebSocket clients need a URL endpoint to set the
        // `Host` header and request path of the upgrade GET. With a bare
        // `hostPort` endpoint the upgrade aborts on iOS 26 with
        // ECONNABORTED right after the TCP handshake, even against a
        // server that the same payload reaches fine over Python `ws://`.
        if let url = URL(string: "ws://\(host):\(port)/") {
            return NWEndpoint.url(url)
        }
        return NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? .any
        )
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
                // Active connection died, restart the race.
                winner = nil
                stopKeepalive()
                store.connection = .connecting
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
            store.connection = .error(message: "Update Clawix on the Mac")
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
            store.connection = .error(message: "Pairing rejected (\(reason))")
            cancelAllCandidates()
            stopBrowser()
            CredentialStore.shared.clear()
            creds = nil
        case .versionMismatch:
            store.connection = .error(message: "Update Clawix on the Mac")
            candidate.connection.cancel()
        case .chatsSnapshot(let chats):
            if winner?.id == candidate.id { store.chats = chats }
        case .chatUpdated(let chat):
            if winner?.id == candidate.id {
                if let idx = store.chats.firstIndex(where: { $0.id == chat.id }) {
                    store.chats[idx] = chat
                } else {
                    store.chats.append(chat)
                }
            }
        case .messagesSnapshot(let chatId, let messages):
            if winner?.id == candidate.id {
                store.messagesByChat[chatId] = messages
            }
        case .messageAppended(let chatId, let message):
            if winner?.id == candidate.id {
                store.messagesByChat[chatId, default: []].append(message)
            }
        case .messageStreaming(let chatId, let messageId, let content, let reasoning, let finished):
            if winner?.id == candidate.id {
                var current = store.messagesByChat[chatId] ?? []
                if let idx = current.firstIndex(where: { $0.id == messageId }) {
                    current[idx].content = content
                    current[idx].reasoningText = reasoning
                    current[idx].streamingFinished = finished
                    store.messagesByChat[chatId] = current
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
        case .auth, .listChats, .openChat, .sendPrompt, .readFile,
             .editPrompt, .archiveChat, .unarchiveChat, .pinChat,
             .unpinChat, .pairingStart, .listProjects,
             .pairingPayload, .projectsSnapshot:
            // Outbound-from-desktop or server-to-desktop frames the
            // iPhone client neither emits nor consumes. Ignore.
            break
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
                self?.startRace()
            }
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
