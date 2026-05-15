import Foundation

/// One open edit session. Combines a Template (skeleton), a Style
/// (visual tokens) and a value bag for each slot. Persisted as a single
/// JSON file under `~/.claw/design/documents/<id>/document.json`.
/// Lives outside the template + style directories so opening, editing
/// and exporting an instance never mutates the underlying recipe.
struct EditorDocument: Codable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: String
    var name: String
    var templateId: String
    var styleId: String
    var variantId: String?
    /// One entry per slot id. Strings, arrays of strings and dicts are
    /// the accepted shapes (mirrors the template render contract).
    var data: [String: SlotValue]
    var createdAt: String
    var updatedAt: String
    var lastExportedAt: String?

    init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        templateId: String,
        styleId: String,
        variantId: String? = nil,
        data: [String: SlotValue] = [:],
        createdAt: String,
        updatedAt: String,
        lastExportedAt: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.templateId = templateId
        self.styleId = styleId
        self.variantId = variantId
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastExportedAt = lastExportedAt
    }
}

/// JSON-friendly value carried by a slot. The renderer reads each kind
/// the way the template expects (heading/body → text, list → items,
/// image → src, button → label, etc.).
enum SlotValue: Codable, Hashable {
    case text(String)
    case items([String])
    case asset(SlotAssetValue)
    case empty

    var asText: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var asItems: [String]? {
        if case .items(let items) = self { return items }
        return nil
    }

    var asAsset: SlotAssetValue? {
        if case .asset(let a) = self { return a }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .empty
            return
        }
        if let asset = try? container.decode(SlotAssetValue.self) {
            self = .asset(asset)
            return
        }
        if let items = try? container.decode([String].self) {
            self = .items(items)
            return
        }
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s):   try container.encode(s)
        case .items(let xs): try container.encode(xs)
        case .asset(let a):  try container.encode(a)
        case .empty:         try container.encodeNil()
        }
    }
}

/// Pointer to an image or logo asset stored inside the document
/// directory. The renderer turns this into a `file://` URL the
/// WKWebView can load.
struct SlotAssetValue: Codable, Hashable {
    var filename: String
    var width: Double?
    var height: Double?
}
