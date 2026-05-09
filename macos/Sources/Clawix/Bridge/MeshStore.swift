import Foundation
import Combine
import ClawixCore

// State container for the Remote Agent Mesh feature on macOS. Owns the
// HTTP client, the cached identity / peers / workspaces lists, and the
// active outbound jobs. Refresh on demand from the Settings page or the
// composer pill — there is no push channel from the daemon for the v1
// surface, so polling lives here.
@MainActor
final class MeshStore: ObservableObject {

    // MARK: - Published surface (drives the UI)

    @Published private(set) var identity: NodeIdentity?
    @Published private(set) var peers: [PeerRecord] = []
    @Published private(set) var workspaces: [RemoteWorkspace] = []
    /// Last error from a refresh / mutation, surfaced as a toast or
    /// banner. Reset by the next successful call.
    @Published var lastError: String?
    @Published private(set) var isRefreshing = false

    /// Outbound remote jobs the user fired from this Mac, keyed by
    /// `jobId`. Drives the "remote run" card in chat. Each entry has
    /// its own poll task tracked in `pollers`.
    @Published private(set) var activeJobs: [String: RemoteJobUIState] = [:]

    /// Pending pairing flow result so the Settings page can show a
    /// success/error banner inline. Cleared when the form is reopened.
    @Published var lastPairingResult: PairingResult?

    /// Per-peer "remote workspace path" the user has typed in
    /// Settings. Stored in UserDefaults so it survives relaunches.
    /// Sent verbatim as `workspacePath` in `/mesh/remote-jobs`. The
    /// remote daemon validates it against its own allowlist; failure
    /// surfaces as a `workspaceDenied` error.
    @Published private(set) var defaultRemoteWorkspaces: [String: String] = [:]

    // MARK: - Private

    private let client: MeshClient
    private var pollers: [String: Task<Void, Never>] = [:]
    private static let workspacesDefaultsKey = "ClawixMesh.RemoteWorkspaces.v1"

    enum PairingResult: Equatable {
        case success(displayName: String)
        case failure(message: String)
    }

    /// `client` is overridable so the E2E suite can plug a fake daemon
    /// running on a port other than 7779. Production code uses the
    /// no-arg form.
    init(client: MeshClient = MeshClient()) {
        self.client = client
        self.defaultRemoteWorkspaces = Self.loadRemoteWorkspaces()
    }

    deinit {
        for task in pollers.values { task.cancel() }
    }

    // MARK: - Refresh

