import Foundation

/// One configured account of a provider. The user can have many of
/// these for the same provider (Personal / Work / Staging).
///
/// Persisted as a `SecretRecord` in the vault. The metadata fields
/// here mirror plaintext fields on that record; credentials
/// (`access_token`, `refresh_token`, raw API key value) are stored in
/// secret fields on the same record and never travel as part of this
/// struct.
public struct ProviderAccount: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let providerId: ProviderID
    public var label: String
    public let authMethod: AuthMethod
    public var isEnabled: Bool
    public let createdAt: Date
    public var lastUsedAt: Date?
    /// Override of `ProviderDefinition.defaultBaseURL`. Most providers
    /// keep this nil. Custom OpenAI-compatible accounts always set it.
    public var baseURLOverride: URL?
    /// Email or username surfaced for OAuth accounts in the UI. Nil
    /// for plain API key accounts.
    public var accountEmail: String?

    public init(
        id: UUID,
        providerId: ProviderID,
        label: String,
        authMethod: AuthMethod,
        isEnabled: Bool,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        baseURLOverride: URL? = nil,
        accountEmail: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.label = label
        self.authMethod = authMethod
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.baseURLOverride = baseURLOverride
        self.accountEmail = accountEmail
    }
}
