import Foundation

/// HTTP client for the bundled ClawJS Secrets server. Mirrors the surface
/// described in `~/.claude/plans/clawjs-en-mi-desktop-tranquil-swing.md`
/// Phase 8.B.2: secrets lifecycle (setup/unlock/lock/recover/change pw),
/// secret CRUD, reveal, brokered execution, audit query+integrity.
///
/// Stateless: every method opens a new URLSession request. The session
/// state (locked/unlocked) lives inside the Node server; this client
/// only proxies calls.
@MainActor
final class ClawJSSecretsClient {

    /// Default tenant the Mac app uses. The server seeds it automatically
    /// on first boot. Multitenancy stays on the server side for future
    /// remote consumers; the GUI never sees more than one tenant.
    nonisolated static let defaultTenantId = "clawix-local"

    private let baseURL: URL
    private let tenantId: String
    private var bearerToken: String?
    private let session: URLSession

    init(baseURL: URL, tenantId: String = ClawJSSecretsClient.defaultTenantId, bearerToken: String? = nil) {
        self.baseURL = baseURL
        self.tenantId = tenantId
        self.bearerToken = bearerToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Convenience: connects to the local Secrets service supervised by
    /// `ClawJSServiceManager`.
    static func local(bearerToken: String? = nil) -> ClawJSSecretsClient {
        let token = bearerToken
            ?? ClawJSServiceManager.shared.adminTokenIfSpawned(for: .secrets)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .secrets))
        return ClawJSSecretsClient(
            baseURL: URL(string: "http://127.0.0.1:\(ClawJSService.secrets.port)")!,
            bearerToken: token
        )
    }

    func setBearerToken(_ token: String?) {
        self.bearerToken = token
    }

    // MARK: - Secrets lifecycle

    func health() async throws -> [String: AnyCodable] {
        try await get("/v1/health")
    }

    struct SecretsStateInfo: Codable {
        let tenantId: String
        let initialized: Bool
        let unlocked: Bool
        let autoLockMinutes: Int
    }

    func state() async throws -> SecretsStateInfo {
        try await get("/v1/secrets/state")
    }

    struct SetupResult: Codable {
        let ok: Bool
        let recoveryPhrase: String
        let deviceId: String
    }

    func setup(password: String, appVersion: String? = nil) async throws -> SetupResult {
        try await post("/v1/secrets/setup", body: ["password": password, "appVersion": appVersion as Any])
    }

    func unlock(password: String) async throws {
        let _: [String: AnyCodable] = try await post("/v1/secrets/unlock", body: ["password": password])
    }

    func lock() async throws {
        let _: [String: AnyCodable] = try await post("/v1/secrets/lock", body: [String: Any]())
    }

    func recover(phrase: String) async throws {
        let _: [String: AnyCodable] = try await post("/v1/secrets/recover", body: ["phrase": phrase])
    }

    struct ChangePasswordResult: Codable {
        let ok: Bool
        let recoveryPhrase: String
    }

    func changePassword(old: String, new: String) async throws -> ChangePasswordResult {
        try await post("/v1/secrets/change-password", body: ["oldPassword": old, "newPassword": new])
    }

    struct BackupExportResponse: Codable {
        let ok: Bool
        let format: String
        let exportedAt: String
        let backup: AnyCodable
    }

    struct BackupImportResponse: Codable {
        let ok: Bool
        let format: String
        let imported: [String: AnyCodable]
    }

    func exportBackup(passphrase: String) async throws -> Data {
        let response: BackupExportResponse = try await post(
            "/v1/secrets/backup/export",
            body: ["passphrase": passphrase]
        )
        return try JSONEncoder().encode(response.backup)
    }

    func importBackup(data: Data, passphrase: String) async throws -> BackupImportResponse {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let backup = object as? [String: Any],
              backup["format"] as? String == "clawix-secrets-backup-v1" else {
            throw ClawJSSecretsError.server(status: 400, message: "Not a valid .clawixsecrets file")
        }
        return try await post(
            "/v1/secrets/backup/import",
            body: ["passphrase": passphrase, "backup": backup]
        )
    }

    // MARK: - Doctor + plugins

    func doctor() async throws -> [String: AnyCodable] {
        try await get("/v1/secrets/doctor")
    }

    func plugins() async throws -> [String: AnyCodable] {
        try await get("/v1/plugins")
    }

    func secretTypes() async throws -> [SecretTypeDescriptor] {
        let envelope: [String: [SecretTypeDescriptor]] = try await get("/v1/secret-types")
        return envelope["types"] ?? []
    }

    // MARK: - Secrets containers

    struct Folder: Codable, Identifiable {
        let id: String
        let tenantId: String
        let name: String
        let icon: String?
        let color: String?
        let sortOrder: Int
        let trashedAt: String?
        let createdAt: String
        let updatedAt: String
    }

    func listContainers(includeTrashed: Bool = false) async throws -> [Folder] {
        let envelope: [String: [Folder]] = try await get(
            "/v1/tenants/\(tenantId)/folders?includeTrashed=\(includeTrashed)"
        )
        return envelope["folders"] ?? []
    }

    func createContainer(name: String, icon: String? = nil, color: String? = nil, sortOrder: Int? = nil) async throws -> Folder {
        var body: [String: Any] = ["name": name]
        if let icon { body["icon"] = icon }
        if let color { body["color"] = color }
        if let sortOrder { body["sortOrder"] = sortOrder }
        let envelope: [String: Folder] = try await post("/v1/tenants/\(tenantId)/folders", body: body)
        return envelope["folder"]!
    }

    func renameContainer(id: String, to name: String) async throws -> Folder? {
        let envelope: [String: Folder?] = try await patch("/v1/tenants/\(tenantId)/folders/\(id)", body: ["name": name])
        return envelope["folder"] ?? nil
    }

    func trashContainer(id: String) async throws {
        let _: [String: AnyCodable] = try await delete("/v1/tenants/\(tenantId)/folders/\(id)")
    }

    // MARK: - Secrets

    struct DescribedSecret: Codable, Identifiable {
        let id: String
        let tenantId: String
        let folderId: String?
        let typeId: String?
        let internalName: String
        let title: String
        let versionNumber: Int
        let versionReason: String
        let governance: Governance
        let states: SecretStates
        let counters: Counters
        let tags: [String]
        let fields: [DescribedField]
        let hasNotes: Bool
        let attachments: [AttachmentRef]
        let createdAt: String
        let updatedAt: String

        struct Governance: Codable {
            let allowedHosts: [String]
            let allowedHeaders: [String]
            let allowInUrl: Bool
            let allowInBody: Bool
            let allowInEnv: Bool
            let allowInsecureTransport: Bool
            let allowLocalNetwork: Bool
            let allowedAgents: [String]?
            let approvalMode: String
            let approvalWindowMinutes: Int?
            let ttlExpiresAt: String?
            let maxUses: Int?
            let rotationReminderDays: Int?
            let redactionLabel: String?
            let clipboardClearSeconds: Int?
            let auditRetentionDays: Int?
            let requiresVpn: Bool
            let vpnProfileName: String?
        }

        struct SecretStates: Codable {
            let isArchived: Bool
            let isCompromised: Bool
            let isCompromisedReason: String?
            let isLocked: Bool
            let readOnly: Bool
            let trashedAt: String?
        }

        struct Counters: Codable {
            let useCount: Int
            let lastUsedAt: String?
            let lastRotatedAt: String?
        }

        struct AttachmentRef: Codable, Identifiable {
            let id: String
            let filename: String
            let size: Int
            let mimeType: String?
        }
    }

    struct DescribedField: Codable, Identifiable {
        let fieldName: String
        let fieldKind: String
        let placement: String
        let isSecret: Bool
        let isConcealed: Bool
        let publicValue: String?
        let hasCiphertext: Bool
        let otpPeriod: Int?
        let otpDigits: Int?
        let otpAlgorithm: String?
        let sortOrder: Int

        var id: String { fieldName }
    }

    struct SecretTypeDescriptor: Codable, Identifiable {
        let typeId: String
        let label: String
        let description: String?
        let vendor: String?
        let iconHint: String?
        let fields: [TypeField]
        let executorIds: [String]?
        let sessionStrategyId: String?
        let permissionModelId: String?
        let brandSyncId: String?

        var id: String { typeId }

        struct TypeField: Codable, Identifiable {
            let name: String
            let label: String?
            let kind: String
            let placement: String
            let isSecret: Bool
            let description: String?
            let placeholder: String?
            let required: Bool?
            let defaultValue: String?

            var id: String { name }
        }
    }

    func listSecrets(search: String? = nil, folderId: String? = nil, includeTrashed: Bool = false, includeArchived: Bool = false) async throws -> [DescribedSecret] {
        var components = URLComponents()
        components.queryItems = []
        if let search { components.queryItems?.append(URLQueryItem(name: "search", value: search)) }
        if let folderId { components.queryItems?.append(URLQueryItem(name: "folderId", value: folderId)) }
        if includeTrashed { components.queryItems?.append(URLQueryItem(name: "includeTrashed", value: "true")) }
        if includeArchived { components.queryItems?.append(URLQueryItem(name: "includeArchived", value: "true")) }
        let qs = components.percentEncodedQuery ?? ""
        let envelope: [String: [DescribedSecret]] = try await get("/v1/tenants/\(tenantId)/secrets?\(qs)")
        return envelope["secrets"] ?? []
    }

    func describeSecret(name: String) async throws -> DescribedSecret? {
        let envelope: [String: DescribedSecret?] = try await get(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))"
        )
        return envelope["secret"] ?? nil
    }

    func createSecret(draft: [String: Any]) async throws -> DescribedSecret {
        let envelope: [String: DescribedSecret] = try await post("/v1/tenants/\(tenantId)/secrets", body: ["draft": draft])
        return envelope["secret"]!
    }

    func updateSecret(
        name: String,
        title: String? = nil,
        governance: [String: Any]? = nil,
        metadata: [String: Any]? = nil
    ) async throws -> DescribedSecret? {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let governance { body["governance"] = governance }
        if let metadata { body["metadata"] = metadata }
        let envelope: [String: DescribedSecret?] = try await patch(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))",
            body: body
        )
        return envelope["secret"] ?? nil
    }

    func archiveSecret(name: String, archived: Bool) async throws {
        let _: [String: AnyCodable] = try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))/archive",
            body: ["archived": archived]
        )
    }

    func compromiseSecret(name: String, compromised: Bool = true, reason: String? = nil) async throws {
        let _: [String: AnyCodable] = try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))/compromise",
            body: ["compromised": compromised, "reason": reason as Any]
        )
    }

    func trashSecret(name: String) async throws {
        let _: [String: AnyCodable] = try await delete(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))"
        )
    }

    func restoreSecret(name: String) async throws {
        let _: [String: AnyCodable] = try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(name))/restore",
            body: [String: Any]()
        )
    }

    struct RevealedField: Codable {
        let fieldName: String
        let value: String
    }

    func revealField(secretName: String, fieldName: String, purpose: String = "uiReveal") async throws -> RevealedField {
        let envelope: [String: RevealedField] = try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(secretName))/reveal-field",
            body: ["field": fieldName, "purpose": purpose]
        )
        return envelope["value"]!
    }

    // MARK: - Brokered HTTP

    struct BrokerHTTPDeclaredField {
        let secretName: String
        let fieldName: String
        let placement: String
    }

    struct BrokerHTTPResponse: Codable {
        let ok: Bool
        let status: Int?
        let headers: [String: String]?
        let bodyText: String?
        let bodyBase64: String?
    }

    func brokerHttp(
        method: String,
        url: URL,
        headers: [String: String],
        body: String?,
        bodyBase64: String? = nil,
        agent: String,
        riskTier: String,
        declaredFields: [BrokerHTTPDeclaredField],
        approvalSatisfied: Bool = false,
        timeoutMs: Int? = nil
    ) async throws -> BrokerHTTPResponse {
        var payload: [String: Any] = [
            "method": method,
            "url": url.absoluteString,
            "headers": headers,
            "capability": "broker.http",
            "agent": agent,
            "riskTier": riskTier,
            "declaredFields": declaredFields.map {
                [
                    "secretName": $0.secretName,
                    "fieldName": $0.fieldName,
                    "placement": $0.placement
                ]
            },
            "approvalSatisfied": approvalSatisfied
        ]
        if let body { payload["body"] = body }
        if let bodyBase64 { payload["bodyBase64"] = bodyBase64 }
        if let timeoutMs { payload["timeoutMs"] = timeoutMs }
        return try await post("/v1/tenants/\(tenantId)/broker/http", body: payload)
    }

    // MARK: - Legacy brokered execute

    struct ExecutorOutput: Codable {
        let ok: Bool
        let status: Int?
        let body: String?
        let detail: String?
    }

    func execute(secretName: String, executorId: String, args: [String: Any] = [:], ctx: [String: Any]? = nil) async throws -> ExecutorOutput {
        var body: [String: Any] = ["args": args]
        if let ctx { body["ctx"] = ctx }
        return try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(secretName))/execute/\(percentEncode(executorId))",
            body: body
        )
    }

    func syncBrand(secretName: String) async throws -> [String: AnyCodable] {
        try await post(
            "/v1/tenants/\(tenantId)/secrets/\(percentEncode(secretName))/sync",
            body: [String: Any]()
        )
    }

    // MARK: - Grants

    struct AgentGrantSummary: Codable, Identifiable {
        let id: String
        let tenantId: String
        let agent: String
        let secretId: String
        let capability: [String: AnyCodable]
        let secretsCapabilities: [String]
        let reason: String
        let createdAt: String
        let expiresAt: String
        let revokedAt: String?
        let usedCount: Int
        let lastUsedAt: String?
    }

    struct IssuedGrant: Codable {
        let grant: AgentGrantSummary
        let token: String
    }

    func issueGrant(
        agent: String,
        secretName: String,
        capabilityKind: String,
        scope: [String: Any] = [:],
        secretsCapabilities: [String] = [],
        reason: String,
        durationMinutes: Int = 10
    ) async throws -> IssuedGrant {
        var capability: [String: Any] = ["kind": capabilityKind]
        capability.merge(scope) { _, new in new }
        let body: [String: Any] = [
            "agent": agent,
            "secretName": secretName,
            "capability": capability,
            "secretsCapabilities": secretsCapabilities,
            "reason": reason,
            "durationMinutes": durationMinutes,
        ]
        return try await post("/v1/tenants/\(tenantId)/grants", body: body)
    }

    func listGrants() async throws -> [AgentGrantSummary] {
        let envelope: [String: [AgentGrantSummary]] = try await get("/v1/tenants/\(tenantId)/grants")
        return envelope["grants"] ?? []
    }

    func revokeGrant(id: String) async throws -> AgentGrantSummary? {
        let envelope: [String: AgentGrantSummary?] = try await delete("/v1/tenants/\(tenantId)/grants/\(id)")
        return envelope["grant"] ?? nil
    }

    // MARK: - Leases

    struct LeaseSummary: Codable, Identifiable {
        let id: String
        let tenantId: String
        let secretId: String
        let mode: String
        let createdAt: String
        let expiresAt: String
        let consumedAt: String?
        let revokedAt: String?
    }

    struct IssuedLease: Codable {
        let lease: LeaseSummary
        let token: String
    }

    func issueLease(secretName: String, mode: String, durationMinutes: Int = 10, context: [String: Any]? = nil) async throws -> IssuedLease {
        var body: [String: Any] = [
            "secretName": secretName,
            "mode": mode,
            "durationMinutes": durationMinutes,
        ]
        if let context { body["context"] = context }
        return try await post("/v1/tenants/\(tenantId)/leases", body: body)
    }

    func listLeases() async throws -> [LeaseSummary] {
        let envelope: [String: [LeaseSummary]] = try await get("/v1/tenants/\(tenantId)/leases")
        return envelope["leases"] ?? []
    }

    func revokeLease(id: String) async throws {
        let _: [String: AnyCodable] = try await post("/v1/tenants/\(tenantId)/leases/\(id)/revoke", body: [String: Any]())
    }

    // MARK: - Audit

    struct AuditEvent: Codable {
        let id: String
        let tenantId: String
        let secretId: String?
        let kind: String
        let timestamp: String
        let source: String
        let success: Bool?
        let sequence: Int
        let prevHashBase64: String
        let selfHashBase64: String
        let payload: [String: AnyCodable]
    }

    func queryAudit(kinds: [String]? = nil, since: String? = nil, limit: Int? = nil) async throws -> [AuditEvent] {
        var components = URLComponents()
        components.queryItems = []
        if let kinds, !kinds.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "kinds", value: kinds.joined(separator: ",")))
        }
        if let since { components.queryItems?.append(URLQueryItem(name: "since", value: since)) }
        if let limit { components.queryItems?.append(URLQueryItem(name: "limit", value: String(limit))) }
        let qs = components.percentEncodedQuery ?? ""
        let envelope: [String: [AuditEvent]] = try await get("/v1/tenants/\(tenantId)/audit?\(qs)")
        return envelope["events"] ?? []
    }

    struct AuditIntegrityReport: Codable {
        let totalEvents: Int
        let verified: Int
        let tampered: [TamperedEvent]
        let ok: Bool

        struct TamperedEvent: Codable {
            let eventId: String
            let sequence: Int
        }
    }

    func verifyAuditIntegrity() async throws -> AuditIntegrityReport {
        let envelope: [String: AuditIntegrityReport] = try await post(
            "/v1/tenants/\(tenantId)/audit/verify-integrity",
            body: [String: Any]()
        )
        return envelope["report"]!
    }

    // MARK: - HTTP plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await call(path: path, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await call(path: path, method: "POST", body: body)
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await call(path: path, method: "PATCH", body: body)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await call(path: path, method: "DELETE", body: nil)
    }

    private func call<T: Decodable>(path: String, method: String, body: [String: Any]?) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClawJSSecretsError.invalidResponse
        }
        if !(200..<300 ~= http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw ClawJSSecretsError.server(status: http.statusCode, message: error)
            }
            throw ClawJSSecretsError.server(status: http.statusCode, message: "HTTP \(http.statusCode)")
        }
        if data.isEmpty {
            throw ClawJSSecretsError.emptyResponse
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}

enum ClawJSSecretsError: Error, LocalizedError {
    case invalidResponse
    case emptyResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Secrets server returned an invalid response."
        case .emptyResponse: return "Secrets server returned an empty response."
        case .server(let status, let message): return "Secrets server error \(status): \(message)"
        }
    }
}

/// Codable shim for arbitrary JSON values returned by the server.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self.value = object.mapValues { $0.value }
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]: try container.encode(dict.mapValues(AnyCodable.init))
        default: try container.encodeNil()
        }
    }
}