    /// Pull identity, peers and workspaces from the daemon in
    /// parallel. Called once on Settings page appear and on manual
    /// refresh. If the daemon is unreachable, surface that as
    /// `lastError` and leave the cached lists alone.
    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let id = try? client.identity()
        async let pp = try? client.peers()
        async let ws = try? client.workspaces()
        let (identity, peers, workspaces) = await (id, pp, ws)
        if let identity { self.identity = identity }
        if let peers { self.peers = peers }
        if let workspaces { self.workspaces = workspaces }
        if identity == nil && peers == nil && workspaces == nil {
            self.lastError = MeshClientError.daemonUnreachable.localizedDescription
        } else {
            self.lastError = nil
        }
    }

    /// Lightweight refresh of just the peers list. Used by the
    /// composer pill before opening the dropdown so the freshly added
    /// peer shows up without a full reload.
    func refreshPeers() async {
        do {
            self.peers = try await client.peers()
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Pairing

    func pair(host: String, httpPort: Int, token: String, profile: PeerPermissionProfile) async {
        do {
            let peer = try await client.link(host: host, httpPort: httpPort, token: token, profile: profile)
            // Optimistic update: drop in (or replace) the freshly
            // linked peer so the list refreshes immediately even
            // before the next /mesh/peers fetch lands.
            if let idx = peers.firstIndex(where: { $0.nodeId == peer.nodeId }) {
                peers[idx] = peer
            } else {
                peers.append(peer)
            }
            lastPairingResult = .success(displayName: peer.displayName)
            await refreshPeers()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastPairingResult = .failure(message: message)
        }
    }

    // MARK: - Workspaces (local allowlist)

    func addWorkspace(path: String, label: String? = nil) async {
        do {
            _ = try await client.addWorkspace(path: path, label: label)
            self.workspaces = try await client.workspaces()
            self.lastError = nil
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Per-peer remote workspace memory

    /// Look up the saved remote workspace path for a peer. Empty
    /// string means "not set" — the composer surfaces an inline error
    /// asking the user to configure one before sending.
    func remoteWorkspace(for peerNodeId: String) -> String {
        defaultRemoteWorkspaces[peerNodeId] ?? ""
    }

    func setRemoteWorkspace(_ path: String, for peerNodeId: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaultRemoteWorkspaces.removeValue(forKey: peerNodeId)
        } else {
            defaultRemoteWorkspaces[peerNodeId] = trimmed
        }
        Self.saveRemoteWorkspaces(defaultRemoteWorkspaces)
    }

    // MARK: - Remote jobs

    /// Fire a prompt at `peer`. Inserts an entry in `activeJobs` with
    /// `queued`/`running` status and starts a poller. The caller is
    /// expected to reflect the same prompt in the chat transcript so
    /// the user sees what they asked.
    @discardableResult
    func startRemoteJob(
        peer: PeerRecord,
        workspacePath: String,
        prompt: String,
        chatId: UUID?
    ) async -> Result<RemoteJobUIState, MeshClientError> {
        do {
            let job = try await client.startRemoteJob(
                peerId: peer.nodeId,
                workspacePath: workspacePath,
                prompt: prompt
            )
            let ui = RemoteJobUIState(
                id: job.id,
                chatId: chatId,
                peerNodeId: peer.nodeId,
                peerDisplayName: peer.displayName,
                workspacePath: workspacePath,
                prompt: prompt,
                status: job.status,
                resultText: job.resultText ?? "",
                events: [],
                errorMessage: job.errorMessage,
                startedAt: job.createdAt
            )
            activeJobs[job.id] = ui
            startPolling(jobId: job.id)
            return .success(ui)
        } catch let err as MeshClientError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }

    func cancelPolling(for jobId: String) {
        pollers[jobId]?.cancel()
        pollers[jobId] = nil
    }

    func clearJob(_ jobId: String) {
        cancelPolling(for: jobId)
        activeJobs.removeValue(forKey: jobId)
    }

    /// All active jobs that belong to a given chat. The chat view
    /// uses this to render any pending remote-run cards above the
    /// composer.
    func jobs(forChat chatId: UUID) -> [RemoteJobUIState] {
        activeJobs.values
            .filter { $0.chatId == chatId }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private func startPolling(jobId: String) {
        cancelPolling(for: jobId)
        let task = Task { [weak self] in
            // Poll every second. Back off to 3s once the job reaches a
            // terminal state — the UI keeps the card around for a few
            // seconds so the user can read the final result, then
            // they can dismiss it manually. We do not auto-clear so
            // the chat history stays inspectable.
            var interval: Duration = .milliseconds(800)
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let snapshot = try await self.client.job(id: jobId)
                    await MainActor.run {
                        self.applyPoll(jobId: jobId, snapshot: snapshot)
                    }
                    if let job = snapshot.job, Self.isTerminal(job.status) {
                        // Bumped poll for one more cycle so any final
                        // event that landed after the terminal status
                        // write makes it into the UI.
                        interval = .seconds(3)
                    }
                } catch {
                    // Daemon momentarily unreachable; back off but
                    // keep retrying so the card auto-recovers when
                    // the bridge comes back up. Surface the error
                    // text on the job so the UI can warn.
                    await MainActor.run {
                        self.activeJobs[jobId]?.transientError =
                            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                    interval = .seconds(2)
                }
                try? await Task.sleep(for: interval)
            }
        }
        pollers[jobId] = task
    }

    private func applyPoll(jobId: String, snapshot: MeshClient.JobOutput) {
        guard var entry = activeJobs[jobId] else { return }
        if let job = snapshot.job {
            entry.status = job.status
            if let text = job.resultText, !text.isEmpty {
                entry.resultText = text
            }
            entry.errorMessage = job.errorMessage
        }
        // Events from the daemon are append-only; preserve insertion
        // order and merge by id so a re-poll doesn't duplicate.
        let known = Set(entry.events.map(\.id))
        let fresh = snapshot.events.filter { !known.contains($0.id) }
        entry.events.append(contentsOf: fresh)
        entry.transientError = nil
        activeJobs[jobId] = entry
        if Self.isTerminal(entry.status) {
            // Stop the poller after one more grace cycle (handled by
            // the loop's interval bump above).
        }
    }

    private static func isTerminal(_ status: RemoteJobStatus) -> Bool {
        switch status {
        case .completed, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }

    // MARK: - UserDefaults plumbing

    private static func loadRemoteWorkspaces() -> [String: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: workspacesDefaultsKey) as? [String: String] else {
            return [:]
        }
        return raw
    }

    private static func saveRemoteWorkspaces(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: workspacesDefaultsKey)
    }
}

// MARK: - UI state model

struct RemoteJobUIState: Identifiable, Equatable {
    let id: String
    let chatId: UUID?
    let peerNodeId: String
    let peerDisplayName: String
    let workspacePath: String
    let prompt: String
    var status: RemoteJobStatus
    var resultText: String
    var events: [RemoteJobEvent]
    var errorMessage: String?
    var transientError: String?
    var startedAt: Date

    var isTerminal: Bool {
        switch status {
        case .completed, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }

    var statusLabel: String {
        switch status {
        case .queued:    return "Queued"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
