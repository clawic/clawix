import Foundation

public enum SecretKind: String, Codable, Hashable, Sendable, CaseIterable {
    case passwordLogin = "password_login"
    case apiKey = "api_key"
    case oauthToken = "oauth_token"
    case sshIdentity = "ssh_identity"
    case databaseUrl = "database_url"
    case envBundle = "env_bundle"
    case structuredCredentials = "structured_credentials"
    case certificate
    case webhookSecret = "webhook_secret"
    case secureNote = "secure_note"
}

public enum FieldKind: String, Codable, Hashable, Sendable, CaseIterable {
    case text
    case password
    case url
    case email
    case number
    case otp
    case note
    case reference
}

public enum FieldPlacement: String, Codable, Hashable, Sendable, CaseIterable {
    case header
    case query
    case body
    case env
    case none
}

public enum OtpAlgorithm: String, Codable, Hashable, Sendable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

public enum ApprovalMode: String, Codable, Hashable, Sendable, CaseIterable {
    case auto
    case window
    case everyUse = "every-use"
}

public enum AuditEventKind: String, Codable, Hashable, Sendable, CaseIterable {
    case proxyRequest = "proxy_request"
    case proxyExec = "proxy_exec"
    case proxySsh = "proxy_ssh"
    case proxyGit = "proxy_git"
    case proxyRelease = "proxy_release"
    case proxyPublish = "proxy_publish"

    case uiView = "ui_view"
    case uiCopy = "ui_copy"
    case uiReveal = "ui_reveal"
    case uiExport = "ui_export"

    case adminCreate = "admin_create"
    case adminEdit = "admin_edit"
    case adminRotate = "admin_rotate"
    case adminToggle = "admin_toggle"
    case adminArchive = "admin_archive"
    case adminTrash = "admin_trash"
    case adminPurge = "admin_purge"
    case adminCompromise = "admin_compromise"
    case adminRestoreVersion = "admin_restore_version"

    case vaultSetup = "vault_setup"
    case vaultUnlock = "vault_unlock"
    case vaultLock = "vault_lock"
    case vaultFailedUnlock = "vault_failed_unlock"
    case vaultPasswordChange = "vault_password_change"
    case vaultRecoveryUsed = "vault_recovery_used"
    case vaultExport = "vault_export"
    case vaultImport = "vault_import"

    case grantIssued = "grant_issued"
    case grantUsed = "grant_used"
    case grantRevoked = "grant_revoked"
    case grantExpired = "grant_expired"

    case anomalyDetected = "anomaly_detected"
    case auditIntegrityFailed = "audit_integrity_failed"
}

public enum AuditEventSource: String, Codable, Hashable, Sendable, CaseIterable {
    case proxy
    case ui
    case admin
    case system
}

public enum AgentCapability: String, Codable, Hashable, Sendable, CaseIterable {
    case githubGitPush = "github_git_push"
    case githubReleaseCreate = "github_release_create"
    case npmPublish = "npm_publish"
    case appStoreConnect = "app_store_connect"
    case appleAds = "apple_ads"
    case revenueCat = "revenue_cat"
    case appleNotarization = "apple_notarization"
    case openAiImageGenerate = "openai_image_generate"
}

public enum SecretVersionReason: String, Codable, Hashable, Sendable, CaseIterable {
    case create
    case edit
    case rotate
    case `import`
    case restore
    case proxyRefresh = "proxy_refresh"
}

public enum SecretVersionAuthor: String, Codable, Hashable, Sendable, CaseIterable {
    case ui
    case proxy
    case `import`
    case recovery
    case system
}
