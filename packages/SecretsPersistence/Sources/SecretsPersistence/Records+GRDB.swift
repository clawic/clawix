import Foundation
import GRDB
import SecretsModels

public protocol VaultStorable: FetchableRecord, PersistableRecord, EncodableRecord, TableRecord {}

public extension VaultStorable {
    static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .uppercaseString }
}

extension AccountRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "accounts"
}

extension VaultRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "vaults"
}

extension SecretRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "secrets"
}

extension SecretVersionRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "secretVersions"
}

extension SecretFieldRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "secretFields"
}

extension SecretNotesRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "secretNotes"
}

extension AttachmentRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "attachments"
}

extension AgentGrantRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "agentGrants"
}

extension AuditEventRecord: @retroactive FetchableRecord, @retroactive PersistableRecord, @retroactive EncodableRecord, @retroactive TableRecord, VaultStorable {
    public static let databaseTableName = "auditEvents"
}

public struct VaultMetaRow: FetchableRecord, PersistableRecord, Codable, Equatable, Hashable {
    public static let databaseTableName = "vaultMeta"
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}

public struct SecretsSettingRow: FetchableRecord, PersistableRecord, Codable, Equatable, Hashable {
    public static let databaseTableName = "secretsSettings"
    public var accountId: Int64
    public var key: String
    public var value: String

    public init(accountId: Int64 = 0, key: String, value: String) {
        self.accountId = accountId
        self.key = key
        self.value = value
    }
}
