import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let driveQuickUploadRequested = Notification.Name("clawix.drive.quickUploadRequested")
}

/// Top-level @MainActor orchestrator for the Drive UI. Wraps
/// `ClawJSDriveClient` (HTTP) and `ClawJSDriveRealtimeClient` (WS), owns
/// the auto-login flow, and exposes a SwiftUI-friendly snapshot of items
/// for the active folder + counts + audit tail. Mirrors the philosophy
/// of `VaultManager`: state machine, no hidden globals, all mutations
/// flow through this object so views can drive optimistic updates.
@MainActor
final class DriveManager: ObservableObject {

    enum State: Equatable {
        case loading
        case unauthenticated
        case authenticating
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var counts = ClawJSDriveClient.ViewCounts(myDrive: 0, recent: 0, starred: 0, shared: 0, trash: 0)
    @Published var currentParentId: String? = nil
    @Published var currentView: String = "my-drive"
    @Published var query: String = ""
    @Published var items: [ClawJSDriveClient.DriveItem] = []
    @Published var breadcrumbs: [ClawJSDriveClient.DriveItemDetail.Breadcrumb] = []
    @Published var lastError: String? = nil
    @Published var thumbnailCache: [String: Data] = [:]
    @Published var pendingRefresh: Date = Date()

    let client: ClawJSDriveClient
    let realtime: ClawJSDriveRealtimeClient

    private var refreshTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?

    init(
        client: ClawJSDriveClient? = nil,
        realtime: ClawJSDriveRealtimeClient? = nil,
    ) {
        self.client = client ?? ClawJSDriveClient()
        self.realtime = realtime ?? ClawJSDriveRealtimeClient()
        configureRealtime()
    }

    // MARK: - Lifecycle

    func boot() {
        guard bootstrapTask == nil else { return }
        bootstrapTask = Task { @MainActor in
            await ensureLoggedIn()
            await refresh()
        }
    }

    func ensureLoggedIn() async {
        let email = DriveKeychain.adminEmail()
        guard let password = DriveKeychain.ensureAdminPassword() else {
            self.state = .error("Could not access Keychain for Drive admin password.")
            return
        }
        self.state = .authenticating
        do {
            _ = try await client.login(email: email, password: password)
            self.realtime.setToken(client.bearerToken)
            self.realtime.subscribe()
            self.state = .ready
        } catch ClawJSDriveClient.Error.http(let status, _) where status == 401 {
            // First boot path: server seeded `admin@localhost / admin`. Try to migrate.
            do {
                _ = try await client.login(email: "admin@localhost", password: "admin")
                // Now we own the JWT. The seed admin still uses default creds; in v1
                // we keep the seed account and just store our own password locally.
                // Future: add an endpoint that rotates the password.
                self.realtime.setToken(client.bearerToken)
                self.realtime.subscribe()
                self.state = .ready
            } catch {
                self.state = .error("Drive auth failed: \(error.localizedDescription)")
            }
        } catch {
            self.state = .error("Drive auth failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh

    func refresh() async {
        do {
            async let listing = client.listItems(view: currentView, parentId: currentParentId, query: query.isEmpty ? nil : query)
            async let bootstrap = client.bootstrap()
            let result = try await listing
            self.items = result.items
            self.counts = result.counts
            self.breadcrumbs = result.breadcrumbs
            _ = try? await bootstrap
            self.lastError = nil
            self.pendingRefresh = Date()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Mutations (optimistic where reasonable)

    func setParent(_ parentId: String?) {
        self.currentParentId = parentId
        Task { @MainActor in await refresh() }
    }

    func setView(_ view: String) {
        self.currentView = view
        self.currentParentId = nil
        Task { @MainActor in await refresh() }
    }

    func setQuery(_ query: String) {
        self.query = query
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refresh()
        }
    }

    func createFolder(name: String, parentId: String?) async {
        do {
            _ = try await client.createFolder(name: name, parentId: parentId ?? currentParentId)
            await refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    @discardableResult
    func upload(fileURL: URL, parentId: String?, allowOverwrite: Bool = false) async -> Result<ClawJSDriveClient.DriveItemDetail, ClawJSDriveClient.Error> {
        do {
            let detail = try await client.upload(filePath: fileURL, parentId: parentId ?? currentParentId, duplicatePolicy: allowOverwrite ? nil : "report")
            await refresh()
            return .success(detail)
        } catch let error as ClawJSDriveClient.Error {
            self.lastError = error.localizedDescription
            return .failure(error)
        } catch {
            self.lastError = error.localizedDescription
            return .failure(.transport(error))
        }
    }

    func uploadPasted(_ data: Data, suggestedName: String, mimeType: String, parentId: String?) async {
        do {
            _ = try await client.uploadData(data, fileName: suggestedName, mimeType: mimeType, parentId: parentId ?? currentParentId)
            await refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func trash(_ itemId: String) async {
        do {
            _ = try await client.trashItem(itemId)
            await refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func star(_ itemId: String, starred: Bool) async {
        do {
            _ = try await client.updateItem(itemId, starred: starred)
            await refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func rename(_ itemId: String, newName: String) async {
        do {
            _ = try await client.updateItem(itemId, name: newName)
            await refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Thumbnails

    func thumbnail(for itemId: String, size: Int = 256) async -> Data? {
        if let cached = thumbnailCache[itemId] { return cached }
        do {
            let data = try await client.thumbnailData(itemId, size: size)
            thumbnailCache[itemId] = data
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Realtime wiring

    private func configureRealtime() {
        realtime.onEvent = { [weak self] event in
            guard let self else { return }
            // Refresh listing if event affects current parent or current view.
            if event.parentId == self.currentParentId || event.itemId != nil {
                Task { @MainActor in await self.refresh() }
            }
        }
        realtime.onDisconnect = { _ in /* backoff handled internally */ }
    }
}
