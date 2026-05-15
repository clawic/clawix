import Combine
import Foundation

/// State orchestrator for the Index tab. Owns the loopback HTTP client
/// and exposes `@Published` state SwiftUI binds to. Mirrors
/// `MemoryManager` / `DatabaseManager` (no master-password lock).
@MainActor
final class IndexManager: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var types: [ClawJSIndexClient.EntityType] = []
    @Published private(set) var typeCounts: [String: Int] = [:]
    @Published private(set) var entities: [ClawJSIndexClient.Entity] = []
    @Published private(set) var searches: [ClawJSIndexClient.Search] = []
    @Published private(set) var monitors: [ClawJSIndexClient.Monitor] = []
    @Published private(set) var runs: [ClawJSIndexClient.Run] = []
    @Published private(set) var alerts: [ClawJSIndexClient.Alert] = []
    @Published private(set) var unreadAlerts: Int = 0
    @Published private(set) var tags: [ClawJSIndexClient.Tag] = []
    @Published private(set) var collections: [ClawJSIndexClient.Collection] = []
    @Published var selectedTypeFilter: String? = nil
    @Published var selectedSubtypeFilter: String? = nil
    @Published var fullTextQuery: String = ""

    private var client: ClawJSIndexClient
    private var supervisorObserver: AnyCancellable?

    init() {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
        self.client = ClawJSIndexClient(bearerToken: token)
        attachSupervisorObserver()
    }

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshots in
                guard let self else { return }
                if let snap = snapshots[.index], snap.state.isReady, self.state == .idle {
                    Task { await self.refresh() }
                }
            }
    }

    func ensureToken() {
        if client.bearerToken == nil {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
            client.bearerToken = token
        }
    }

    func surfaceActionError(_ error: Error) {
        state = .error(error.localizedDescription)
    }

    func refresh() async {
        ensureToken()
        state = .loading
        do {
            async let typesTask = client.listTypes()
            async let countsTask = client.countsByType()
            async let searchesTask = client.listSearches()
            async let monitorsTask = client.listMonitors()
            async let runsTask = client.listRuns()
            async let alertsTask = client.listAlerts()
            async let tagsTask = client.listTags()
            async let collectionsTask = client.listCollections()
            let (types, countsResp, searches, monitors, runs, alertsResp, tags, collections) = try await (
                typesTask, countsTask, searchesTask, monitorsTask, runsTask, alertsTask, tagsTask, collectionsTask
            )
            self.types = types
            var countsMap: [String: Int] = [:]
            for entry in countsResp.counts { countsMap[entry.typeName] = entry.total }
            self.typeCounts = countsMap
            self.searches = searches
            self.monitors = monitors
            self.runs = runs
            self.alerts = alertsResp.alerts
            self.unreadAlerts = alertsResp.unread
            self.tags = tags
            self.collections = collections
            await loadEntities()
            for alert in alertsResp.alerts where alert.ackAt == nil {
                let entityTitle = alert.entityId.flatMap { id in
                    self.entities.first { $0.id == id }?.title
                }
                IndexNotificationsBridge.shared.surface(alert, entityTitle: entityTitle)
            }
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func loadEntities() async {
        ensureToken()
        var payload: [String: AnyJSON] = ["limit": .number(500)]
        if let typeFilter = selectedTypeFilter { payload["type"] = .string(typeFilter) }
        do {
            self.entities = try await client.listEntities(payload: payload)
        } catch {
            self.entities = []
        }
    }

    func searchEntitiesFullText() async -> [ClawJSIndexClient.Entity] {
        ensureToken()
        let trimmed = fullTextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entities }
        do {
            struct Response: Decodable { let entities: [ClawJSIndexClient.Entity] }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ClawJSIndexClient.Entity], Swift.Error>) in
                Task {
                    do {
                        let raw = try await client.listEntities(payload: [
                            "limit": .number(200),
                            "type": selectedTypeFilter.map { AnyJSON.string($0) } ?? .null,
                        ].compactMapValues { value -> AnyJSON? in
                            if case .null = value { return nil }
                            return value
                        })
                        continuation.resume(returning: raw.filter { entity in
                            let haystack = (entity.title ?? "") + " " + (entity.sourceUrl ?? "")
                            return haystack.localizedCaseInsensitiveContains(trimmed)
                        })
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            return entities
        }
    }

    func detail(for id: String) async throws -> ClawJSIndexClient.EntityDetailResponse {
        ensureToken()
        return try await client.getEntity(id: id)
    }

    func history(for entityId: String, field: String) async throws -> [ClawJSIndexClient.HistoryPoint] {
        ensureToken()
        return try await client.history(entityId: entityId, field: field)
    }

    @discardableResult
    func createSearch(name: String, type: String?, criteria: [String: AnyJSON], prompt: String?) async throws -> ClawJSIndexClient.Search {
        ensureToken()
        var payload: [String: AnyJSON] = [
            "name": .string(name),
            "criteria": .object(criteria),
        ]
        if let type { payload["type"] = .string(type) }
        if let prompt { payload["promptTemplate"] = .string(prompt) }
        let search = try await client.createSearch(payload: payload)
        searches.insert(search, at: 0)
        return search
    }

    @discardableResult
    func runSearch(id: String) async throws -> ClawJSIndexClient.Run {
        ensureToken()
        let run = try await client.runSearch(id: id)
        runs.insert(run, at: 0)
        return run
    }

    func deleteSearch(id: String) async {
        ensureToken()
        do {
            try await client.deleteSearch(id: id)
            searches.removeAll { $0.id == id }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func createMonitor(searchId: String, cron: String, name: String?, alertRules: [ClawJSIndexClient.AlertRule]) async throws -> ClawJSIndexClient.Monitor {
        ensureToken()
        let rulesJson: [AnyJSON] = alertRules.map { rule in
            var obj: [String: AnyJSON] = [
                "id": .string(rule.id),
                "when": .string(rule.when),
            ]
            if let field = rule.field { obj["field"] = .string(field) }
            if let pct = rule.thresholdPct { obj["thresholdPct"] = .number(pct) }
            if let abs = rule.thresholdAbs { obj["thresholdAbs"] = .number(abs) }
            if let match = rule.match { obj["match"] = match }
            return .object(obj)
        }
        var payload: [String: AnyJSON] = [
            "searchId": .string(searchId),
            "cronExpr": .string(cron),
            "alertRules": .array(rulesJson),
        ]
        if let name { payload["name"] = .string(name) }
        let monitor = try await client.createMonitor(payload: payload)
        monitors.insert(monitor, at: 0)
        return monitor
    }

    @discardableResult
    func fireMonitor(id: String) async throws -> ClawJSIndexClient.Run {
        ensureToken()
        let run = try await client.fireMonitor(id: id)
        runs.insert(run, at: 0)
        return run
    }

    func ackAlert(id: String) async {
        ensureToken()
        do {
            try await client.ackAlert(id: id)
            if let index = alerts.firstIndex(where: { $0.id == id }) {
                let alert = alerts[index]
                if alert.ackAt == nil { unreadAlerts = max(0, unreadAlerts - 1) }
            }
            alerts.removeAll { $0.id == id }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func applyTag(entityId: String, name: String, color: String? = nil) async throws -> ClawJSIndexClient.Tag {
        ensureToken()
        let tag = try await client.applyTag(entityId: entityId, name: name, color: color)
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
        }
        return tag
    }

    @discardableResult
    func createCollection(name: String, description: String? = nil) async throws -> ClawJSIndexClient.Collection {
        ensureToken()
        let collection = try await client.createCollection(name: name, description: description)
        collections.insert(collection, at: 0)
        return collection
    }

    func addToCollection(collectionId: String, entityId: String) async throws {
        ensureToken()
        try await client.addToCollection(collectionId: collectionId, entityId: entityId)
    }
}
