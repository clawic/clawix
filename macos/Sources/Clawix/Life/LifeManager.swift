import Foundation
import Combine

/// One in-process cache + HTTP client per vertical, keyed by id.
/// All verticals share the same daemon authentication: a bearer token
/// negotiated by the bridge (see `DaemonBridgeClient`).
@MainActor
final class LifeManager: ObservableObject {
    static let shared = LifeManager()

    @Published private(set) var verticals: [String: LifeVerticalState] = [:]
    @Published private(set) var enabledVerticalIds: [String] = LifeManager.loadEnabledIds()
    @Published private(set) var hiddenVerticalIds: Set<String> = LifeManager.loadHiddenIds()

    private let urlSession: URLSession
    private let host: String
    private let portByVertical: [String: Int]
    private let tokenProvider: () -> String?

    init(
        urlSession: URLSession = .shared,
        host: String = "127.0.0.1",
        tokenProvider: @escaping () -> String? = LifeManager.defaultToken
    ) {
        self.urlSession = urlSession
        self.host = host
        var ports: [String: Int] = [:]
        for entry in LifeRegistry.entries {
            if let port = entry.servicePort {
                ports[entry.id] = port
            }
        }
        self.portByVertical = ports
        self.tokenProvider = tokenProvider
    }

    func state(for verticalId: String) -> LifeVerticalState {
        if let existing = verticals[verticalId] {
            return existing
        }
        let fresh = LifeVerticalState(verticalId: verticalId)
        verticals[verticalId] = fresh
        return fresh
    }

    /// Replaces the persisted enabled-set. Caller decides the new order.
    func setEnabled(_ ids: [String]) {
        enabledVerticalIds = ids
        UserDefaults(suiteName: appPrefsSuite)?.set(ids, forKey: "LifeEnabledVerticals")
    }

    /// Toggle whether a vertical is hidden from the sidebar (but still
    /// reachable via Cmd+K or LifeSettings).
    func setHidden(id: String, hidden: Bool) {
        if hidden {
            hiddenVerticalIds.insert(id)
        } else {
            hiddenVerticalIds.remove(id)
        }
        UserDefaults(suiteName: appPrefsSuite)?.set(
            Array(hiddenVerticalIds),
            forKey: "LifeHiddenVerticals"
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

    func deleteObservation(verticalId: String, observationId: String) async {
        guard let url = endpoint(
            for: verticalId,
            path: "observations/\(observationId)"
        ) else { return }
        do {
            let _: DeletedEnvelope = try await delete(url)
            await reloadObservations(for: verticalId, variableId: nil)
        } catch {
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    // MARK: - URL plumbing

    private func endpoint(for verticalId: String, path: String) -> URL? {
        guard let port = portByVertical[verticalId] else { return nil }
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

    private func delete<O: Decodable>(_ url: URL) async throws -> O {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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

    // MARK: - Persistence

    nonisolated private static var appPrefsSuiteName: String { appPrefsSuite }

    nonisolated private static func loadEnabledIds() -> [String] {
        if let stored = UserDefaults(suiteName: appPrefsSuiteName)?.stringArray(
            forKey: "LifeEnabledVerticals"
        ), !stored.isEmpty {
            return stored
        }
        // Default: every Phase-1 vertical visible the first time the app
        // launches. The remaining 70 are reachable from `LifeSettingsView`.
        return [
            "health", "sleep", "workouts", "emotions", "journal",
            "habits", "time-tracking", "goals", "finance", "nutrition"
        ]
    }

    nonisolated private static func loadHiddenIds() -> Set<String> {
        let array = UserDefaults(suiteName: appPrefsSuiteName)?
            .stringArray(forKey: "LifeHiddenVerticals") ?? []
        return Set(array)
    }

    nonisolated static func defaultToken() -> String? {
        UserDefaults(suiteName: "clawix.bridge")?.string(forKey: "ClawixBridge.Bearer.v1")
    }
}

/// Per-vertical state cached in memory while the app is running.
struct LifeVerticalState: Equatable {
    let verticalId: String
    var catalog: [LifeCatalogEntry] = []
    var observations: [LifeObservation] = []
    var lastError: String?
}

struct LifeUpsertObservationInput: Codable {
    var id: String?
    var variableId: String
    var value: LifeObservationValue
    var unitId: String?
    var recordedAt: Double?
    var source: LifeObservationSource?
    var notes: String?
    var sessionId: String?
    var externalId: String?
}

private struct CatalogEnvelope: Decodable {
    let items: [LifeCatalogEntry]
}

private struct ObservationsEnvelope: Decodable {
    let items: [LifeObservation]
}

private struct DeletedEnvelope: Decodable {
    let deleted: Bool
}
