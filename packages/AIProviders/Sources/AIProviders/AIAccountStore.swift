import Foundation

public enum AIAccountStoreError: Error, Sendable, Equatable {
    case vaultLocked
    case accountNotFound
    case providerUnknown
    case credentialMissing
    case duplicateLabel
    case underlying(String)
}

/// Credentials loaded from the vault for a single account. Returned
/// only by `revealCredentials`, which performs an authenticated read
/// against the vault and emits an audit event.
public struct AIAccountCredentials: Sendable, Hashable {
    /// Plain API key (when `account.authMethod == .apiKey`).
    public var apiKey: String?
    /// OAuth access token (when `.oauth(...)` or `.deviceCode(...)`).
    public var accessToken: String?
    /// OAuth refresh token. Nil if the provider does not refresh.
    public var refreshToken: String?
    /// Absolute expiry for `accessToken`. Nil if not applicable.
    public var expiresAt: Date?
    /// Space-delimited scope list returned by the provider. Nil if not
    /// applicable.
    public var scope: String?

    public init(
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scope: String? = nil
    ) {
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public var isEmpty: Bool {
        apiKey?.isEmpty ?? true
            && accessToken?.isEmpty ?? true
    }
}

/// Draft used when creating a brand-new account. The store turns this
/// into a `SecretRecord` with the canonical fields described in the
/// plan's "Storage en vault" section.
public struct ProviderAccountDraft: Sendable {
    public let providerId: ProviderID
    public var label: String
    public var authMethod: AuthMethod
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scope: String?
    public var accountEmail: String?
    public var baseURLOverride: URL?

    public init(
        providerId: ProviderID,
        label: String,
        authMethod: AuthMethod,
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scope: String? = nil,
        accountEmail: String? = nil,
        baseURLOverride: URL? = nil
    ) {
        self.providerId = providerId
        self.label = label
        self.authMethod = authMethod
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.accountEmail = accountEmail
        self.baseURLOverride = baseURLOverride
    }
}

/// Persistence interface for `ProviderAccount`. The macOS target
/// implements it on top of `SecretsStore`; tests use an in-memory mock.
public protocol AIAccountStore: AnyObject, Sendable {

    /// All accounts currently visible. Returns empty when the vault
    /// is locked (callers treat that as "no accounts configured").
    func listAccounts() throws -> [ProviderAccount]

    /// Filter helper: accounts of one provider only.
    func listAccounts(for provider: ProviderID) throws -> [ProviderAccount]

    /// Persist a new account. Returns the saved `ProviderAccount`.
    /// Throws `.duplicateLabel` if the provider already has an account
    /// with the same label (case-insensitive).
    @discardableResult
    func createAccount(_ draft: ProviderAccountDraft) throws -> ProviderAccount

    /// Mutate the editable metadata. Credentials are rotated through
    /// `updateCredentials` to keep the audit trail honest.
    @discardableResult
    func updateAccount(
        id: UUID,
        label: String?,
        isEnabled: Bool?,
        baseURLOverride: URL??,
        accountEmail: String??
    ) throws -> ProviderAccount

    /// Replace the secret material on an existing account. Used by the
    /// OAuth refresh service and by the "rotate API key" UI.
    func updateCredentials(
        accountId: UUID,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) throws

    /// Bumps `lastUsedAt` to now. Cheap, called by features after a
    /// successful network round-trip.
    func touch(accountId: UUID) throws

    /// Remove the account permanently (trash + audit). After this the
    /// id is no longer valid; features that pointed to it must recover.
    func deleteAccount(id: UUID) throws

    /// Authenticated read of credentials for one account. Emits an
    /// audit event. Returns `.credentialMissing` if the vault is locked
    /// or the secret has been deleted under the caller's feet.
    func revealCredentials(accountId: UUID) throws -> AIAccountCredentials
}
