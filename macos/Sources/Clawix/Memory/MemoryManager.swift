import Combine
import Foundation

/// State orchestrator for the Memory tab. Mirrors the role `VaultManager`
/// plays for Secrets: a thin wrapper that owns the HTTP client, exposes
/// `@Published` state for SwiftUI, and routes mutations through the
/// daemon. Memory has no master-password lock, so the state machine is
/// simpler (loading → ready → error).
@MainActor
final class MemoryManager: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var notes: [ClawJSMemoryClient.MemoryNote] = []
    @Published private(set) var captures: [ClawJSMemoryClient.Capture] = []
    @Published private(set) var stats: ClawJSMemoryClient.MemoryStatsResponse?
    @Published private(set) var doctor: ClawJSMemoryClient.DoctorResponse?
    @Published private(set) var lastSearch: ClawJSMemoryClient.SearchResponse?
    @Published var isSearching: Bool = false

    let client: ClawJSMemoryClient
    private var searchTask: Task<Void, Never>?
    private var refreshGeneration: UUID?
    private var supervisorObserver: AnyCancellable?

    init(client: ClawJSMemoryClient = .init()) {
        self.client = client
        attachSupervisorObserver()
    }

    // MARK: - Loading

    /// Refreshes notes + captures + stats in parallel. Marks `state =
    /// .ready` when everything succeeds; flips to `.error` only when
    /// the notes call fails (captures + stats are best-effort).
    func refresh() async {
        state = .loading
        let generation = UUID()
        refreshGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.refreshGeneration == generation else { return }
            if case .loading = self.state {
                self.state = .error("Memory service did not become ready within 8 seconds.")
            }
        }
        do {
            async let notesTask = client.listNotes()
            async let capturesTask: [ClawJSMemoryClient.Capture] = (try? await client.listCaptures()) ?? []
            async let statsTask: ClawJSMemoryClient.MemoryStatsResponse? = (try? await client.stats())
            self.notes = try await notesTask
            self.captures = await capturesTask
            self.stats = await statsTask
            self.state = .ready
            self.refreshGeneration = nil
        } catch let error as ClawJSMemoryClient.Error {
            self.state = .error(error.localizedDescription)
            self.refreshGeneration = nil
        } catch {
            self.state = .error(error.localizedDescription)
            self.refreshGeneration = nil
        }
    }

    /// Just probes the daemon and updates `doctor`. Does not affect
    /// `state` so a doctor refresh from the Settings page does not show
    /// a transient loading shimmer over the list.
    func runDoctor() async {
        doctor = try? await client.doctor()
    }

    // MARK: - Search

    /// Debounced search. Cancels the previous in-flight request and
    /// dispatches a new one after 300 ms of typing pause.
    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isSearching = false
            lastSearch = nil
            return
        }
        searchTask = Task { [client] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self.isSearching = true }
            do {
                let response = try await client.search(query: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.lastSearch = response
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.lastSearch = nil
                    self.isSearching = false
                }
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        lastSearch = nil
        isSearching = false
    }

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots.sink { [weak self] snapshots in
            guard let self, let snap = snapshots[.memory] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                switch self.state {
                case .idle, .error:
                    Task { @MainActor [weak self] in await self?.refresh() }
                case .loading, .ready:
                    break
                }
            case .blocked, .crashed, .daemonUnavailable, .idle, .suspendedForDaemon:
                self.notes = []
                self.captures = []
                self.stats = nil
                self.state = .error(snap.state.unavailableReason ?? "Memory service is unavailable.")
            case .starting:
                if self.state != .ready { self.state = .loading }
            }
        }
    }

    // MARK: - Mutations

    @discardableResult
    func create(_ input: ClawJSMemoryClient.CreateNoteInput) async throws -> ClawJSMemoryClient.CreateNoteResponse {
        let response = try await client.createNote(input)
        await refresh()
        return response
    }

    @discardableResult
    func update(
        id: String,
        patch: ClawJSMemoryClient.UpdateNotePatch,
        editor: String = "user"
    ) async throws -> ClawJSMemoryClient.UpdateNoteResponse {
        let response = try await client.updateNote(id: id, patch: patch, editor: editor)
        await refresh()
        return response
    }

    @discardableResult
    func delete(id: String) async throws -> ClawJSMemoryClient.DeleteNoteResponse {
        let response = try await client.deleteNote(id: id)
        await refresh()
        return response
    }

    @discardableResult
    func promote(captureId: String) async throws -> ClawJSMemoryClient.PromoteResponse {
        let response = try await client.promoteCapture(id: captureId)
        await refresh()
        return response
    }
}
