import Foundation
import SwiftUI
import Combine

/// Observable manager for the clawjs-iot daemon.
///
/// Owns:
///   - The HTTP client (`IoTClient`).
///   - The realtime SSE event stream (`/v1/events/stream`).
///   - The cached snapshots the UI binds against: homes, areas, things,
///     scenes, automations, approvals.
///   - The downloaded tool catalog (`availableTools`).
///
/// The supervisor (`ClawJSServiceManager.shared.snapshots[.iot]`)
/// drives the state machine: any time the service flips to `.ready` /
/// `.readyFromDaemon` we bootstrap; any other state suspends consumers
/// and clears the snapshots so the UI shows the right empty/error
/// surface. The SSE stream keeps the snapshots fresh between fetches.
@MainActor
final class IoTManager: NSObject, ObservableObject {

    enum State: Equatable {
        case loading
        case bootstrapping
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?

    /// Tool catalog exposed by the daemon.
    @Published private(set) var availableTools: [RemoteToolDescriptor] = []
    @Published private(set) var catalogGeneratedAt: Date?

    /// Cached collections. The supervisor refresh path replaces each one
    /// wholesale; SSE deltas trigger targeted re-fetches.
    @Published private(set) var homes: [HomeRecord] = []
    @Published private(set) var currentHomeId: String?
    @Published private(set) var areas: [AreaRecord] = []
    @Published private(set) var things: [ThingRecord] = []
    @Published private(set) var scenes: [SceneRecord] = []
    @Published private(set) var automations: [AutomationRecord] = []
    @Published private(set) var approvals: [ApprovalRecord] = []
    @Published private(set) var pendingApprovalsCount: Int = 0
    @Published private(set) var lastAdapterFailure: String?

    private(set) var client = IoTClient()

    private var supervisorObserver: AnyCancellable?
    private var bootstrapGeneration: UUID?
    private var sseTask: URLSessionDataTask?
    private var sseSession: URLSession!
    private var sseBuffer = Data()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.waitsForConnectivity = true
        self.sseSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        attachSupervisorObserver()
    }

    // MARK: - Supervisor wiring

