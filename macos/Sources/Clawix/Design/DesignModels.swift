import Foundation

// MARK: - Style

struct StyleColorTokens: Codable, Hashable {
    var bg: String
    var surface: String
    var surface2: String?
    var fg: String
    var fgMuted: String?
    var accent: String
    var accent2: String?
    var success: String?
    var warn: String?
    var danger: String?
    var border: String?
    var overlay: String?
    var extras: [String: String]

    enum CodingKeys: String, CodingKey {
        case bg, surface, fg, accent, success, warn, danger, border, overlay
        case surface2 = "surface-2"
        case fgMuted = "fg-muted"
        case accent2 = "accent-2"
    }

    init(
        bg: String,
        surface: String,
        surface2: String? = nil,
        fg: String,
        fgMuted: String? = nil,
        accent: String,
        accent2: String? = nil,
        success: String? = nil,
        warn: String? = nil,
        danger: String? = nil,
        border: String? = nil,
        overlay: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.bg = bg
        self.surface = surface
        self.surface2 = surface2
        self.fg = fg
        self.fgMuted = fgMuted
        self.accent = accent
        self.accent2 = accent2
        self.success = success
        self.warn = warn
        self.danger = danger
        self.border = border
        self.overlay = overlay
        self.extras = extras
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: GenericCodingKey.self)
        var extras: [String: String] = [:]
        var bg: String?
        var surface: String?
        var surface2: String?
        var fg: String?
        var fgMuted: String?
        var accent: String?
        var accent2: String?
        var success: String?
        var warn: String?
        var danger: String?
        var border: String?
        var overlay: String?
        for key in container.allKeys {
            let value = try? container.decode(String.self, forKey: key)
            guard let value else { continue }
            switch key.stringValue {
            case "bg":         bg = value
            case "surface":    surface = value
            case "surface-2":  surface2 = value
            case "fg":         fg = value
            case "fg-muted":   fgMuted = value
            case "accent":     accent = value
            case "accent-2":   accent2 = value
            case "success":    success = value
            case "warn":       warn = value
            case "danger":     danger = value
            case "border":     border = value
            case "overlay":    overlay = value
            default:           extras[key.stringValue] = value
            }
        }
        guard let bg, let surface, let fg, let accent else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing core color tokens (bg, surface, fg, accent)"))
        }
        self.bg = bg
        self.surface = surface
        self.surface2 = surface2
        self.fg = fg
        self.fgMuted = fgMuted
        self.accent = accent
        self.accent2 = accent2
        self.success = success
        self.warn = warn
        self.danger = danger
        self.border = border
        self.overlay = overlay
        self.extras = extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: GenericCodingKey.self)
        try container.encode(bg, forKey: GenericCodingKey(stringValue: "bg")!)
        try container.encode(surface, forKey: GenericCodingKey(stringValue: "surface")!)
        if let surface2 { try container.encode(surface2, forKey: GenericCodingKey(stringValue: "surface-2")!) }
        try container.encode(fg, forKey: GenericCodingKey(stringValue: "fg")!)
        if let fgMuted { try container.encode(fgMuted, forKey: GenericCodingKey(stringValue: "fg-muted")!) }
        try container.encode(accent, forKey: GenericCodingKey(stringValue: "accent")!)
        if let accent2 { try container.encode(accent2, forKey: GenericCodingKey(stringValue: "accent-2")!) }
        if let success { try container.encode(success, forKey: GenericCodingKey(stringValue: "success")!) }
        if let warn { try container.encode(warn, forKey: GenericCodingKey(stringValue: "warn")!) }
        if let danger { try container.encode(danger, forKey: GenericCodingKey(stringValue: "danger")!) }
        if let border { try container.encode(border, forKey: GenericCodingKey(stringValue: "border")!) }
        if let overlay { try container.encode(overlay, forKey: GenericCodingKey(stringValue: "overlay")!) }
        for (k, v) in extras { try container.encode(v, forKey: GenericCodingKey(stringValue: k)!) }
    }

    /// Returns all named color tokens in display order for the moodboard card.
    var allNamed: [(String, String)] {
        var out: [(String, String)] = []
        out.append(("accent", accent))
        if let a2 = accent2 { out.append(("accent-2", a2)) }
        out.append(("bg", bg))
        out.append(("surface", surface))
        if let s2 = surface2 { out.append(("surface-2", s2)) }
        out.append(("fg", fg))
        if let m = fgMuted { out.append(("fg-muted", m)) }
        if let b = border { out.append(("border", b)) }
        for (k, v) in extras.sorted(by: { $0.key < $1.key }) {
            out.append((k, v))
        }
        return out
    }
}

