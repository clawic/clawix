import Foundation
import SecretsModels

public struct DraftField: Equatable, Hashable, Sendable {
    public var name: String
    public var fieldKind: FieldKind
    public var placement: FieldPlacement
    public var isSecret: Bool
    public var isConcealed: Bool
    public var publicValue: String?
    public var secretValue: String?
    public var otpPeriod: Int?
    public var otpDigits: Int?
    public var otpAlgorithm: OtpAlgorithm?
    public var sortOrder: Int

    public init(
        name: String,
        fieldKind: FieldKind,
        placement: FieldPlacement = .none,
        isSecret: Bool,
        isConcealed: Bool = true,
        publicValue: String? = nil,
        secretValue: String? = nil,
        otpPeriod: Int? = nil,
        otpDigits: Int? = nil,
        otpAlgorithm: OtpAlgorithm? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.fieldKind = fieldKind
        self.placement = placement
        self.isSecret = isSecret
        self.isConcealed = isConcealed
        self.publicValue = publicValue
        self.secretValue = secretValue
        self.otpPeriod = otpPeriod
        self.otpDigits = otpDigits
        self.otpAlgorithm = otpAlgorithm
        self.sortOrder = sortOrder
    }
}

public struct DraftSecret: Equatable, Hashable, Sendable {
    public var kind: SecretKind
    public var brandPreset: String?
    public var internalName: String
    public var title: String
    public var fields: [DraftField]
    public var notes: String?
    public var tags: [String]

    public init(
        kind: SecretKind,
        brandPreset: String? = nil,
        internalName: String,
        title: String,
        fields: [DraftField] = [],
        notes: String? = nil,
        tags: [String] = []
    ) {
        self.kind = kind
        self.brandPreset = brandPreset
        self.internalName = internalName
        self.title = title
        self.fields = fields
        self.notes = notes
        self.tags = tags
    }
}

public struct RevealedField: Equatable, Hashable, Sendable {
    public let name: String
    public let fieldKind: FieldKind
    public let placement: FieldPlacement
    public let value: String?
    public let otpPeriod: Int?
    public let otpDigits: Int?
    public let otpAlgorithm: OtpAlgorithm?
}
