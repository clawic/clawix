import Foundation

public struct AccountRecord: Equatable, Hashable, Codable, Sendable {
    public var id: Int64
    public var name: String
    public var createdAt: Timestamp

    public init(id: Int64 = 0, name: String, createdAt: Timestamp = Clock.now()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct VaultRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var accountId: Int64
    public var name: String
    public var icon: String?
    public var color: String?
    public var sortOrder: Int
    public var trashedAt: Timestamp?
    public var createdAt: Timestamp
    public var updatedAt: Timestamp

    public init(
        id: EntityID = .newID(),
        accountId: Int64 = 0,
        name: String,
        icon: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0,
        trashedAt: Timestamp? = nil,
        createdAt: Timestamp = Clock.now(),
        updatedAt: Timestamp = Clock.now()
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.trashedAt = trashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SecretRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var accountId: Int64
    public var vaultId: EntityID
    public var kind: SecretKind
    public var brandPreset: String?
    public var internalName: String
    public var title: String
    public var wrappedItemKey: Data
    public var currentVersionId: EntityID

    public var isArchived: Bool
    public var isCompromised: Bool
    public var isLocked: Bool
    public var readOnly: Bool
    public var trashedAt: Timestamp?

    public var allowedHostsJson: String?
    public var allowedHeadersJson: String?
    public var allowInUrl: Bool
    public var allowInBody: Bool
    public var allowInEnv: Bool
    public var allowInsecureTransport: Bool
    public var allowLocalNetwork: Bool
    public var allowedAgentsJson: String?
    public var approvalMode: ApprovalMode
    public var approvalWindowMinutes: Int?
    public var ttlExpiresAt: Timestamp?
    public var maxUses: Int?
    public var useCount: Int
    public var rotationReminderDays: Int?
    public var lastRotatedAt: Timestamp?
    public var redactionLabel: String?
    public var clipboardClearSeconds: Int
    public var auditRetentionDays: Int?
    public var tagsJson: String?

    public var createdAt: Timestamp
    public var updatedAt: Timestamp
    public var lastUsedAt: Timestamp?

    public init(
        id: EntityID = .newID(),
        accountId: Int64 = 0,
        vaultId: EntityID,
        kind: SecretKind,
        brandPreset: String? = nil,
        internalName: String,
        title: String,
        wrappedItemKey: Data,
        currentVersionId: EntityID,
        isArchived: Bool = false,
        isCompromised: Bool = false,
        isLocked: Bool = false,
        readOnly: Bool = false,
        trashedAt: Timestamp? = nil,
        allowedHostsJson: String? = nil,
        allowedHeadersJson: String? = nil,
        allowInUrl: Bool = false,
        allowInBody: Bool = false,
        allowInEnv: Bool = true,
        allowInsecureTransport: Bool = false,
        allowLocalNetwork: Bool = false,
        allowedAgentsJson: String? = nil,
        approvalMode: ApprovalMode = .auto,
        approvalWindowMinutes: Int? = nil,
        ttlExpiresAt: Timestamp? = nil,
        maxUses: Int? = nil,
        useCount: Int = 0,
        rotationReminderDays: Int? = nil,
        lastRotatedAt: Timestamp? = nil,
        redactionLabel: String? = nil,
        clipboardClearSeconds: Int = 30,
        auditRetentionDays: Int? = nil,
        tagsJson: String? = nil,
        createdAt: Timestamp = Clock.now(),
        updatedAt: Timestamp = Clock.now(),
        lastUsedAt: Timestamp? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.vaultId = vaultId
        self.kind = kind
        self.brandPreset = brandPreset
        self.internalName = internalName
        self.title = title
        self.wrappedItemKey = wrappedItemKey
        self.currentVersionId = currentVersionId
        self.isArchived = isArchived
        self.isCompromised = isCompromised
        self.isLocked = isLocked
        self.readOnly = readOnly
        self.trashedAt = trashedAt
        self.allowedHostsJson = allowedHostsJson
        self.allowedHeadersJson = allowedHeadersJson
        self.allowInUrl = allowInUrl
        self.allowInBody = allowInBody
        self.allowInEnv = allowInEnv
        self.allowInsecureTransport = allowInsecureTransport
        self.allowLocalNetwork = allowLocalNetwork
        self.allowedAgentsJson = allowedAgentsJson
        self.approvalMode = approvalMode
        self.approvalWindowMinutes = approvalWindowMinutes
        self.ttlExpiresAt = ttlExpiresAt
        self.maxUses = maxUses
        self.useCount = useCount
        self.rotationReminderDays = rotationReminderDays
        self.lastRotatedAt = lastRotatedAt
        self.redactionLabel = redactionLabel
        self.clipboardClearSeconds = clipboardClearSeconds
        self.auditRetentionDays = auditRetentionDays
        self.tagsJson = tagsJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct SecretVersionRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var secretId: EntityID
    public var versionNumber: Int
    public var reason: SecretVersionReason
    public var diffSummary: String?
    public var createdAt: Timestamp
    public var createdBy: SecretVersionAuthor

    public init(
        id: EntityID = .newID(),
        secretId: EntityID,
        versionNumber: Int,
        reason: SecretVersionReason,
        diffSummary: String? = nil,
        createdAt: Timestamp = Clock.now(),
        createdBy: SecretVersionAuthor = .ui
    ) {
        self.id = id
        self.secretId = secretId
        self.versionNumber = versionNumber
        self.reason = reason
        self.diffSummary = diffSummary
        self.createdAt = createdAt
        self.createdBy = createdBy
    }
}

public struct SecretFieldRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var secretId: EntityID
    public var versionId: EntityID
    public var fieldName: String
    public var fieldKind: FieldKind
    public var placement: FieldPlacement
    public var isSecret: Bool
    public var isConcealed: Bool
    public var publicValue: String?
    public var valueCiphertext: Data?
    public var otpPeriod: Int?
    public var otpDigits: Int?
    public var otpAlgorithm: OtpAlgorithm?
    public var sortOrder: Int

    public init(
        id: EntityID = .newID(),
        secretId: EntityID,
        versionId: EntityID,
        fieldName: String,
        fieldKind: FieldKind,
        placement: FieldPlacement = .none,
        isSecret: Bool,
        isConcealed: Bool = true,
        publicValue: String? = nil,
        valueCiphertext: Data? = nil,
        otpPeriod: Int? = nil,
        otpDigits: Int? = nil,
        otpAlgorithm: OtpAlgorithm? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.secretId = secretId
        self.versionId = versionId
        self.fieldName = fieldName
        self.fieldKind = fieldKind
        self.placement = placement
        self.isSecret = isSecret
        self.isConcealed = isConcealed
        self.publicValue = publicValue
        self.valueCiphertext = valueCiphertext
        self.otpPeriod = otpPeriod
        self.otpDigits = otpDigits
        self.otpAlgorithm = otpAlgorithm
        self.sortOrder = sortOrder
    }
}

public struct SecretNotesRecord: Equatable, Hashable, Codable, Sendable {
    public var secretId: EntityID
    public var versionId: EntityID
    public var ciphertext: Data?

    public init(secretId: EntityID, versionId: EntityID, ciphertext: Data? = nil) {
        self.secretId = secretId
        self.versionId = versionId
        self.ciphertext = ciphertext
    }
}

public struct AttachmentRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var secretId: EntityID
    public var versionId: EntityID
    public var filename: String
    public var mimeType: String?
    public var size: Int
    public var wrappedAttachmentKey: Data
    public var ciphertext: Data
    public var sortOrder: Int
    public var createdAt: Timestamp

    public init(
        id: EntityID = .newID(),
        secretId: EntityID,
        versionId: EntityID,
        filename: String,
        mimeType: String? = nil,
        size: Int,
        wrappedAttachmentKey: Data,
        ciphertext: Data,
        sortOrder: Int = 0,
        createdAt: Timestamp = Clock.now()
    ) {
        self.id = id
        self.secretId = secretId
        self.versionId = versionId
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.wrappedAttachmentKey = wrappedAttachmentKey
        self.ciphertext = ciphertext
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct AgentGrantRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var accountId: Int64
    public var agent: String
    public var secretId: EntityID
    public var capability: AgentCapability
    public var scopeJson: String?
    public var reason: String
    public var tokenHash: Data
    public var createdAt: Timestamp
    public var expiresAt: Timestamp
    public var revokedAt: Timestamp?
    public var usedCount: Int
    public var lastUsedAt: Timestamp?

    public init(
        id: EntityID = .newID(),
        accountId: Int64 = 0,
        agent: String,
        secretId: EntityID,
        capability: AgentCapability,
        scopeJson: String? = nil,
        reason: String,
        tokenHash: Data,
        createdAt: Timestamp = Clock.now(),
        expiresAt: Timestamp,
        revokedAt: Timestamp? = nil,
        usedCount: Int = 0,
        lastUsedAt: Timestamp? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.agent = agent
        self.secretId = secretId
        self.capability = capability
        self.scopeJson = scopeJson
        self.reason = reason
        self.tokenHash = tokenHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.usedCount = usedCount
        self.lastUsedAt = lastUsedAt
    }
}

public struct AuditEventRecord: Equatable, Hashable, Codable, Sendable {
    public var id: EntityID
    public var accountId: Int64
    public var secretId: EntityID?
    public var vaultId: EntityID?
    public var versionId: EntityID?

    public var kind: AuditEventKind
    public var timestamp: Timestamp
    public var source: AuditEventSource
    public var success: Bool?
    public var deviceId: String?
    public var sessionId: String?

    public var wrappedEventKey: Data
    public var payloadCiphertext: Data

    public var prevHash: Data
    public var selfHash: Data

    public init(
        id: EntityID = .newID(),
        accountId: Int64 = 0,
        secretId: EntityID? = nil,
        vaultId: EntityID? = nil,
        versionId: EntityID? = nil,
        kind: AuditEventKind,
        timestamp: Timestamp = Clock.now(),
        source: AuditEventSource,
        success: Bool? = nil,
        deviceId: String? = nil,
        sessionId: String? = nil,
        wrappedEventKey: Data,
        payloadCiphertext: Data,
        prevHash: Data,
        selfHash: Data
    ) {
        self.id = id
        self.accountId = accountId
        self.secretId = secretId
        self.vaultId = vaultId
        self.versionId = versionId
        self.kind = kind
        self.timestamp = timestamp
        self.source = source
        self.success = success
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.wrappedEventKey = wrappedEventKey
        self.payloadCiphertext = payloadCiphertext
        self.prevHash = prevHash
        self.selfHash = selfHash
    }
}

public struct AuditEventPayload: Equatable, Hashable, Codable, Sendable {
    public var requesterPid: Int32?
    public var requesterImage: String?
    public var agentName: String?
    public var capability: AgentCapability?
    public var host: String?
    public var httpMethod: String?
    public var requestId: String?
    public var redactedRequest: String?
    public var responseSize: Int?
    public var latencyMs: Int?
    public var errorCode: String?
    public var agentGrantId: EntityID?
    public var notes: String?
    public var secretInternalNameFrozen: String?
    public var secretKindFrozen: SecretKind?
    public var userLabel: String?

    public init(
        requesterPid: Int32? = nil,
        requesterImage: String? = nil,
        agentName: String? = nil,
        capability: AgentCapability? = nil,
        host: String? = nil,
        httpMethod: String? = nil,
        requestId: String? = nil,
        redactedRequest: String? = nil,
        responseSize: Int? = nil,
        latencyMs: Int? = nil,
        errorCode: String? = nil,
        agentGrantId: EntityID? = nil,
        notes: String? = nil,
        secretInternalNameFrozen: String? = nil,
        secretKindFrozen: SecretKind? = nil,
        userLabel: String? = nil
    ) {
        self.requesterPid = requesterPid
        self.requesterImage = requesterImage
        self.agentName = agentName
        self.capability = capability
        self.host = host
        self.httpMethod = httpMethod
        self.requestId = requestId
        self.redactedRequest = redactedRequest
        self.responseSize = responseSize
        self.latencyMs = latencyMs
        self.errorCode = errorCode
        self.agentGrantId = agentGrantId
        self.notes = notes
        self.secretInternalNameFrozen = secretInternalNameFrozen
        self.secretKindFrozen = secretKindFrozen
        self.userLabel = userLabel
    }
}

public struct BrandPreset: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var iconId: String
    public var defaultKind: SecretKind
    public var prefilledFields: [BrandPresetField]
    public var defaultAllowedHosts: [String]
    public var defaultAllowedHeaders: [String]
    public var notes: String?

    public init(
        id: String,
        displayName: String,
        iconId: String,
        defaultKind: SecretKind,
        prefilledFields: [BrandPresetField] = [],
        defaultAllowedHosts: [String] = [],
        defaultAllowedHeaders: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.iconId = iconId
        self.defaultKind = defaultKind
        self.prefilledFields = prefilledFields
        self.defaultAllowedHosts = defaultAllowedHosts
        self.defaultAllowedHeaders = defaultAllowedHeaders
        self.notes = notes
    }
}

public struct BrandPresetField: Equatable, Hashable, Codable, Sendable {
    public var name: String
    public var fieldKind: FieldKind
    public var placement: FieldPlacement
    public var isSecret: Bool
    public var defaultValue: String?

    public init(
        name: String,
        fieldKind: FieldKind,
        placement: FieldPlacement = .none,
        isSecret: Bool = false,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.fieldKind = fieldKind
        self.placement = placement
        self.isSecret = isSecret
        self.defaultValue = defaultValue
    }
}
