import Foundation

/// HTTP client for the clawjs-iot daemon.
///
/// Phase 1 surface is intentionally narrow:
///   - `health()` confirms the daemon is reachable on its loopback port.
///   - `listTools()` mirrors `GET /v1/tools/list`.
///   - `invokeTool(id:arguments:)` mirrors `POST /v1/tools/:id/invoke`.
///
/// Phase 2 will add typed accessors (`listHomes`, `listThings`,
/// `getThing`, scene/automation mutators) once adapters land; for the
/// foundation pass everything flows through the tools registry.
///
/// Mirrors `DatabaseClient` enough that they can be merged into a
/// shared HTTP helper if the duplication outgrows its usefulness.
struct IoTClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "IoT service is not running."
            case .invalidURL: return "Could not build a URL for the IoT service."
            case .http(let status, let body):
                return "IoT returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode IoT response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach IoT service: \(error.localizedDescription)"
            }
        }
    }

    /// Loopback base URL `http://127.0.0.1:<iot port>`. Resolved from
    /// `ClawJSService.iot.port` so a port change in one place rewires
    /// every consumer.
    let origin: URL

    /// Bearer token for the future authenticated routes. Phase 1 always
    /// nil; populated by `IoTAdminToken.currentAdminToken()` once the
    /// daemon learns to authenticate writes.
    var bearerToken: String?

    init(origin: URL? = nil, bearerToken: String? = nil) {
        self.origin = origin ?? URL(string: "http://127.0.0.1:\(ClawJSService.iot.port)")!
        self.bearerToken = bearerToken
    }

    func health() async -> Bool {
        guard let url = URL(string: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health", relativeTo: origin) else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func listTools() async throws -> RemoteToolCatalog {
        try await getJSON(path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/tools/list", as: RemoteToolCatalog.self)
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        let body: [String: Any] = ["arguments": arguments]
        return try await postJSON(
            path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/tools/\(id)/invoke",
            body: body,
            as: RemoteToolInvocationResult.self
        )
    }

    // MARK: - Typed REST accessors

    func listHomes() async throws -> [HomeRecord] {
        try await getJSON(path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes", as: HomesResponse.self).homes
    }

    func listThings(homeId: String? = nil) async throws -> [ThingRecord] {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/things" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/things"
        return try await getJSON(path: path, as: ThingsResponse.self).things
    }

    func listAreas(homeId: String? = nil) async throws -> [AreaRecord] {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/areas" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/areas"
        return try await getJSON(path: path, as: AreasResponse.self).areas
    }

    func listScenes(homeId: String? = nil) async throws -> [SceneRecord] {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/scenes" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/scenes"
        return try await getJSON(path: path, as: ScenesResponse.self).scenes
    }

    func listAutomations(homeId: String? = nil) async throws -> [AutomationRecord] {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/automations" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/automations"
        return try await getJSON(path: path, as: AutomationsResponse.self).automations
    }

    func listApprovals(homeId: String? = nil) async throws -> [ApprovalRecord] {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/approvals" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/approvals"
        return try await getJSON(path: path, as: ApprovalsResponse.self).approvals
    }

    func runAction(_ request: IoTActionRequest, homeId: String? = nil) async throws -> IoTActionResult {
        let path = homeId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/actions" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/actions"
        let body = try encode(request)
        return try await postJSON(path: path, body: body, as: ActionResponse.self).result
    }

    func activateScene(sceneId: String, homeId: String? = nil) async throws -> IoTActionResult {
        let path = homeId
            .map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/scenes/\(sceneId)/activate" }
            ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/scenes/\(sceneId)/activate"
        return try await postJSON(path: path, body: [:], as: ActionResponse.self).result
    }

    func setAutomationEnabled(automationId: String, enabled: Bool, homeId: String? = nil) async throws -> AutomationRecord {
        let suffix = enabled ? "enable" : "disable"
        let path = homeId
            .map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/automations/\(automationId)/\(suffix)" }
            ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/automations/\(automationId)/\(suffix)"
        return try await postJSON(path: path, body: [:], as: AutomationResponse.self).automation
    }

    func runAutomation(automationId: String, homeId: String? = nil) async throws -> IoTActionResult {
        let path = homeId
            .map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/automations/\(automationId)/run" }
            ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/automations/\(automationId)/run"
        return try await postJSON(path: path, body: [:], as: ActionResponse.self).result
    }

    func approveApproval(approvalId: String, homeId: String? = nil) async throws -> IoTActionResult {
        let path = homeId
            .map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/approvals/\(approvalId)/approve" }
            ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/approvals/\(approvalId)/approve"
        return try await postJSON(path: path, body: [:], as: ActionResponse.self).result
    }

    func denyApproval(approvalId: String, homeId: String? = nil) async throws -> ApprovalRecord {
        let path = homeId
            .map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/homes/\($0)/approvals/\(approvalId)/deny" }
            ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/approvals/\(approvalId)/deny"
        return try await postJSON(path: path, body: [:], as: ApprovalDenyResponse.self).approval
    }

    // MARK: - Tool-backed actions

    /// Phase 2 connector adapters surface adding/removing things and
    /// driving discovery as tool invocations rather than REST routes;
    /// using the tool endpoint keeps a single audit trail in
    /// command_log for both UI and agent paths.
    func addThing(input: AddThingInput) async throws -> ThingRecord {
        let result = try await invokeTool(id: "iot.things.add", arguments: input.toToolArguments())
        try result.throwIfFailed()
        let envelope = try Self.decode(result.value, as: ThingEnvelope.self)
        return envelope.thing
    }

    func removeThing(thingId: String, homeId: String? = nil) async throws {
        var args: [String: Any] = ["thingId": thingId]
        if let homeId { args["homeId"] = homeId }
        let result = try await invokeTool(id: "iot.things.remove", arguments: args)
        try result.throwIfFailed()
    }

    func startDiscovery(timeoutMs: Int? = nil) async throws {
        var args: [String: Any] = [:]
        if let timeoutMs { args["timeoutMs"] = timeoutMs }
        let result = try await invokeTool(id: "iot.discovery.start", arguments: args)
        try result.throwIfFailed()
    }

    func stopDiscovery() async throws {
        let result = try await invokeTool(id: "iot.discovery.stop", arguments: [:])
        try result.throwIfFailed()
    }

    struct AddThingInput {
        var fingerprint: String?
        var label: String?
        var kind: IoTThingKind?
        var connectorId: String?
        var targetRef: String?
        var areaId: String?
        var aliases: [String]?
        var metadata: [String: Any]?
        var homeId: String?

        func toToolArguments() -> [String: Any] {
            var args: [String: Any] = [:]
            if let fingerprint { args["fingerprint"] = fingerprint }
            if let label { args["label"] = label }
            if let kind { args["kind"] = kind.rawValue }
            if let connectorId { args["connectorId"] = connectorId }
            if let targetRef { args["targetRef"] = targetRef }
            if let areaId { args["areaId"] = areaId }
            if let aliases { args["aliases"] = aliases }
            if let metadata { args["metadata"] = metadata }
            if let homeId { args["homeId"] = homeId }
            return args
        }
    }

    // MARK: - HTTP helpers

    private func getJSON<T: Decodable>(path: String, as: T.Type) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return try await send(req)
    }

    private func postJSON<T: Decodable>(path: String, body: [String: Any], as: T.Type) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return try await send(req)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(status: 0, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    /// Encodes a Codable model to the dictionary shape `postJSON`
    /// expects. Used by callers that want to send a typed action
    /// request without hand-translating fields into a Dictionary.
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        return (any as? [String: Any]) ?? [:]
    }

    fileprivate static func decode<T: Decodable>(_ value: Any?, as: T.Type) throws -> T {
        guard let value else {
            throw Error.decoding(NSError(domain: "IoTClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing value"]))
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Response envelopes

private struct HomesResponse: Codable { let homes: [HomeRecord] }
private struct ThingsResponse: Codable { let things: [ThingRecord] }
private struct AreasResponse: Codable { let areas: [AreaRecord] }
private struct ScenesResponse: Codable { let scenes: [SceneRecord] }
private struct AutomationsResponse: Codable { let automations: [AutomationRecord] }
private struct ApprovalsResponse: Codable { let approvals: [ApprovalRecord] }
private struct ActionResponse: Codable { let result: IoTActionResult }
private struct AutomationResponse: Codable { let automation: AutomationRecord }
private struct ApprovalDenyResponse: Codable { let approval: ApprovalRecord }
private struct ThingEnvelope: Codable { let thing: ThingRecord }

extension RemoteToolInvocationResult {
    /// Convenience helper to bubble daemon-side errors as Swift throws.
    func throwIfFailed() throws {
        if !ok, let error {
            throw IoTClient.Error.http(status: 0, body: "\(error.code): \(error.message)")
        }
    }
}
