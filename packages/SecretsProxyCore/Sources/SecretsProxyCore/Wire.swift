import Foundation

public enum ProxyOpName: String, Codable, Sendable, CaseIterable {
    case listSecrets = "list_secrets"
    case describeSecret = "describe_secret"
    case resolvePlaceholders = "resolve"
    case audit = "audit"
    case doctor = "doctor"
    case requestActivation = "request_activation"
    case listGrants = "list_grants"
    case revokeGrant = "revoke_grant"
}

public struct ActivationRequest: Codable, Sendable, Hashable {
    public var agent: String
    public var secretInternalName: String
    public var capability: String
    public var reason: String
    public var durationMinutes: Int
    public var scope: [String: String]

    public init(agent: String, secretInternalName: String, capability: String, reason: String, durationMinutes: Int, scope: [String: String]) {
        self.agent = agent
        self.secretInternalName = secretInternalName
        self.capability = capability
        self.reason = reason
        self.durationMinutes = durationMinutes
        self.scope = scope
    }
}

public struct IssuedTokenInfo: Codable, Sendable, Hashable {
    public var token: String
    public var grantId: String
    public var agent: String
    public var capability: String
    public var secretInternalName: String
    public var expiresAt: Int64
    public var durationMinutes: Int
    public var scope: [String: String]

    public init(token: String, grantId: String, agent: String, capability: String, secretInternalName: String, expiresAt: Int64, durationMinutes: Int, scope: [String: String]) {
        self.token = token
        self.grantId = grantId
        self.agent = agent
        self.capability = capability
        self.secretInternalName = secretInternalName
        self.expiresAt = expiresAt
        self.durationMinutes = durationMinutes
        self.scope = scope
    }
}

public struct DescribedGrant: Codable, Sendable, Hashable {
    public var grantId: String
    public var agent: String
    public var capability: String
    public var secretInternalName: String
    public var reason: String
    public var createdAt: Int64
    public var expiresAt: Int64
    public var revokedAt: Int64?
    public var usedCount: Int
    public var lastUsedAt: Int64?
    public var scope: [String: String]

    public init(grantId: String, agent: String, capability: String, secretInternalName: String, reason: String, createdAt: Int64, expiresAt: Int64, revokedAt: Int64?, usedCount: Int, lastUsedAt: Int64?, scope: [String: String]) {
        self.grantId = grantId
        self.agent = agent
        self.capability = capability
        self.secretInternalName = secretInternalName
        self.reason = reason
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.usedCount = usedCount
        self.lastUsedAt = lastUsedAt
        self.scope = scope
    }
}

public struct ResolveContext: Codable, Sendable, Equatable {
    public var host: String?
    public var method: String?
    public var headerNames: [String]
    public var inUrl: Bool
    public var inBody: Bool
    public var inEnv: Bool
    public var insecureTransport: Bool
    public var localNetwork: Bool

    public init(
        host: String? = nil,
        method: String? = nil,
        headerNames: [String] = [],
        inUrl: Bool = false,
        inBody: Bool = false,
        inEnv: Bool = false,
        insecureTransport: Bool = false,
        localNetwork: Bool = false
    ) {
        self.host = host
        self.method = method
        self.headerNames = headerNames
        self.inUrl = inUrl
        self.inBody = inBody
        self.inEnv = inEnv
        self.insecureTransport = insecureTransport
        self.localNetwork = localNetwork
    }
}

public struct DescribedField: Codable, Sendable, Equatable {
    public var name: String
    public var fieldKind: String
    public var placement: String
    public var isSecret: Bool

    public init(name: String, fieldKind: String, placement: String, isSecret: Bool) {
        self.name = name
        self.fieldKind = fieldKind
        self.placement = placement
        self.isSecret = isSecret
    }
}

public struct DescribedSecret: Codable, Sendable, Equatable {
    public var internalName: String
    public var title: String
    public var kind: String
    public var brandPreset: String?
    public var vaultName: String
    public var allowedHosts: [String]
    public var allowedHeaders: [String]
    public var allowInUrl: Bool
    public var allowInBody: Bool
    public var allowInEnv: Bool
    public var readOnly: Bool
    public var isCompromised: Bool
    public var isLocked: Bool
    public var fields: [DescribedField]
    public var notes: String?
    public var lastUsedAt: Int64?
    public var useCount: Int

