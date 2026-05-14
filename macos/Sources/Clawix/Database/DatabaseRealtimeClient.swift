import Foundation

/// WebSocket client for `GET /v1/realtime`. Subscribes to a single
/// `(namespaceId, collectionName)` at a time and forwards every record
/// event to a SwiftUI consumer via `onEvent`.
///
/// Reconnection: exponential backoff [1, 2, 4, 8, 16] capped at 60s.
/// On reconnect, re-subscribes automatically.
@MainActor
final class DatabaseRealtimeClient: ObservableObject {

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var unreadEvents: Int = 0

    private var task: URLSessionWebSocketTask?
    private var session: URLSession = .shared
    private var origin: URL
    private var bearer: String?
    private var subscription: (namespaceId: String, collection: String)?
    private var reconnectAttempt: Int = 0
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var stopped: Bool = false

    var onEvent: ((DBRecordEvent) -> Void)?

    private static let backoff: [UInt64] = [1, 2, 4, 8, 16, 32, 60]

    init(origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.database.port)")!) {
        self.origin = origin
    }

    func configure(origin: URL, bearer: String?) {
        self.origin = origin
        self.bearer = bearer
    }

    func connect() {
        stopped = false
        guard task == nil else { return }
        guard let bearer else { return }

        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = origin.scheme == "https" ? "wss" : "ws"
        components.path = "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/realtime"
        components.queryItems = [URLQueryItem(name: "token", value: bearer)]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        isConnected = true
        scheduleReceive(on: task)
        scheduleHeartbeat(on: task)

        if let subscription {
            send(subscribeTo: subscription.namespaceId, collection: subscription.collection)
        }
    }

    func subscribe(namespaceId: String, collection: String) {
        let pair = (namespaceId, collection)
        if let current = subscription, current == pair { return }
        subscription = pair
        send(subscribeTo: namespaceId, collection: collection)
    }

    func unsubscribe() {
        subscription = nil
    }

    func disconnect() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    func clearUnread() {
        unreadEvents = 0
    }

    private func send(subscribeTo namespaceId: String, collection: String) {
        guard let task else { return }
        let payload: [String: Any] = [
            "type": "subscribe",
            "namespaceId": namespaceId,
            "collectionName": collection,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { _ in }
    }

    private func scheduleHeartbeat(on task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard self.task === task else { return }
                let payload: [String: Any] = ["type": "ping"]
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let string = String(data: data, encoding: .utf8) {
                    task.send(.string(string)) { _ in }
                }
            }
        }
    }

    private func scheduleReceive(on task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.task === task else { return }
                do {
                    let message = try await task.receive()
                    self.handle(message: message)
                } catch {
                    if !Task.isCancelled {
                        await self.handleDisconnect(error: error)
                    }
                    return
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }
        guard let data = text.data(using: .utf8) else { return }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = raw["type"] as? String else { return }
        if type == "event", let envelope = raw["event"] as? [String: Any] {
            if let bytes = try? JSONSerialization.data(withJSONObject: envelope),
               let event = try? JSONDecoder().decode(DBRecordEvent.self, from: bytes) {
                lastEventAt = Date()
                unreadEvents &+= 1
                onEvent?(event)
            }
        }
        // ignore: hello, subscribed, pong, error (transient)
    }

    private func handleDisconnect(error: Swift.Error?) async {
        isConnected = false
        task = nil
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard !stopped else { return }
        let delaySeconds = Self.backoff[min(reconnectAttempt, Self.backoff.count - 1)]
        reconnectAttempt = min(reconnectAttempt + 1, Self.backoff.count)
        try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        guard !stopped else { return }
        connect()
    }
}
