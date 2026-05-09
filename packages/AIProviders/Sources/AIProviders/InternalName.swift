import Foundation

/// Encodes and decodes the `SecretRecord.internalName` we use for
/// provider account credentials: `provider:<providerID>:<accountUUID>`.
public enum InternalName {

    public static let prefix = "provider:"

    public static func encode(providerId: ProviderID, accountId: UUID) -> String {
        "\(prefix)\(providerId.rawValue):\(accountId.uuidString.lowercased())"
    }

    public struct Decoded: Equatable, Sendable {
        public let providerId: ProviderID
        public let accountId: UUID
    }

    public static func decode(_ raw: String) -> Decoded? {
        guard raw.hasPrefix(prefix) else { return nil }
        let body = raw.dropFirst(prefix.count)
        let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let providerId = ProviderID(rawValue: String(parts[0])) else { return nil }
        guard let accountId = UUID(uuidString: String(parts[1])) else { return nil }
        return Decoded(providerId: providerId, accountId: accountId)
    }

    /// True when `raw` has the well-known shape but its provider id is
    /// unknown to this build of the catalog. Used to detect orphaned
    /// rows after the user downgrades or after a removed provider.
    public static func isOrphan(_ raw: String) -> Bool {
        guard raw.hasPrefix(prefix), decode(raw) == nil else { return false }
        return true
    }
}