    private func attachSupervisorObserver() {
        let supervisor = ClawJSServiceManager.shared
        supervisorObserver = supervisor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            guard let snap = snapshots[.iot] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .ready = self.state { return }
                    await self.bootstrap()
                }
            case .crashed, .blocked, .idle, .daemonUnavailable:
                self.disconnectSSE()
                self.things = []
                self.areas = []
                self.scenes = []
                self.automations = []
                self.approvals = []
                self.pendingApprovalsCount = 0
                self.state = .failed(snap.state.unavailableReason ?? "IoT service is unavailable.")
            case .starting:
                self.state = .bootstrapping
            }
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if case .ready = state { return }
        state = .bootstrapping
        let generation = UUID()
        bootstrapGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootstrapGeneration == generation else { return }
            if case .bootstrapping = self.state {
                self.state = .failed("IoT service did not become ready within 8 seconds.")
            }
        }
        client.bearerToken = IoTAdminToken.currentAdminToken()
        do {
            async let toolsTask = client.listTools()
            async let homesTask = client.listHomes()
            let catalog = try await toolsTask
            let homes = try await homesTask
            self.availableTools = catalog.tools
            self.catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            self.homes = homes
            self.currentHomeId = homes.first(where: { $0.isDefault })?.id ?? homes.first?.id
            try await refreshAll()
            connectSSE()
            state = .ready
            lastError = nil
            bootstrapGeneration = nil
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            bootstrapGeneration = nil
        }
    }

    func refreshAll() async throws {
        let homeId = currentHomeId
        async let thingsTask = client.listThings(homeId: homeId)
        async let areasTask = client.listAreas(homeId: homeId)
        async let scenesTask = client.listScenes(homeId: homeId)
        async let automationsTask = client.listAutomations(homeId: homeId)
        async let approvalsTask = client.listApprovals(homeId: homeId)
        self.things = try await thingsTask
        self.areas = try await areasTask
        self.scenes = try await scenesTask
        self.automations = try await automationsTask
        let approvals = try await approvalsTask
        self.approvals = approvals
        self.pendingApprovalsCount = approvals.filter { $0.status == "pending" }.count
    }

    func switchHome(_ homeId: String) async {
        guard currentHomeId != homeId else { return }
        currentHomeId = homeId
        do {
            try await refreshAll()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCatalog() async {
        guard case .ready = state else { return }
        do {
            let catalog = try await client.listTools()
            availableTools = catalog.tools
            catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - UI-facing actions

    @discardableResult
    func runAction(_ request: IoTActionRequest) async throws -> IoTActionResult {
        let result = try await performAction {
            try await client.runAction(request, homeId: currentHomeId)
        }
        // After a successful action the SSE event will re-trigger our
        // snapshot refresh; we kick a manual refresh too so the UI
        // does not wait on the event round-trip when the user just
        // tapped a card.
        scheduleRefreshAfterChange()
        return result
    }

    func activateScene(_ scene: SceneRecord) async throws {
        _ = try await performAction {
            try await client.activateScene(sceneId: scene.id, homeId: currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func setAutomationEnabled(_ automation: AutomationRecord, enabled: Bool) async throws {
        _ = try await performAction {
            try await client.setAutomationEnabled(
                automationId: automation.id,
                enabled: enabled,
                homeId: currentHomeId,
            )
        }
        scheduleRefreshAfterChange()
    }

    func runAutomation(_ automation: AutomationRecord) async throws {
        _ = try await performAction {
            try await client.runAutomation(automationId: automation.id, homeId: currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func approveApproval(_ approval: ApprovalRecord) async throws -> IoTActionResult {
        let result = try await performAction {
            try await client.approveApproval(approvalId: approval.id, homeId: currentHomeId)
        }
        scheduleRefreshAfterChange()
        return result
    }

    func denyApproval(_ approval: ApprovalRecord) async throws {
        _ = try await performAction {
            try await client.denyApproval(approvalId: approval.id, homeId: currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func addThing(input: IoTClient.AddThingInput) async throws -> ThingRecord {
        var input = input
        if input.homeId == nil { input.homeId = currentHomeId }
        let thing = try await performAction {
            try await client.addThing(input: input)
        }
        scheduleRefreshAfterChange()
        return thing
    }

    func removeThing(_ thing: ThingRecord) async throws {
        try await performAction {
            try await client.removeThing(thingId: thing.id, homeId: currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    private func performAction<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            let value = try await operation()
            lastError = nil
            return value
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func scheduleRefreshAfterChange() {
        Task { await refreshAllReportingErrors() }
    }

    private func refreshAllReportingErrors() async {
        do {
            try await refreshAll()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startDiscovery(timeoutMs: Int? = nil) async throws {
        do {
            try await client.startDiscovery(timeoutMs: timeoutMs)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func stopDiscovery() async throws {
        do {
            try await client.stopDiscovery()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Protocol helpers

    func commissionMatter(pairingCode: String, label: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["pairingCode": pairingCode]
        if let label, !label.isEmpty { args["label"] = label }
        let result = try await client.invokeTool(id: "iot.matter.commission", arguments: args)
        try result.throwIfFailed()
        return (result.value?.asDictionary) ?? [:]
    }

    func startHomeKitBridge(label: String?) async throws -> [String: Any] {
        var args: [String: Any] = [:]
        if let label, !label.isEmpty { args["label"] = label }
        let result = try await client.invokeTool(id: "iot.homekit.startBridge", arguments: args)
        try result.throwIfFailed()
        return (result.value?.asDictionary) ?? [:]
    }

    func connectMqtt(url: String, username: String?, password: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["url": url]
        if let username, !username.isEmpty { args["username"] = username }
        if let password, !password.isEmpty { args["password"] = password }
        let result = try await client.invokeTool(id: "iot.mqtt.connect", arguments: args)
        try result.throwIfFailed()
        return (result.value?.asDictionary) ?? [:]
    }

    func disconnectMqtt() async throws {
        let result = try await client.invokeTool(id: "iot.mqtt.disconnect", arguments: [:])
        try result.throwIfFailed()
    }

    // MARK: - Cloud helpers

    func connectTuya(appKey: String, appSecret: String, baseUrl: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["appKey": appKey, "appSecret": appSecret]
        if let baseUrl, !baseUrl.isEmpty { args["baseUrl"] = baseUrl }
        let result = try await client.invokeTool(id: "iot.tuya.connect", arguments: args)
        try result.throwIfFailed()
        return result.value?.asDictionary ?? [:]
    }

    func syncTuya() async throws -> [String: Any] {
        let result = try await client.invokeTool(id: "iot.tuya.sync", arguments: [:])
        try result.throwIfFailed()
        return result.value?.asDictionary ?? [:]
    }

    func disconnectTuya() async throws {
        let result = try await client.invokeTool(id: "iot.tuya.disconnect", arguments: [:])
        try result.throwIfFailed()
    }

    func connectGoogleHome(
        publicFulfillmentUrl: String,
        oauthClientId: String,
        oauthClientSecret: String,
        agentUserId: String,
        homeGraphToken: String?,
    ) async throws -> [String: Any] {
        var args: [String: Any] = [
            "publicFulfillmentUrl": publicFulfillmentUrl,
            "oauthClientId": oauthClientId,
            "oauthClientSecret": oauthClientSecret,
            "agentUserId": agentUserId,
        ]
        if let homeGraphToken, !homeGraphToken.isEmpty { args["homeGraphToken"] = homeGraphToken }
        let result = try await client.invokeTool(id: "iot.googleHome.connect", arguments: args)
        try result.throwIfFailed()
        return result.value?.asDictionary ?? [:]
    }

    func disconnectGoogleHome() async throws {
        let result = try await client.invokeTool(id: "iot.googleHome.disconnect", arguments: [:])
        try result.throwIfFailed()
    }

    func connectAlexa(
        publicFulfillmentUrl: String,
        oauthClientSecret: String,
        eventGatewayToken: String?,
        eventGatewayUrl: String?,
    ) async throws -> [String: Any] {
        var args: [String: Any] = [
            "publicFulfillmentUrl": publicFulfillmentUrl,
            "oauthClientSecret": oauthClientSecret,
        ]
        if let eventGatewayToken, !eventGatewayToken.isEmpty { args["eventGatewayToken"] = eventGatewayToken }
        if let eventGatewayUrl, !eventGatewayUrl.isEmpty { args["eventGatewayUrl"] = eventGatewayUrl }
        let result = try await client.invokeTool(id: "iot.alexa.connect", arguments: args)
        try result.throwIfFailed()
        return result.value?.asDictionary ?? [:]
    }

    func disconnectAlexa() async throws {
        let result = try await client.invokeTool(id: "iot.alexa.disconnect", arguments: [:])
        try result.throwIfFailed()
    }

    // MARK: - Lookups

    func areaLabel(forId id: String?) -> String? {
        guard let id else { return nil }
        return areas.first(where: { $0.id == id })?.label
    }

    func thing(byId id: String) -> ThingRecord? {
        things.first(where: { $0.id == id })
    }

    func capability(thing: ThingRecord, key: String) -> CapabilityRecord? {
        thing.capabilities.first(where: { $0.key == key })
    }

    // MARK: - Realtime SSE

    private func connectSSE() {
        guard sseTask == nil else { return }
        guard let url = URL(string: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/events/stream", relativeTo: client.origin) else { return }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity
        sseBuffer.removeAll()
        sseTask = sseSession.dataTask(with: request)
        sseTask?.resume()
    }

    private func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    fileprivate func handleSSEEvent(type: String, payload: [String: Any]?) {
        switch type {
        case "iot.action.executed":
            scheduleRefreshAfterChange()
        case "iot.approval.created":
            scheduleRefreshAfterChange()
        case "iot.thing.added", "iot.thing.removed":
            scheduleRefreshAfterChange()
        case "iot.adapter.failed":
            if let payload, let note = payload["note"] as? String {
                lastAdapterFailure = note
            }
        default:
            break
        }
    }
}

// MARK: - URLSessionDataDelegate (SSE)

extension IoTManager: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            self?.ingestSSEChunk(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            self?.sseTask = nil
            // Reconnection is handled implicitly by the supervisor:
            // if the daemon drops, snapshot flips out of .ready and we
            // bootstrap again next time it returns.
        }
    }

    private func ingestSSEChunk(_ chunk: Data) {
        sseBuffer.append(chunk)
        while let range = sseBuffer.range(of: Data("\n\n".utf8)) {
            let raw = sseBuffer.subdata(in: 0..<range.lowerBound)
            sseBuffer.removeSubrange(0..<range.upperBound)
            guard let text = String(data: raw, encoding: .utf8) else { continue }
            var type: String?
            var dataLine = ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("event:") {
                    type = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    if !dataLine.isEmpty { dataLine.append("\n") }
                    dataLine.append(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
                }
            }
            guard let type else { continue }
            let payload: [String: Any]?
            if dataLine.isEmpty {
                payload = nil
            } else if let bytes = dataLine.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                payload = json
            } else {
                payload = nil
            }
            handleSSEEvent(type: type, payload: payload)
        }
    }
}
