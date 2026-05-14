import Foundation
import Combine

private enum LifePersistentKeys {
    static let enabledVerticalsDefaultsKey = "LifeEnabledVerticals"
    static let hiddenVerticalsDefaultsKey = "LifeHiddenVerticals"
    static let bridgeBearerDefaultsKey = "ClawixBridge.Bearer.v1"
    static let bridgeHostDefaultsKey = "ClawixBridge.Host.v1"
}

@MainActor
final class LifeManager: ObservableObject {
    static let shared = LifeManager()

    @Published private(set) var verticals: [String: LifeVerticalState] = [:]
    @Published private(set) var enabledVerticalIds: [String]
    @Published private(set) var hiddenVerticalIds: Set<String>

    private let urlSession: URLSession
    private let portByVertical: [String: Int]
    private let hostProvider: () -> String?
    private let tokenProvider: () -> String?

    init(
        urlSession: URLSession = .shared,
        hostProvider: @escaping () -> String? = LifeManager.defaultHost,
        tokenProvider: @escaping () -> String? = LifeManager.defaultToken
    ) {
        self.urlSession = urlSession
        var ports: [String: Int] = [:]
        for entry in LifeRegistry.entries {
            if let port = entry.servicePort {
                ports[entry.id] = port
            }
        }
        self.portByVertical = ports
        self.hostProvider = hostProvider
        self.tokenProvider = tokenProvider
        self.enabledVerticalIds = LifeManager.loadEnabledIds()
        self.hiddenVerticalIds = LifeManager.loadHiddenIds()
    }

    func state(for verticalId: String) -> LifeVerticalState {
        if let existing = verticals[verticalId] { return existing }
        let fresh = LifeVerticalState(verticalId: verticalId)
        verticals[verticalId] = fresh
        return fresh
    }

    func setEnabled(_ ids: [String]) {
        enabledVerticalIds = ids
        UserDefaults.standard.set(ids, forKey: LifePersistentKeys.enabledVerticalsDefaultsKey)
    }

    func setHidden(id: String, hidden: Bool) {
        if hidden { hiddenVerticalIds.insert(id) } else { hiddenVerticalIds.remove(id) }
        UserDefaults.standard.set(
            Array(hiddenVerticalIds),
            forKey: LifePersistentKeys.hiddenVerticalsDefaultsKey
        )
    }

    // MARK: - Network

    func reloadCatalog(for verticalId: String) async {
        guard let url = endpoint(for: verticalId, path: "catalog") else { return }
        do {
            let envelope: CatalogEnvelope = try await get(url)
            var entry = state(for: verticalId)
            entry.catalog = envelope.items
            verticals[verticalId] = entry
        } catch {
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func reloadObservations(
        for verticalId: String,
        variableId: String?,
        limit: Int = 200
    ) async {
        var components = URLComponents()
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        if let variableId {
            queryItems.append(URLQueryItem(name: "variableId", value: variableId))
        }
        components.queryItems = queryItems
        guard let suffix = components.url?.query else { return }
        guard let url = endpoint(for: verticalId, path: "observations?\(suffix)") else { return }
        do {
            let envelope: ObservationsEnvelope = try await get(url)
            var entry = state(for: verticalId)
            entry.observations = envelope.items
            verticals[verticalId] = entry
        } catch {
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func upsertObservation(
        verticalId: String,
        input: LifeUpsertObservationInput
    ) async {
        guard let url = endpoint(for: verticalId, path: "observations") else { return }
        do {
            let _: LifeObservation = try await post(url, body: input)
            await reloadObservations(for: verticalId, variableId: input.variableId)
        } catch {
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func bulkUpsertObservations(
        verticalId: String,
        inputs: [LifeUpsertObservationInput]
    ) async {
        guard let url = endpoint(for: verticalId, path: "observations/bulk") else { return }
        do {
            let body = BulkBody(items: inputs)
            let _: BulkEnvelope = try await post(url, body: body)
        } catch {
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    // MARK: - URL plumbing

    private func endpoint(for verticalId: String, path: String) -> URL? {
        guard let port = portByVertical[verticalId] else { return nil }
        guard let host = hostProvider() else { return nil }
        return URL(string: "http://\(host):\(port)/v1/\(verticalId)/\(path)")
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data: data, url: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<I: Encodable, O: Decodable>(_ url: URL, body: I) async throws -> O {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data: data, url: url)
        return try JSONDecoder().decode(O.self, from: data)
    }

    private static func check(_ response: URLResponse, data: Data, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "LifeManager",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode) on \(url.absoluteString)"
                ]
            )
        }
    }

    nonisolated private static func loadEnabledIds() -> [String] {
        if let stored = UserDefaults.standard.stringArray(forKey: LifePersistentKeys.enabledVerticalsDefaultsKey),
           !stored.isEmpty {
            return stored
        }
        return [
            "health", "sleep", "workouts", "emotions", "journal",
            "habits", "time-tracking", "goals", "finance", "nutrition"
        ]
    }

    nonisolated private static func loadHiddenIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: LifePersistentKeys.hiddenVerticalsDefaultsKey) ?? [])
    }

    nonisolated static func defaultToken() -> String? {
        UserDefaults.standard.string(forKey: LifePersistentKeys.bridgeBearerDefaultsKey)
    }

    nonisolated static func defaultHost() -> String? {
        UserDefaults.standard.string(forKey: LifePersistentKeys.bridgeHostDefaultsKey)
    }
}

struct LifeVerticalState: Equatable {
    let verticalId: String
    var catalog: [LifeCatalogEntry] = []
    var observations: [LifeObservation] = []
    var lastError: String?
}

private struct CatalogEnvelope: Decodable {
    let items: [LifeCatalogEntry]
}

private struct ObservationsEnvelope: Decodable {
    let items: [LifeObservation]
}

private struct BulkEnvelope: Decodable {
    let count: Int
}

private struct BulkBody: Encodable {
    let items: [LifeUpsertObservationInput]
}
