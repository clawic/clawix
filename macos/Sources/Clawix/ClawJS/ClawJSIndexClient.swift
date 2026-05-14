import Foundation

/// HTTP client for `@clawjs/index` running on the registered search port. Mirrors
/// `ClawJSDatabaseClient` and talks to the routes documented in
/// `packages/clawjs-index/src/app.ts`.
struct ClawJSIndexClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "ClawJS index service is not running."
            case .invalidURL: return "Could not build a URL for the index service."
            case .http(let status, let body): return "Index returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error): return "Could not decode index response: \(error.localizedDescription)"
            case .transport(let error): return "Could not reach index service: \(error.localizedDescription)"
            }
        }
    }

    var bearerToken: String?
    let origin: URL

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.index.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Health

    struct HealthResponse: Decodable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    func probeHealth() async throws -> HealthResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health", method: "GET", body: nil, authenticated: false)
    }

    // MARK: - Types

    struct EntityType: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let version: Int
        let identityFields: [String]
        let timeseriesFields: [String]
        let canonical: Bool
        let createdAt: String?
        let uiHints: UIHints?
        let schemaJson: SchemaWrapper?

        struct UIHints: Decodable, Equatable, Hashable {
            let icon: String?
            let accentColor: String?
            let cardKind: String?
            let listColumns: [String]?
        }

        struct SchemaWrapper: Decodable, Equatable, Hashable {
            let raw: AnyJSON
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                raw = try container.decode(AnyJSON.self)
            }
        }
    }

    func listTypes() async throws -> [EntityType] {
        struct Response: Decodable { let types: [EntityType] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/types")
        return response.types
    }

    @discardableResult
    func declareType(payload: [String: AnyJSON]) async throws -> EntityType {
        struct Response: Decodable { let type: EntityType }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/types", method: "POST", body: payload)
        return response.type
    }

    // MARK: - Entities

    struct Entity: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let typeId: String
        let typeName: String
        let identityKey: String
        let data: [String: AnyJSON]
        let firstSeenAt: String
        let lastSeenAt: String
        let observationCount: Int
        let sourceUrl: String?
        let title: String?
        let thumbnailUrl: String?
    }

    struct Observation: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let entityId: String
        let runId: String?
        let sourceUrl: String?
        let observedAt: String
        let snapshot: [String: AnyJSON]
        let changedFields: [String]
        let agentSessionId: String?
    }

    struct EntityRelation: Decodable, Identifiable, Equatable, Hashable {
        let id: Int
        let fromEntityId: String
        let toEntityId: String
        let relationType: String
        let attrs: [String: AnyJSON]?
        let createdAt: String
    }

    struct EntityTag: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let color: String?
    }

    struct EntityDetailResponse: Decodable, Equatable {
        let entity: Entity
        let observations: [Observation]
        let relationsFrom: [EntityRelation]
        let relationsTo: [EntityRelation]
        let tags: [EntityTag]
    }

    func listEntities(payload: [String: AnyJSON]) async throws -> [Entity] {
        struct Response: Decodable { let entities: [Entity] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/entities/query", method: "POST", body: payload)
        return response.entities
    }

    func getEntity(id: String) async throws -> EntityDetailResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/entities/\(id)", method: "GET", body: nil)
    }

    struct CountsResponse: Decodable, Equatable {
        struct Entry: Decodable, Equatable, Hashable {
            let typeName: String
            let total: Int
        }
        let counts: [Entry]
    }

    func countsByType() async throws -> CountsResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/entities/counts")
    }

    struct HistoryPoint: Decodable, Equatable, Hashable {
        let fieldPath: String
        let value: AnyJSON
        let validFrom: String
        let runId: String?
    }

    func history(entityId: String, field: String) async throws -> [HistoryPoint] {
        struct Response: Decodable { let history: [HistoryPoint] }
        let response: Response = try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/entities/\(entityId)/history?field=\(field.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? field)"
        )
        return response.history
    }

    @discardableResult
    func upsertEntity(type: String, data: [String: AnyJSON], sourceUrl: String? = nil) async throws -> Entity {
        struct Response: Decodable { let entity: Entity; let isNew: Bool; let changedFields: [String] }
        var payload: [String: AnyJSON] = ["type": .string(type), "data": .object(data)]
        if let sourceUrl { payload["sourceUrl"] = .string(sourceUrl) }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/entities/upsert", method: "POST", body: payload)
        return response.entity
    }

    // MARK: - Searches

    struct Search: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let typeId: String?
        let criteria: [String: AnyJSON]
        let promptTemplate: String?
        let createdAt: String
        let updatedAt: String
    }

    func listSearches() async throws -> [Search] {
        struct Response: Decodable { let searches: [Search] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/searches")
        return response.searches
    }

    @discardableResult
    func createSearch(payload: [String: AnyJSON]) async throws -> Search {
        struct Response: Decodable { let search: Search }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/searches", method: "POST", body: payload)
        return response.search
    }

    @discardableResult
    func updateSearch(id: String, payload: [String: AnyJSON]) async throws -> Search {
        struct Response: Decodable { let search: Search }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/searches/\(id)", method: "PATCH", body: payload)
        return response.search
    }

    func deleteSearch(id: String) async throws {
        let _: Empty = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/searches/\(id)", method: "DELETE", body: nil)
    }

    @discardableResult
    func runSearch(id: String, prompt: String? = nil) async throws -> Run {
        struct Response: Decodable { let run: Run }
        var payload: [String: AnyJSON] = [:]
        if let prompt { payload["prompt"] = .string(prompt) }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/searches/\(id)/run", method: "POST", body: payload)
        return response.run
    }

    // MARK: - Monitors

    struct AlertRule: Codable, Equatable, Hashable {
        let id: String
        let when: String
        let field: String?
        let thresholdPct: Double?
        let thresholdAbs: Double?
        let match: AnyJSON?
    }

    struct Monitor: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let searchId: String
        let name: String?
        let cronExpr: String
        let cronHuman: String?
        let enabled: Bool
        let lastFireAt: String?
        let nextFireAt: String?
        let alertRules: [AlertRule]
        let muteUntil: String?
        let createdAt: String
    }

    func listMonitors() async throws -> [Monitor] {
        struct Response: Decodable { let monitors: [Monitor] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/monitors")
        return response.monitors
    }

    @discardableResult
    func createMonitor(payload: [String: AnyJSON]) async throws -> Monitor {
        struct Response: Decodable { let monitor: Monitor }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/monitors", method: "POST", body: payload)
        return response.monitor
    }

    @discardableResult
    func updateMonitor(id: String, payload: [String: AnyJSON]) async throws -> Monitor {
        struct Response: Decodable { let monitor: Monitor }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/monitors/\(id)", method: "PATCH", body: payload)
        return response.monitor
    }

    func deleteMonitor(id: String) async throws {
        let _: Empty = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/monitors/\(id)", method: "DELETE", body: nil)
    }

    @discardableResult
    func fireMonitor(id: String) async throws -> Run {
        struct Response: Decodable { let run: Run }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/monitors/\(id)/fire", method: "POST", body: nil)
        return response.run
    }

    // MARK: - Runs

    struct Run: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let monitorId: String?
        let searchId: String?
        let kind: String
        let status: String
        let startedAt: String?
        let endedAt: String?
        let codexSessionId: String?
        let error: String?
        let entitiesSeen: Int
        let observationsCount: Int
        let alertsFired: Int
        let tokensIn: Int?
        let tokensOut: Int?
        let prompt: String?
        let createdAt: String
    }

    func listRuns(monitorId: String? = nil) async throws -> [Run] {
        struct Response: Decodable { let runs: [Run] }
        let path = monitorId.map { "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runs?monitorId=\($0)" } ?? "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runs"
        let response: Response = try await request(path)
        return response.runs
    }

    struct RunDetail: Decodable, Equatable {
        let run: Run
        let entities: [Entity]
    }

    func getRun(id: String) async throws -> RunDetail {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runs/\(id)")
    }

    // MARK: - Alerts

    struct Alert: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let monitorId: String?
        let runId: String?
        let entityId: String?
        let ruleId: String
        let ruleKind: String
        let ts: String
        let payload: [String: AnyJSON]
        let ackAt: String?
    }

    struct AlertsResponse: Decodable, Equatable {
        let alerts: [Alert]
        let unread: Int
    }

    func listAlerts() async throws -> AlertsResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/alerts")
    }

    func ackAlert(id: String) async throws {
        let _: Empty = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/alerts/\(id)/ack", method: "POST", body: nil)
    }

    // MARK: - Tags + Collections

    struct Tag: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let color: String?
    }

    func listTags() async throws -> [Tag] {
        struct Response: Decodable { let tags: [Tag] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/tags")
        return response.tags
    }

    @discardableResult
    func applyTag(entityId: String, name: String, color: String? = nil) async throws -> Tag {
        struct Response: Decodable { let tag: Tag }
        var payload: [String: AnyJSON] = ["entityId": .string(entityId), "name": .string(name)]
        if let color { payload["color"] = .string(color) }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/tags/apply", method: "POST", body: payload)
        return response.tag
    }

    struct Collection: Decodable, Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let description: String?
        let kind: String
        let memberCount: Int
        let createdAt: String
    }

    func listCollections() async throws -> [Collection] {
        struct Response: Decodable { let collections: [Collection] }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/collections")
        return response.collections
    }

    @discardableResult
    func createCollection(name: String, description: String? = nil) async throws -> Collection {
        struct Response: Decodable { let collection: Collection }
        var payload: [String: AnyJSON] = ["name": .string(name)]
        if let description { payload["description"] = .string(description) }
        let response: Response = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/collections", method: "POST", body: payload)
        return response.collection
    }

    func addToCollection(collectionId: String, entityId: String) async throws {
        let payload: [String: AnyJSON] = ["entityId": .string(entityId)]
        let _: Empty = try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/collections/\(collectionId)/add",
            method: "POST",
            body: payload
        )
    }

    // MARK: - Transport

    private struct Empty: Decodable {}

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Any? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let bearerToken else { throw Error.serviceNotReady }
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: AnyJSONCodableHelper.swift(from: body))
            } catch {
                throw Error.transport(error)
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: bodyString)
        }
        if data.isEmpty || T.self == Empty.self {
            return try JSONDecoder().decode(T.self, from: "{}".data(using: .utf8)!)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }
}

