import Foundation

/// Visual identity for a provider in the UI. Brand color is a hex
/// string ("#RRGGBB"); the macOS UI parses it into a SwiftUI Color.
public struct ProviderBrand: Codable, Sendable, Hashable {
    public let monogram: String
    public let colorHex: String

    public init(monogram: String, colorHex: String) {
        self.monogram = monogram
        self.colorHex = colorHex
    }
}

/// One provider in the catalog. Brand names (`displayName`) are NOT
/// localized: "OpenAI" stays "OpenAI" in every locale. `tagline` and
/// `notes` are user-facing copy and localize at the macOS layer.
public struct ProviderDefinition: Sendable, Hashable {
    public let id: ProviderID
    public let displayName: String
    public let tagline: String
    public let authMethods: [AuthMethod]
    public let defaultBaseURL: URL?
    public let supportsCustomBaseURL: Bool
    public let docsURL: URL
    public let brand: ProviderBrand
    public let models: [ModelDefinition]
    public let notes: String?

    public init(
        id: ProviderID,
        displayName: String,
        tagline: String,
        authMethods: [AuthMethod],
        defaultBaseURL: URL?,
        supportsCustomBaseURL: Bool,
        docsURL: URL,
        brand: ProviderBrand,
        models: [ModelDefinition],
        notes: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
        self.authMethods = authMethods
        self.defaultBaseURL = defaultBaseURL
        self.supportsCustomBaseURL = supportsCustomBaseURL
        self.docsURL = docsURL
        self.brand = brand
        self.models = models
        self.notes = notes
    }

    /// Union of every model's capabilities. Settings UI uses this to
    /// render capability badges on the provider list row.
    public var capabilities: Set<Capability> {
        models.reduce(into: Set<Capability>()) { $0.formUnion($1.capabilities) }
    }
}
