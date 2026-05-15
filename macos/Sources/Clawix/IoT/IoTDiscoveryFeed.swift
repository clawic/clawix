import Foundation
import SwiftUI

/// Live feed of devices the daemon's discovery orchestrator surfaces
/// while a scan window is open. The user opens the wizard, starts a scan,
/// and the feed fills with cards as devices arrive over the SSE stream.
///
/// Subscribes to `GET /v1/events/stream` and filters on `event:
/// iot.discovery.found` envelopes. The same stream carries `iot.action.*`
/// and `iot.approval.*` events; each consumer owns its subscription to keep
/// the state machines independent.
@MainActor
final class IoTDiscoveryFeed: NSObject, ObservableObject {

    /// Snapshot of devices the daemon has surfaced during the active
    /// scan window. Ordered by `discoveredAt` ascending so the wizard
    /// shows new arrivals at the bottom.
    @Published private(set) var devices: [DiscoveredDevice] = []

    /// True while the SSE connection is alive. The wizard uses this to
    /// render a "Listening for devices..." progress strip.
    @Published private(set) var isStreaming = false

    /// Last transport error surfaced to the UI. Cleared when the next
    /// successful event arrives.
    @Published private(set) var lastError: String?

    private var task: URLSessionDataTask?
    private var session: URLSession!
    private var buffer = Data()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Connect to the daemon's SSE stream. Idempotent.
    func connect() {
        guard task == nil else { return }
        guard let url = URL(string: "http://127.0.0.1:\(ClawJSService.iot.port)/v1/events/stream") else {
            return
        }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity
        buffer.removeAll()
        task = session.dataTask(with: request)
        task?.resume()
        isStreaming = true
    }

    /// Tear down the SSE connection. Idempotent.
    func disconnect() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    /// Clear the current snapshot. Called by the wizard when the user
    /// restarts a scan so stale devices don't linger.
    func reset() {
        devices = []
        lastError = nil
    }

    fileprivate func ingest(envelope: SSEEnvelope) {
        guard envelope.type == "iot.discovery.found" else { return }
        guard let payload = envelope.payload,
              let deviceData = try? JSONSerialization.data(withJSONObject: payload["device"] ?? [:], options: []),
              let device = try? JSONDecoder().decode(DiscoveredDevice.self, from: deviceData) else {
            return
        }
        if let index = devices.firstIndex(where: { $0.fingerprint == device.fingerprint }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        lastError = nil
    }

    fileprivate func note(error: String) {
        lastError = error
    }
}

// MARK: - SSE parsing

/// One Server-Sent Event after newline-framing.
private struct SSEEnvelope {
    let type: String
    let payload: [String: Any]?
}

extension IoTDiscoveryFeed: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            self?.handleChunk(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.task = nil
            self?.isStreaming = false
            if let message {
                self?.note(error: message)
            }
        }
    }

    private func handleChunk(_ chunk: Data) {
        buffer.append(chunk)
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let raw = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard let envelope = parseEnvelope(raw) else { continue }
            ingest(envelope: envelope)
        }
    }

    private func parseEnvelope(_ data: Data) -> SSEEnvelope? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var event: String?
        var dataLine = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") {
                event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                if !dataLine.isEmpty { dataLine.append("\n") }
                dataLine.append(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        guard let event else { return nil }
        let payload: [String: Any]?
        if dataLine.isEmpty {
            payload = nil
        } else if let bytes = dataLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            payload = json
        } else {
            payload = nil
        }
        return SSEEnvelope(type: event, payload: payload)
    }
}

// MARK: - DiscoveredDevice wire model

/// Mirrors `DiscoveredDevice` from `clawjs/iot/src/server/adapters/types.ts`.
/// Keep aligned when the daemon's shape changes.
struct DiscoveredDevice: Codable, Identifiable, Equatable {
    var id: String { fingerprint }

    let fingerprint: String
    let connectorId: String
    let label: String
    let kind: String
    let targetRef: String
    let risk: String?
    let discoveredAt: String

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.fingerprint == rhs.fingerprint
            && lhs.label == rhs.label
            && lhs.targetRef == rhs.targetRef
    }
}
