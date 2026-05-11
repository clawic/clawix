import Foundation
import SwiftUI
import Combine

/// Singleton observable manager for the bundled `@clawjs/database`
/// daemon. Mirrors the role of `VaultManager` for the Vault service.
///
/// Owns:
///   - The HTTP client (`DatabaseClient`) with a fresh JWT.
///   - The realtime WebSocket client.
///   - The list of collections discovered in the active namespace.
///   - Per-collection in-memory record caches, refreshed on subscribe.
///
/// State machine:
///   .loading -> .bootstrapping -> .ready
///   any state -> .failed(reason) on hard error
///   .ready re-enters .bootstrapping when the supervisor restarts the
///   daemon (we observe `ClawJSServiceManager` snapshots).
@MainActor
final class DatabaseManager: ObservableObject {

    enum State: Equatable {
        case loading
        case bootstrapping
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?
    @Published private(set) var collections: [DBCollection] = []
    @Published private(set) var currentNamespace: String = "clawix-local"
    @Published private(set) var lastEventAt: Date?

    /// Per-collection record cache. Keys are collection names; values are
    /// the latest list returned by the server (filter-applied) plus any
    /// realtime patches applied since.
    @Published private(set) var recordsByCollection: [String: [DBRecord]] = [:]

    /// Per-collection filter+sort state, persisted in UserDefaults.
    @Published var filterByCollection: [String: DBFilterState] = [:]

    /// In-flight tasks per collection so we can cancel a stale fetch when
    /// the user changes filter quickly.
    private var inFlight: [String: Task<Void, Never>] = [:]

    private(set) var client = DatabaseClient()
    let realtime = DatabaseRealtimeClient()

    private let userDefaults: UserDefaults
    private let filterStateKey = "clawix.database.filterStates.v1"
    private let isDisabled: Bool