struct StyleTypographyStack: Codable, Hashable {
    var family: String
    var fallback: String?
    var weight: Int?
    var source: String?
}

struct StyleTypographyScale: Codable, Hashable {
    var xs: Double
    var sm: Double
    var md: Double
    var lg: Double
    var xl: Double
    var xl2: Double
    var xl3: Double

    enum CodingKeys: String, CodingKey {
        case xs, sm, md, lg, xl
        case xl2 = "2xl"
        case xl3 = "3xl"
    }
}

struct StyleTypographyTokens: Codable, Hashable {
    var display: StyleTypographyStack
    var body: StyleTypographyStack
    var mono: StyleTypographyStack
    var scale: StyleTypographyScale
}

struct StyleSpacingTokens: Codable, Hashable {
    var unit: Double
    var scale: [String: Double]
}

struct StyleRadiusTokens: Codable, Hashable {
    var none: Double
    var sm: Double
    var md: Double
    var lg: Double
    var xl: Double
    var full: Double
    var squircle: Double?
}

struct StyleShadowToken: Codable, Hashable {
    var offsetX: Double
    var offsetY: Double
    var blur: Double
    var color: String
}

struct StyleShadowTokens: Codable, Hashable {
    var sm: StyleShadowToken
    var md: StyleShadowToken
    var lg: StyleShadowToken
}

struct StyleMotionTokens: Codable, Hashable {
    var curves: [String: String]
    var durations: [String: Double]
}

struct StyleTokens: Codable, Hashable {
    var color: StyleColorTokens
    var typography: StyleTypographyTokens
    var spacing: StyleSpacingTokens
    var radius: StyleRadiusTokens
    var shadow: StyleShadowTokens
    var motion: StyleMotionTokens
}

struct StyleBrand: Codable, Hashable {
    var voice: String?
    var doDont: String?
    var glossary: String?
    var taglines: [String]?
    var claims: [String]?
    var naming: String?

    enum CodingKeys: String, CodingKey {
        case voice, glossary, taglines, claims, naming
        case doDont = "do_dont"
    }
}

struct StyleImagery: Codable, Hashable {
    var photography: String?
    var illustration: String?
    var iconography: String?
    var generationPromptSuffix: String?
    var negativePrompt: String?
    var references: [String]?

    enum CodingKeys: String, CodingKey {
        case photography, illustration, iconography, references
        case generationPromptSuffix = "generation_prompt_suffix"
        case negativePrompt = "negative_prompt"
    }
}

struct StyleManifest: Codable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: String
    var name: String
    var description: String?
    var tags: [String]?
    var tokens: StyleTokens
    var brand: StyleBrand?
    var imagery: StyleImagery?
    var overrides: [String: [String: String]]?
    var references: [String]?
    var examples: [String]?
    var createdAt: String
    var updatedAt: String
    var builtin: Bool?
}

// MARK: - Template