    public init(
        internalName: String,
        title: String,
        kind: String,
        brandPreset: String? = nil,
        vaultName: String,
        allowedHosts: [String] = [],
        allowedHeaders: [String] = [],
        allowInUrl: Bool = false,
        allowInBody: Bool = false,
        allowInEnv: Bool = true,
        readOnly: Bool = false,
        isCompromised: Bool = false,
        isLocked: Bool = false,
        fields: [DescribedField] = [],
        notes: String? = nil,
        lastUsedAt: Int64? = nil,
        useCount: Int = 0
    ) {
        self.internalName = internalName
        self.title = title
        self.kind = kind
        self.brandPreset = brandPreset
        self.vaultName = vaultName
        self.allowedHosts = allowedHosts
        self.allowedHeaders = allowedHeaders
        self.allowInUrl = allowInUrl
        self.allowInBody = allowInBody
        self.allowInEnv = allowInEnv
        self.readOnly = readOnly
        self.isCompromised = isCompromised
        self.isLocked = isLocked
        self.fields = fields
        self.notes = notes
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public struct ProxyAuditCallSummary: Codable, Sendable, Equatable {
    public var kind: String
    public var success: Bool?
    public var host: String?
    public var method: String?
    public var redactedRequest: String?
    public var responseSize: Int?
    public var latencyMs: Int?
    public var errorCode: String?
    public var sessionId: String?
    public var secretInternalNames: [String]

    public init(
        kind: String,
        success: Bool? = nil,
        host: String? = nil,
        method: String? = nil,
        redactedRequest: String? = nil,
        responseSize: Int? = nil,
        latencyMs: Int? = nil,
        errorCode: String? = nil,
        sessionId: String? = nil,
        secretInternalNames: [String] = []
    ) {
        self.kind = kind
        self.success = success
        self.host = host
        self.method = method
        self.redactedRequest = redactedRequest
        self.responseSize = responseSize
        self.latencyMs = latencyMs
        self.errorCode = errorCode
        self.sessionId = sessionId
        self.secretInternalNames = secretInternalNames
    }
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public var vaultExists: Bool
    public var vaultLocked: Bool
    public var totalSecrets: Int?
    public var totalAuditEvents: Int?
    public var auditChainIntact: Bool?
    public var symlinkInstalled: Bool
    public var deviceId: String?
    public var helperPath: String?

    public init(
        vaultExists: Bool,
        vaultLocked: Bool,
        totalSecrets: Int? = nil,
        totalAuditEvents: Int? = nil,
        auditChainIntact: Bool? = nil,
        symlinkInstalled: Bool = false,
        deviceId: String? = nil,
        helperPath: String? = nil
    ) {
        self.vaultExists = vaultExists
        self.vaultLocked = vaultLocked
        self.totalSecrets = totalSecrets
        self.totalAuditEvents = totalAuditEvents
        self.auditChainIntact = auditChainIntact
        self.symlinkInstalled = symlinkInstalled
        self.deviceId = deviceId
        self.helperPath = helperPath
    }
}

public struct ProxyRequest: Codable, Sendable {
    public var op: ProxyOpName
    public var sessionId: String?
    public var search: String?
    public var name: String?
    public var vaultName: String?
    public var kind: String?
    public var placeholders: [PlaceholderToken]?
    public var context: ResolveContext?
    public var auditCall: ProxyAuditCallSummary?
    public var activation: ActivationRequest?
    public var agentToken: String?
    public var grantId: String?

    public init(
        op: ProxyOpName,
        sessionId: String? = nil,
        search: String? = nil,
        name: String? = nil,
        vaultName: String? = nil,
        kind: String? = nil,
        placeholders: [PlaceholderToken]? = nil,
        context: ResolveContext? = nil,
        auditCall: ProxyAuditCallSummary? = nil,
        activation: ActivationRequest? = nil,
        agentToken: String? = nil,
        grantId: String? = nil
    ) {
        self.op = op
        self.sessionId = sessionId
        self.search = search
        self.name = name
        self.vaultName = vaultName
        self.kind = kind
        self.placeholders = placeholders
        self.context = context
        self.auditCall = auditCall
        self.activation = activation
        self.agentToken = agentToken
        self.grantId = grantId
    }
}

public struct ProxyResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var secrets: [DescribedSecret]?
    public var secret: DescribedSecret?
    public var values: [String: String]?
    public var sensitiveValues: [String]?
    public var redactionLabels: [String: String]?
    public var doctor: DoctorReport?
    public var issuedToken: IssuedTokenInfo?
    public var grants: [DescribedGrant]?
    public var grant: DescribedGrant?

    public init(
        ok: Bool,
        error: String? = nil,
        secrets: [DescribedSecret]? = nil,
        secret: DescribedSecret? = nil,
        values: [String: String]? = nil,
        sensitiveValues: [String]? = nil,
        redactionLabels: [String: String]? = nil,
        doctor: DoctorReport? = nil,
        issuedToken: IssuedTokenInfo? = nil,
        grants: [DescribedGrant]? = nil,
        grant: DescribedGrant? = nil
    ) {
        self.ok = ok
        self.error = error
        self.secrets = secrets
        self.secret = secret
        self.values = values
        self.sensitiveValues = sensitiveValues
        self.redactionLabels = redactionLabels
        self.doctor = doctor
        self.issuedToken = issuedToken
        self.grants = grants
        self.grant = grant
    }

    public static func errorResponse(_ message: String) -> ProxyResponse {
        ProxyResponse(ok: false, error: message)
    }
}

public enum ProxyWireCodec {
    public static func encode(_ message: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(message)
        data.append(0x0A) // newline-delimited JSON
        return data
    }

    public static func decodeRequest(from line: Data) throws -> ProxyRequest {
        try JSONDecoder().decode(ProxyRequest.self, from: line)
    }

    public static func decodeResponse(from line: Data) throws -> ProxyResponse {
        try JSONDecoder().decode(ProxyResponse.self, from: line)
    }
}