/// Coerces our `AnyJSON` enum (and dictionaries thereof) into the
/// `Any` graph `JSONSerialization` accepts.
enum AnyJSONCodableHelper {
    static func swift(from value: Any) -> Any {
        if let json = value as? AnyJSON { return json.swiftValue }
        if let dict = value as? [String: AnyJSON] {
            return dict.mapValues { $0.swiftValue }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { swift(from: $0) }
        }
        if let array = value as? [AnyJSON] { return array.map { $0.swiftValue } }
        if let array = value as? [Any] { return array.map { swift(from: $0) } }
        return value
    }
}

extension AnyJSON {
    var swiftValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let entries): return entries.map { $0.swiftValue }
        case .object(let entries): return entries.mapValues { $0.swiftValue }
        }
    }

    var asString: String? { if case .string(let s) = self { return s }; return nil }
    var asNumber: Double? { if case .number(let n) = self { return n }; return nil }
    var asBool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var asArray: [AnyJSON]? { if case .array(let a) = self { return a }; return nil }
    var asObject: [String: AnyJSON]? { if case .object(let o) = self { return o }; return nil }

    func string(_ path: String) -> String? {
        guard case .object(let dict) = self else { return nil }
        return dict[path]?.asString
    }

    func number(_ path: String) -> Double? {
        guard case .object(let dict) = self else { return nil }
        return dict[path]?.asNumber
    }
}