enum TemplateCategory: String, Codable, CaseIterable, Identifiable {
    case presentation
    case card
    case poster
    case socialPost = "social-post"
    case onePager = "one-pager"
    case cv
    case invoice
    case certificate
    case menu
    case flyer
    case email
    case businessCard = "business-card"
    case webLanding = "web-landing"
    case brochure
    case report

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .presentation: return "Presentations"
        case .card:         return "Cards"
        case .poster:       return "Posters"
        case .socialPost:   return "Social"
        case .onePager:     return "One-pagers"
        case .cv:           return "CVs"
        case .invoice:      return "Invoices"
        case .certificate:  return "Certificates"
        case .menu:         return "Menus"
        case .flyer:        return "Flyers"
        case .email:        return "Emails"
        case .businessCard: return "Business cards"
        case .webLanding:   return "Web landings"
        case .brochure:     return "Brochures"
        case .report:       return "Reports"
        }
    }
}

enum TemplateSlotKind: String, Codable {
    case heading
    case subheading
    case body
    case list
    case quote
    case metric
    case image
    case logo
    case button
    case divider
    case shape
    case table
}

struct TemplateSlot: Codable, Hashable, Identifiable {
    var id: String
    var kind: TemplateSlotKind
    var label: String
    var required: Bool?
    var multiline: Bool?
    var maxLength: Int?
    var minItems: Int?
    var maxItems: Int?
    var placeholder: String?
}

struct TemplateVariant: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var description: String?
    var preview: String?
}

enum TemplateAspect: Codable, Hashable {
    case named(String)
    case custom(width: Double, height: Double, unit: String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            self = .named(raw)
            return
        }
        struct CustomAspect: Codable { let width: Double; let height: Double; let unit: String }
        if let custom = try? container.decode(CustomAspect.self) {
            self = .custom(width: custom.width, height: custom.height, unit: custom.unit)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported aspect representation"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .named(let s):
            try container.encode(s)
        case .custom(let w, let h, let u):
            try container.encode(CustomAspectPayload(width: w, height: h, unit: u))
        }
    }

    private struct CustomAspectPayload: Encodable {
        let width: Double
        let height: Double
        let unit: String
    }

    var displayLabel: String {
        switch self {
        case .named(let s): return s
        case .custom(let w, let h, let u): return "\(formatNumber(w))×\(formatNumber(h)) \(u)"
        }
    }

    var size: (width: Double, height: Double) {
        switch self {
        case .named(let s):
            switch s {
            case "16:9":             return (1280, 720)
            case "4:3":              return (1280, 960)
            case "1:1":              return (1080, 1080)
            case "4:5":              return (1080, 1350)
            case "9:16":             return (1080, 1920)
            case "a4-portrait":      return (794, 1123)
            case "a4-landscape":     return (1123, 794)
            case "letter-portrait":  return (816, 1056)
            case "letter-landscape": return (1056, 816)
            default: return (1280, 720)
            }
        case .custom(let w, let h, let u):
            return u == "mm" ? (w * 3.7795, h * 3.7795) : (w, h)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct TemplateManifest: Codable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: String
    var name: String
    var category: TemplateCategory
    var aspect: TemplateAspect
    var description: String?
    var tags: [String]?
    var slots: [TemplateSlot]
    var variants: [TemplateVariant]
    var outputs: [String]
    var defaultStyleId: String?
    var builtin: Bool?
    var createdAt: String
    var updatedAt: String
}

// MARK: - Reference

enum ReferenceType: String, Codable, CaseIterable, Identifiable {
    case web, pdf, image, video, screenshot, snippet
    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

struct ReferenceExtractedStyle: Codable, Hashable {
    var paletteHex: [String]?
    var primaryFontFamily: String?
    var bodyFontFamily: String?
    var monoFontFamily: String?
    var notes: String?
    var candidateStyleId: String?
}

struct ReferenceManifest: Codable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: String
    var type: ReferenceType
    var name: String
    var source: String?
    var asset: String?
    var tags: [String]?
    var description: String?
    var styleIds: [String]?
    var extractedStyle: ReferenceExtractedStyle?
    var createdAt: String
    var updatedAt: String
}

// MARK: - Shared

struct GenericCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
