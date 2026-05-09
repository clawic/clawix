import Foundation

/// One model offered by a provider. The catalog is curated by us in
/// code; the user does not edit this list. v1 keeps it static.
public struct ModelDefinition: Codable, Sendable, Hashable {
    public let id: String
    public let providerId: ProviderID
    public let displayName: String
    public let capabilities: Set<Capability>
    public let contextWindow: Int?
    /// Capabilities for which this model is the catalog's first pick. A
    /// feature with a fresh selection chooses the first model that has
    /// the requested capability in `isDefaultFor`; falls back to any
    /// model with that capability when none is marked.
    public let isDefaultFor: Set<Capability>

    public init(
        id: String,
        providerId: ProviderID,
        displayName: String,
        capabilities: Set<Capability>,
        contextWindow: Int? = nil,
        isDefaultFor: Set<Capability> = []
    ) {
        self.id = id
        self.providerId = providerId
        self.displayName = displayName
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.isDefaultFor = isDefaultFor
    }
}
