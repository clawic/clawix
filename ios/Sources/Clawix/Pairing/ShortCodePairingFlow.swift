import Foundation
import Network
import UIKit
import ClawixCore

/// Bonjour-driven pairing flow that lets the user type the short code
/// from the Mac's `clawix pair` output instead of scanning the QR.
///
/// The daemon advertises `_clawix-bridge._tcp` over Bonjour while
/// running, so this flow can find any Mac on the same Wi-Fi without
/// asking the user for an IP. We open a one-shot WebSocket to that
/// service, send the typed code as the token in the standard auth
/// frame (the daemon accepts either the pairing token or the short
/// code), and on `authOk` produce a `Credentials` value with `host`
/// left empty so `BridgeClient`'s own Bonjour browser keeps resolving
/// the Mac across DHCP and SSID changes.
@MainActor
@Observable
final class ShortCodePairingFlow {

    enum Status: Equatable {
        case idle
        case browsing
        case authenticating
        case error(String)
    }

    struct DiscoveredMac: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint

        static func == (a: DiscoveredMac, b: DiscoveredMac) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    private(set) var discovered: [DiscoveredMac] = []
    private(set) var status: Status = .idle

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var pairConnection: NWConnection?
    @ObservationIgnored private var resultContinuation: CheckedContinuation<Credentials, Error>?
    @ObservationIgnored private var pairingCode: String?
    @ObservationIgnored private var timeoutWork: DispatchWorkItem?

    func startBrowsing() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_clawix-bridge._tcp", domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.applyResults(results) }
        }
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: .main)
        self.browser = browser
        status = .browsing
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        if case .browsing = status { status = .idle }
    }

    private func applyResults(_ results: Set<NWBrowser.Result>) {
        var found: [DiscoveredMac] = []
        for r in results {
            guard case .service(let name, _, _, _) = r.endpoint else { continue }
            if !found.contains(where: { $0.id == name }) {
                found.append(DiscoveredMac(id: name, name: name, endpoint: r.endpoint))
            }
        }
        discovered = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Open a WS to `mac`, send the auth frame with the typed code as
    /// the token field, and resolve the continuation with the
    /// resulting `Credentials` on `authOk`. The connection is closed
    /// either way: long-term traffic flows through `BridgeClient` once
    /// `Credentials` is persisted.
    func pair(with mac: DiscoveredMac, code: String) async throws -> Credentials {
        cleanup()
        status = .authenticating
        pairingCode = code

        let parameters = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        let connection = NWConnection(to: mac.endpoint, using: parameters)
        pairConnection = connection

        return try await withCheckedThrowingContinuation { continuation in
            self.resultContinuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.sendAuth(code: code, on: connection)
                        self.receive(on: connection, mac: mac, code: code)
                    case .failed(let err):
                        self.fail("Could not connect: \(err.localizedDescription)")
                    case .cancelled:
                        if self.resultContinuation != nil {
                            self.fail("Connection cancelled")
                        }
                    default:
                        break
                    }
                }
            }
            connection.start(queue: .main)

            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.resultContinuation != nil {
                        self.fail("Pairing timed out. Make sure the Mac is awake and on the same Wi-Fi.")
                    }
                }
            }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }
    }

    private func sendAuth(code: String, on connection: NWConnection) {
        let frame = BridgeFrame(.auth(
            token: code,
            deviceName: UIDevice.current.name,
            clientKind: .companion,
            clientId: BridgeClientIdentity.clientId,
            installationId: BridgeClientIdentity.installationId,
            deviceId: BridgeClientIdentity.deviceId
        ))
        guard let data = try? BridgeCoder.encode(frame) else {
            fail("Could not encode auth frame")
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "auth", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    private func receive(on connection: NWConnection, mac: DiscoveredMac, code: String) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.fail(error.localizedDescription)
                    return
                }
                if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata {
                    switch metadata.opcode {
                    case .text, .binary: break
                    default:
                        self.rearmReceive(connection: connection, mac: mac, code: code)
                        return
                    }
                }
                guard let data, !data.isEmpty else {
                    self.rearmReceive(connection: connection, mac: mac, code: code)
                    return
                }
                guard let frame = try? BridgeCoder.decode(data) else {
                    self.rearmReceive(connection: connection, mac: mac, code: code)
                    return
                }
                switch frame.body {
                case .authOk(let hostDisplayName):
                    let creds = Credentials(
                        host: "",
                        port: 24080,
                        token: code,
                        hostDisplayName: hostDisplayName ?? mac.name,
                        tailscaleHost: nil
                    )
                    self.complete(creds)
                case .authFailed(let reason):
                    self.fail("Pairing rejected (\(reason)). Check the code and try again.")
                default:
                    self.rearmReceive(connection: connection, mac: mac, code: code)
                }
            }
        }
    }

    private func rearmReceive(connection: NWConnection, mac: DiscoveredMac, code: String) {
        if case .ready = connection.state {
            receive(on: connection, mac: mac, code: code)
        }
    }

    private func complete(_ creds: Credentials) {
        timeoutWork?.cancel()
        timeoutWork = nil
        let cont = resultContinuation
        resultContinuation = nil
        pairConnection?.cancel()
        pairConnection = nil
        status = .idle
        cont?.resume(returning: creds)
    }

    private func fail(_ message: String) {
        timeoutWork?.cancel()
        timeoutWork = nil
        let cont = resultContinuation
        resultContinuation = nil
        pairConnection?.cancel()
        pairConnection = nil
        status = .error(message)
        cont?.resume(throwing: NSError(
            domain: "ShortCodePairingFlow",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
    }

    private func cleanup() {
        timeoutWork?.cancel()
        timeoutWork = nil
        pairConnection?.cancel()
        pairConnection = nil
    }
}
