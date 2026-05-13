import Foundation
import SwiftUI
import Combine

/// Top-level `@MainActor` observable for the Publishing UI. Wraps the typed
/// HTTP client and watches `ClawJSServiceManager` for liveness transitions
/// so views can react when the helper crashes / restarts. Mirrors the
/// philosophy of `DriveManager` / `SecretsManager`: one state machine, no
/// hidden globals, all mutations flow through this object.
@MainActor
final class PublishingManager: ObservableObject {

    enum State: Equatable {
        case idle
        case bootstrapping
        case ready
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var workspaceId: String?
    @Published private(set) var families: [ClawJSPublishingClient.Family] = []
    @Published private(set) var channels: [ClawJSPublishingClient.ChannelAccount] = []
    @Published private(set) var posts: [ClawJSPublishingClient.Post] = []
    @Published private(set) var lastError: String?

    let client: ClawJSPublishingClient

    private static let workspaceKey = "clawix.publishing.workspaceId.v1"

    private var bootstrapTask: Task<Void, Never>?
    private var supervisorObserver: AnyCancellable?

    init(client: ClawJSPublishingClient? = nil) {
        self.client = client ?? ClawJSPublishingClient()
        let stored = UserDefaults.standard.string(forKey: Self.workspaceKey)
        self.workspaceId = (stored?.isEmpty == false) ? stored : nil
        self.client.workspaceId = self.workspaceId
        attachSupervisorObserver()
    }

    // MARK: - Lifecycle

    /// Loads the admin token from the daemon's `.admin-token` file and
    /// resolves (or creates) the "Default" workspace. Idempotent: re-entry
    /// while a bootstrap is in flight is a no-op.
    func bootstrap() {
        guard bootstrapTask == nil else { return }
        let snapshot = ClawJSServiceManager.shared.snapshots[.publishing]
        guard snapshot?.state.isReady == true else {
            state = .unavailable(snapshot?.state.unavailableReason ?? "Publishing service is not running.")
            return
        }
        state = .bootstrapping
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.bootstrapTask = nil }
            do {
                let token = try ClawJSServiceManager.adminTokenFromDataDir(for: .publishing)
                self.client.bearerToken = token
                try await self.ensureDefaultWorkspace()
                async let families = self.client.listFamilies()
                async let channels = self.client.listChannels(workspaceId: self.workspaceId ?? "")
                self.families = (try? await families) ?? []
                self.channels = (try? await channels) ?? []
                self.state = .ready
                self.lastError = nil
            } catch {
                self.state = .unavailable(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Drops any in-memory state. Used when the supervisor reports the
    /// service is down so views render an empty state instead of stale
    /// data from a previous boot.
    func reset(reason: String) {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        families = []
        channels = []
        posts = []
        state = .unavailable(reason)
    }

    private func ensureDefaultWorkspace() async throws {
        if let id = workspaceId, !id.isEmpty {
            client.workspaceId = id
            // Confirm it still exists; if the daemon was wiped between
            // launches the stored id will dangle.
            let workspaces = try await client.listWorkspaces()
            if workspaces.contains(where: { $0.id == id }) { return }
        }
        let workspaces = try await client.listWorkspaces()
        let resolved: ClawJSPublishingClient.Workspace
        if let existing = workspaces.first {
            resolved = existing
        } else {
            resolved = try await client.createWorkspace(name: "Default")
        }
        workspaceId = resolved.id
        client.workspaceId = resolved.id
        UserDefaults.standard.set(resolved.id, forKey: Self.workspaceKey)
    }

    // MARK: - Refresh

    func refreshFamilies() async {
        guard state == .ready else { return }
        do {
            families = try await client.listFamilies()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshChannels() async {
        guard let workspaceId, state == .ready else { return }
        do {
            channels = try await client.listChannels(workspaceId: workspaceId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCalendar(from: Date, to: Date) async {
        guard let workspaceId, state == .ready else { return }
        do {
            posts = try await client.listPosts(workspaceId: workspaceId, from: from, to: to)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mutations

    func connect(familyId: String, payload: [String: String]) async throws -> ClawJSPublishingClient.ChannelAccount {
        guard let workspaceId else { throw ClawJSPublishingClient.Error.serviceNotReady }
        let account = try await client.connectChannel(
            workspaceId: workspaceId,
            familyId: familyId,
            payload: payload
        )
        channels.append(account)
        return account
    }

    func disconnect(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        do {
            _ = try await client.disconnectChannel(workspaceId: workspaceId, accountId: account.id)
            channels.removeAll { $0.id == account.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func probe(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        do {
            _ = try await client.probeChannel(workspaceId: workspaceId, accountId: account.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createPost(spec: ClawJSPublishingClient.PostSpec) async throws -> ClawJSPublishingClient.Post {
        guard let workspaceId else { throw ClawJSPublishingClient.Error.serviceNotReady }
        let post = try await client.createPost(workspaceId: workspaceId, spec: spec)
        posts.append(post)
        return post
    }

    // MARK: - Supervisor wiring

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots.sink { [weak self] snapshots in
            guard let self, let snap = snapshots[.publishing] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                if self.state == .idle || self.state == .bootstrapping {
                    self.bootstrap()
                } else if case .unavailable = self.state {
                    self.bootstrap()
                }
            case .blocked, .crashed, .daemonUnavailable:
                self.reset(reason: snap.state.unavailableReason ?? "Publishing service is unavailable.")
            case .idle:
                if self.state != .idle {
                    self.reset(reason: "Publishing service has not started yet.")
                }
            case .starting:
                if case .ready = self.state {
                    // keep current state until the next ready flip
                } else {
                    self.state = .bootstrapping
                }
            }
        }
    }
}
