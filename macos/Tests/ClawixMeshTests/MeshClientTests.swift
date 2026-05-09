import XCTest
import ClawixCore
@testable import Clawix

/// E2E coverage for the macOS Remote Agent Mesh UI plumbing using a
/// fake daemon — no real Codex prompts, no network beyond loopback.
/// Each test boots `FakeMeshDaemon` on a random port, points
/// `MeshClient` at it via the same UserDefaults override the explorer
/// uses, and asserts the published state in `MeshStore` evolves the
/// way the UI expects.
final class MeshClientTests: XCTestCase {

    var daemon: FakeMeshDaemon!

    override func tearDown() {
        daemon?.stop()
        daemon = nil
        UserDefaults.standard.removeObject(forKey: MeshClient.httpPortDefaultsKey)
        super.tearDown()
    }

    // MARK: - Identity / Peers / Workspaces

    func test_identity_decodesNodeIdentity() async throws {
        let identity = MeshTestFixtures.nodeIdentity()
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("GET", "/mesh/identity"):
                return try! .json(identity)
            default:
                return .text("not found", status: 404)
            }
        }
        let client = makeClient()
        let result = try await client.identity()
        XCTAssertEqual(result.nodeId, identity.nodeId)
        XCTAssertEqual(result.displayName, identity.displayName)
        XCTAssertEqual(result.endpoints.count, identity.endpoints.count)
    }

    func test_peers_decodesEnvelope() async throws {
        let peer = MeshTestFixtures.peer()
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("GET", "/mesh/peers"):
                return try! .json(["peers": [peer]])
            default:
                return .text("not found", status: 404)
            }
        }
        let result = try await makeClient().peers()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.nodeId, peer.nodeId)
        XCTAssertEqual(result.first?.permissionProfile, .scoped)
    }

    func test_workspaces_decodesEnvelope() async throws {
        let ws = MeshTestFixtures.workspace()
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("GET", "/mesh/workspaces"):
                return try! .json(["workspaces": [ws]])
            default:
                return .text("not found", status: 404)
            }
        }
        let result = try await makeClient().workspaces()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, ws.path)
    }

    // MARK: - Pairing flow

    func test_link_returnsPeer() async throws {
        let peer = MeshTestFixtures.peer(nodeId: "node-linked", displayName: "Linked Mac")
        var sawLinkBody: Data?
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("POST", "/mesh/link"):
                sawLinkBody = req.body
                return try! .json(["peer": peer])
            default:
                return .text("not found", status: 404)
            }
        }
        let result = try await makeClient().link(host: "192.168.1.20", httpPort: 7779, token: "TOKEN-1", profile: .scoped)
        XCTAssertEqual(result.nodeId, "node-linked")
        XCTAssertNotNil(sawLinkBody)
        let echoed = try JSONDecoder().decode([String: AnyCodable].self, from: sawLinkBody!)
        XCTAssertEqual(echoed["host"]?.value as? String, "192.168.1.20")
        XCTAssertEqual(echoed["token"]?.value as? String, "TOKEN-1")
    }

    // MARK: - Workspace add (allowlist)

    func test_addWorkspace_postsAndReturns() async throws {
        let added = MeshTestFixtures.workspace(path: "/tmp/foo", label: "scratch")
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("POST", "/mesh/workspaces"):
                return try! .json(["workspace": added])
            default:
                return .text("not found", status: 404)
            }
        }
        let result = try await makeClient().addWorkspace(path: "/tmp/foo", label: "scratch")
        XCTAssertEqual(result.path, "/tmp/foo")
        XCTAssertEqual(result.label, "scratch")
    }

    // MARK: - Remote-job dispatch + polling

    func test_remoteJob_dispatchesAndPolls() async throws {
        let peer = MeshTestFixtures.peer(nodeId: "node-remote", displayName: "Remote Mac")
        let initialJob = RemoteJob(
            id: "job-1",
            requesterNodeId: "node-this",
            workspacePath: "/Users/me/Projects/foo",
            prompt: "do work",
            status: .running
        )
        let completedJob = RemoteJob(
            id: "job-1",
            requesterNodeId: "node-this",
            workspacePath: "/Users/me/Projects/foo",
            prompt: "do work",
            status: .completed,
            resultText: "All done"
        )
        let evt = RemoteJobEvent(jobId: "job-1", type: "delta", message: "step 1")
        let stage = AtomicCounter()
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("POST", "/mesh/remote-jobs"):
                return try! .json(["job": initialJob])
            case ("GET", "/mesh/jobs/job-1"):
                let calls = stage.incrementAndGet()
                if calls == 1 {
                    return try! .json(JobSnapshot(job: initialJob, events: [evt]))
                } else {
                    return try! .json(JobSnapshot(job: completedJob, events: [evt]))
                }
            default:
                return .text("not found", status: 404)
            }
        }

        let store = await MainActor.run { MeshStore(client: makeClient()) }
        let chatId = UUID()
        let result = await store.startRemoteJob(
            peer: peer,
            workspacePath: "/Users/me/Projects/foo",
            prompt: "do work",
            chatId: chatId
        )
        switch result {
        case .success(let ui):
            XCTAssertEqual(ui.id, "job-1")
            XCTAssertEqual(ui.status, .running)
            XCTAssertEqual(ui.peerDisplayName, "Remote Mac")
        case .failure(let error):
            XCTFail("expected success, got \(error)")
        }

        // Wait for polling to upgrade the job to `.completed`. The
        // poller runs every 800ms; give it 4s of grace.
        try await waitFor(timeout: 4) {
            await store.activeJobs["job-1"]?.status == .completed
        }
        let final = await store.activeJobs["job-1"]
        XCTAssertEqual(final?.resultText, "All done")
        XCTAssertEqual(final?.events.first?.message, "step 1")
        await MainActor.run { store.cancelPolling(for: "job-1") }
    }

    // MARK: - Errors

    func test_workspaceDenied_isMappedToTypedError() async throws {
        try bootDaemon { req in
            switch (req.method, req.path) {
            case ("POST", "/mesh/remote-jobs"):
                return .text("workspace is denied on this host", status: 400)
            default:
                return .text("not found", status: 404)
            }
        }
        let client = makeClient()
        do {
            _ = try await client.startRemoteJob(
                peerId: "node-x",
                workspacePath: "/tmp/forbidden",
                prompt: "x"
            )
            XCTFail("expected workspace denied error")
        } catch MeshClientError.workspaceDenied {
            // ok
        } catch {
            XCTFail("expected workspaceDenied, got \(error)")
        }
    }

    func test_daemonUnreachable_whenPortUnused() async throws {
        // Pick a port that nothing is listening on.
        UserDefaults.standard.set(1, forKey: MeshClient.httpPortDefaultsKey)
        let client = MeshClient()
        do {
            _ = try await client.identity()
            XCTFail("expected daemonUnreachable")
        } catch MeshClientError.daemonUnreachable {
            // ok
        } catch {
            XCTFail("expected daemonUnreachable, got \(error)")
        }
    }

    func test_meshTarget_isLocalForLocal_andCarriesNodeIdForPeer() {
        XCTAssertTrue(MeshTarget.local.isLocal)
        XCTAssertNil(MeshTarget.local.peerNodeId)
        let peer = MeshTarget.peer(nodeId: "abc")
        XCTAssertFalse(peer.isLocal)
        XCTAssertEqual(peer.peerNodeId, "abc")
    }

    func test_remoteJobUIState_isTerminalForFinalStatuses() {
        let base = RemoteJobUIState(
            id: "x", chatId: nil, peerNodeId: "p", peerDisplayName: "P",
            workspacePath: "/", prompt: "y",
            status: .running, resultText: "", events: [],
            errorMessage: nil, transientError: nil, startedAt: Date()
        )
        XCTAssertFalse(base.isTerminal)
        var done = base
        done.status = .completed
        XCTAssertTrue(done.isTerminal)
        var failed = base
        failed.status = .failed
        XCTAssertTrue(failed.isTerminal)
        var cancelled = base
        cancelled.status = .cancelled
        XCTAssertTrue(cancelled.isTerminal)
    }

    @MainActor
    func test_remoteMeshIsHiddenWithExperimentalFeaturesOff() {
        XCTAssertEqual(AppFeature.remoteMesh.tier, .experimental)

        let categories = SettingsCategory.visibleCases { feature in
            feature.tier == .stable
        }
        XCTAssertFalse(categories.contains(.machines))
    }

    // MARK: - Helpers

    private func bootDaemon(handler: @escaping FakeMeshDaemon.Handler) throws {
        let d = try FakeMeshDaemon(handler: handler)
        self.daemon = d
        UserDefaults.standard.set(Int(d.port), forKey: MeshClient.httpPortDefaultsKey)
    }

    private func makeClient() -> MeshClient {
        MeshClient(host: "127.0.0.1", port: daemon.port)
    }

    private func waitFor(
        timeout: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("waitFor timed out after \(timeout)s")
    }
}

// MARK: - Tiny JSON helpers

/// Heterogeneous-value Codable wrapper used by the link-body assertion
/// to inspect the JSON the client posted without having to redeclare
/// `LinkInput` here. `value` is `Any` because the server side accepts
/// arbitrary JSON shapes.
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self.value = s; return }
        if let i = try? container.decode(Int.self) { self.value = i; return }
        if let d = try? container.decode(Double.self) { self.value = d; return }
        if let b = try? container.decode(Bool.self) { self.value = b; return }
        if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value); return
        }
        self.value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        default: try container.encodeNil()
        }
    }
}

/// Server-side shape of GET /mesh/jobs/<id>. Mirrors
/// `RemoteMeshHTTPController.JobOutput` so the fake daemon can
/// produce a structurally identical body without depending on the
/// real type.
struct JobSnapshot: Codable {
    var job: RemoteJob?
    var events: [RemoteJobEvent]
}

/// Sloppy thread-safe counter so the polling test can advance through
/// staged responses without taking a lock for each read. Atomic loads
/// only — fine because the test serialises through the fake daemon's
/// queue.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func incrementAndGet() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
