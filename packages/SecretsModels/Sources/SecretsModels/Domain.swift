import Foundation

public struct Governance: Equatable, Hashable, Codable, Sendable {
    public var allowedHosts: [String]
    public var allowedHeaders: [String]
    public var allowInUrl: Bool
    public var allowInBody: Bool
    public var allowInEnv: Bool
    public var allowInsecureTransport: Bool
    public var allowLocalNetwork: Bool
    public var allowedAgents: [String]?
    public var approvalMode: ApprovalMode
    public var approvalWindowMinutes: Int?
    public var ttlExpiresAt: Timestamp?
    public var maxUses: Int?
    public var rotationReminderDays: Int?
    public var redactionLabel: String?
    public var clipboardClearSeconds: Int
    public var auditRetentionDays: Int?

    public init(
        allowedHosts: [String] = [],
        allowedHeaders: [String] = ["Authorization"],
        allowInUrl: Bool = false,
        allowInBody: Bool = false,
        allowInEnv: Bool = true,
        allowInsecureTransport: Bool = false,
        allowLocalNetwork: Bool = false,
        allowedAgents: [String]? = nil,
        approvalMode: ApprovalMode = .auto,
        approvalWindowMinutes: Int? = nil,
        ttlExpiresAt: Timestamp? = nil,
        maxUses: Int? = nil,
        rotationReminderDays: Int? = nil,
        redactionLabel: String? = nil,
        clipboardClearSeconds: Int = 30,
        auditRetentionDays: Int? = nil
    ) {
        self.allowedHosts = allowedHosts
        self.allowedHeaders = allowedHeaders
        self.allowInUrl = allowInUrl
        self.allowInBody = allowInBody
        self.allowInEnv = allowInEnv
        self.allowInsecureTransport = allowInsecureTransport
        self.allowLocalNetwork = allowLocalNetwork
        self.allowedAgents = allowedAgents
        self.approvalMode = approvalMode
        self.approvalWindowMinutes = approvalWindowMinutes
        self.ttlExpiresAt = ttlExpiresAt
        self.maxUses = maxUses
        self.rotationReminderDays = rotationReminderDays
        self.redactionLabel = redactionLabel
        self.clipboardClearSeconds = clipboardClearSeconds
        self.auditRetentionDays = auditRetentionDays
    }

    public static var permissive: Governance { Governance() }
}

public extension SecretRecord {
    var governance: Governance {
        get {
            Governance(
                allowedHosts: SecretRecord.decodeStringArray(allowedHostsJson),
                allowedHeaders: SecretRecord.decodeStringArray(allowedHeadersJson),
                allowInUrl: allowInUrl,
                allowInBody: allowInBody,
                allowInEnv: allowInEnv,
                allowInsecureTransport: allowInsecureTransport,
                allowLocalNetwork: allowLocalNetwork,
                allowedAgents: allowedAgentsJson.flatMap { SecretRecord.decodeOptionalStringArray($0) },
                approvalMode: approvalMode,
                approvalWindowMinutes: approvalWindowMinutes,
                ttlExpiresAt: ttlExpiresAt,
                maxUses: maxUses,
                rotationReminderDays: rotationReminderDays,
                redactionLabel: redactionLabel,
                clipboardClearSeconds: clipboardClearSeconds,
                auditRetentionDays: auditRetentionDays
            )
        }
        set {
            allowedHostsJson = SecretRecord.encodeStringArray(newValue.allowedHosts)
            allowedHeadersJson = SecretRecord.encodeStringArray(newValue.allowedHeaders)
            allowInUrl = newValue.allowInUrl
            allowInBody = newValue.allowInBody
            allowInEnv = newValue.allowInEnv
            allowInsecureTransport = newValue.allowInsecureTransport
            allowLocalNetwork = newValue.allowLocalNetwork
            allowedAgentsJson = newValue.allowedAgents.flatMap { SecretRecord.encodeStringArray($0) }
            approvalMode = newValue.approvalMode
            approvalWindowMinutes = newValue.approvalWindowMinutes
            ttlExpiresAt = newValue.ttlExpiresAt
            maxUses = newValue.maxUses
            rotationReminderDays = newValue.rotationReminderDays
            redactionLabel = newValue.redactionLabel
            clipboardClearSeconds = newValue.clipboardClearSeconds
            auditRetentionDays = newValue.auditRetentionDays
        }
    }

    var tags: [String] {
        get { SecretRecord.decodeStringArray(tagsJson) }
        set { tagsJson = newValue.isEmpty ? nil : SecretRecord.encodeStringArray(newValue) }
    }

    static func encodeStringArray(_ array: [String]) -> String? {
        guard !array.isEmpty else { return nil }
        let data = (try? JSONEncoder().encode(array)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func decodeOptionalStringArray(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