    private var supervisorObserver: AnyCancellable?
    private var bootstrapGeneration: UUID?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isDisabled = ProcessInfo.processInfo.environment["CLAWIX_DATABASE_DISABLE"] == "1"
        loadFilterStates()
        realtime.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyEvent(event)
            }
        }
        guard !isDisabled else {
            state = .failed("Database service is disabled for this launch.")
            return
        }
        attachSupervisorObserver()
    }

    /// Observes `ClawJSServiceManager.shared.snapshots[.database]` and
    /// kicks off `bootstrap()` whenever the supervisor flips that service
    /// to `.ready`. If the daemon crashes and gets restarted, we re-issue
    /// `bootstrap()` so we get a fresh JWT, recover the WS subscription,
    /// and reload collections. Cheap: bootstrap is idempotent.
    private func attachSupervisorObserver() {
        let supervisor = ClawJSServiceManager.shared
        supervisorObserver = supervisor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            guard let snap = snapshots[.database] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .ready = self.state { return }
                    await self.bootstrap()
                }
            case .crashed, .blocked, .idle, .daemonUnavailable:
                self.realtime.disconnect()
                self.collections = []
                self.recordsByCollection = [:]
                self.state = .failed(snap.state.unavailableReason ?? "Database service is unavailable.")
            case .starting:
                if case .ready = self.state { self.realtime.disconnect() }
                self.state = .bootstrapping
                break
            }
        }
    }

    // MARK: - Bootstrap

    /// Establishes a JWT-authenticated client and ensures the namespace
    /// exists. Idempotent. Called automatically when the supervisor
    /// flips `database` to `.ready` and on app foregrounding.
    func bootstrap() async {
        guard !isDisabled else { return }
        if case .ready = state { return }
        state = .bootstrapping
        let generation = UUID()
        bootstrapGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootstrapGeneration == generation else { return }
            if case .bootstrapping = self.state {
                self.state = .failed("Database service did not become ready within 8 seconds.")
            }
        }
        do {
            let credential = try DatabaseKeychain.loadOrCreateCredential()
            let response = try await client.bootstrapAdmin(
                email: credential.email,
                password: credential.password
            )
            client.bearerToken = response.accessToken
            _ = try await client.ensureNamespace(id: currentNamespace, displayName: "Clawix Local")
            let collections = try await client.listCollections(namespaceId: currentNamespace)
            self.collections = collections.sorted { lhs, rhs in
                if lhs.builtin != rhs.builtin { return lhs.builtin && !rhs.builtin }
                return lhs.displayName < rhs.displayName
            }
            realtime.configure(
                origin: client.origin,
                bearer: client.bearerToken
            )
            realtime.connect()
            state = .ready
            lastError = nil
            bootstrapGeneration = nil
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            bootstrapGeneration = nil
        }
    }

    // MARK: - Records

    func collection(named name: String) -> DBCollection? {
        collections.first(where: { $0.name == name })
    }

    func filterState(for collection: String) -> DBFilterState {
        filterByCollection[collection] ?? DBFilterState()
    }

    func setFilterState(_ state: DBFilterState, for collection: String) {
        filterByCollection[collection] = state
        persistFilterStates()
        Task { await refreshRecords(collection: collection) }
    }

    func refreshRecords(collection name: String) async {
        guard let _ = collection(named: name) else { return }
        guard case .ready = state else { return }
        let filter = filterState(for: name)
        inFlight[name]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.client.listRecords(
                    namespaceId: self.currentNamespace,
                    collection: name,
                    filter: filter.backendFilterJSON(),
                    sort: filter.sortString(),
                    limit: 500
                )
                let post = filter.clientSidePostFilter(records: response.items)
                self.recordsByCollection[name] = post
            } catch {
                self.lastError = error.localizedDescription
            }
        }
        inFlight[name] = task
        _ = await task.value
    }

    func subscribeRealtime(collection name: String) {
        realtime.subscribe(namespaceId: currentNamespace, collection: name)
    }

    func createRecord(collection name: String, data: [String: DBJSON]) async throws -> DBRecord {
        let record = try await client.createRecord(
            namespaceId: currentNamespace,
            collection: name,
            data: data
        )
        var current = recordsByCollection[name] ?? []
        current.insert(record, at: 0)
        recordsByCollection[name] = current
        return record
    }

    func updateRecord(
        collection name: String,
        id: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let updated = try await client.updateRecord(
            namespaceId: currentNamespace,
            collection: name,
            id: id,
            data: data
        )
        if var current = recordsByCollection[name], let index = current.firstIndex(where: { $0.id == id }) {
            current[index] = updated
            recordsByCollection[name] = current
        }
        return updated
    }

    func deleteRecord(collection name: String, id: String) async throws {
        try await client.deleteRecord(namespaceId: currentNamespace, collection: name, id: id)
        if var current = recordsByCollection[name] {
            current.removeAll { $0.id == id }
            recordsByCollection[name] = current
        }
    }

    func archiveRecord(collection name: String, id: String) async throws {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        _ = try await updateRecord(
            collection: name,
            id: id,
            data: ["archivedAt": .string(nowIso)]
        )
    }

    func restoreRecord(collection name: String, id: String) async throws {
        _ = try await updateRecord(
            collection: name,
            id: id,
            data: ["archivedAt": .null]
        )
    }

    /// Returns a flat list of records with the current filter applied
    /// (server-side + client-side post filter). Used by views.
    func records(for collection: String) -> [DBRecord] {
        recordsByCollection[collection] ?? []
    }

    // MARK: - Realtime

    private func applyEvent(_ event: DBRecordEvent) {
        guard event.namespaceId == currentNamespace else { return }
        let name = event.collectionName
        var current = recordsByCollection[name] ?? []
        switch event.type {
        case .created:
            if let record = event.record, !current.contains(where: { $0.id == record.id }) {
                current.insert(record, at: 0)
            }
        case .updated:
            if let record = event.record {
                if let index = current.firstIndex(where: { $0.id == record.id }) {
                    current[index] = record
                } else {
                    current.insert(record, at: 0)
                }
            }
        case .deleted:
            current.removeAll { $0.id == event.recordId }
        }
        recordsByCollection[name] = current
        lastEventAt = Date()
    }

    // MARK: - Persistence

    private func loadFilterStates() {
        guard let data = userDefaults.data(forKey: filterStateKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: DBFilterState].self, from: data) {
            filterByCollection = decoded
        }
    }

    private func persistFilterStates() {
        if let data = try? JSONEncoder().encode(filterByCollection) {
            userDefaults.set(data, forKey: filterStateKey)
        }
    }
}
