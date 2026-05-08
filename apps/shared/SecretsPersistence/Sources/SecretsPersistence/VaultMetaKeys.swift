import Foundation

public enum VaultMetaKey {
    public static let formatVersion = "formatVersion"
    public static let cryptoVersion = "cryptoVersion"
    public static let schemaVersion = "schemaVersion"
    public static let appVersionAtSetup = "appVersionAtSetup"
    public static let deviceId = "deviceId"
    public static let createdAt = "createdAt"
    public static let lastUnlockedAt = "lastUnlockedAt"

    public static let kdfSalt = "kdfSalt"
    public static let kdfParams = "kdfParams"
    public static let verifier = "verifier"

    public static let recoverySalt = "recoverySalt"
    public static let recoveryParams = "recoveryParams"
    public static let recoveryWrap = "recoveryWrap"

    public static let auditChainGenesis = "auditChainGenesis"
    public static let auditMacKeyWrap = "auditMacKeyWrap"
}
