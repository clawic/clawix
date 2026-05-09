import Foundation

/// WebSocket client for the Drive realtime endpoint (`GET /v1/realtime`).
/// Manages a single subscription to either the active folder, an item, or
/// the global stream. Reconnect with backoff `1/2/4/8/16/60s`. The owner
/// receives decoded `Event`s through the `onEvent` closure.
@MainActor
final class ClawJSDriveRealtimeClient {

    struct Event: Decodable, Equatable {
        let kind: String
        let itemId: String?
        let parentId: String?
        let timestamp: String
    }

    private struct Envelope: Decodable {
        let type: String
        let event: Event?
        let subscriptionId: String?
        let error: String?
    }

    private struct Subscribe: Encodable {
        let type: String = "subscribe"
        let subscriptionId: String
        let filters: Filters
        struct Filters: Encodable {
            let parentId: String?
            let itemId: String?
            let kinds: [String]?
        }
    }

    private struct Pong: Encodable { let type = "pong" }

    private let origin: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var subscriptionId = UUID().uuidString
    private var currentParentId: String?
    private var currentItemId: String?
    private var currentKinds: [String]?
    private var reconnectAttempt = 0
    private var bearerToken: String?
    private var stopped = false

    var onEvent: ((Event) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: ((Swift.Error?) -> Void)?

    init(
        origin: URL = URL(string: "ws://127.0.0.1:7792")!,
        session: URLSession = URLSession(configuration: .default)
    ) {
        self.origin = origin
        self.session = session
    }

    func setToken(_ token: String?) {
        self.bearerToken = token
    }

    func subscribe(parentId: String? = nil, itemId: String? = nil, kinds: [String]? = nil) {
        self.currentParentId = parentId
        self.currentItemId = itemId
        self.currentKinds = kinds
        connect()
    }

    func stop() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() {
        stopped = false
        var components = URLComponents(url: origin.appendingPathComponent("v1/realtime"), resolvingAgainstBaseURL: false)!
        if let token = bearerToken { components.queryItems = [URLQueryItem(name: "token", value: token)] }
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive()
        sendSubscribe()
        onConnect?()
    }

    private func sendSubscribe() {
        let payload = Subscribe(
            subscriptionId: subscriptionId,
            filters: .init(parentId: currentParentId, itemId: currentItemId, kinds: currentKinds),
        )
        guard let task else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8) ?? "")
            task.send(message) { _ in }
        } catch { /* ignored */ }
    }

    private func receive() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receive()
                case .failure(let error):
                    self.scheduleReconnect(error: error)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text, let data = text.data(using: .utf8) else { return }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        if env.type == "ping" {
            sendPong()
        } else if env.type == "event", let event = env.event {
            onEvent?(event)
            reconnectAttempt = 0
        }
    }

    private func sendPong() {
        guard let task else { return }
        if let data = try? JSONEncoder().encode(Pong()), let s = String(data: data, encoding: .utf8) {
            task.send(.string(s)) { _ in }
        }
    }

    private func scheduleReconnect(error: Swift.Error?) {
        onDisconnect?(error)
        if stopped { return }
        let backoffs: [TimeInterval] = [1, 2, 4, 8, 16, 60]
        let delay = backoffs[min(reconnectAttempt, backoffs.count - 1)]
        reconnectAttempt += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if self.stopped { return }
            self.connect()
        }
    }
}
