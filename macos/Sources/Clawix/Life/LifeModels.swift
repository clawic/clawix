import Foundation

/// Source of an observation (mirrors the ClawJS `Source` enum).
enum LifeObservationSource: String, Codable {
    case manual
    case healthkit
    case `import`
    case agent
    case external_api
    case device
}

/// Mirror of the ClawJS `valueType` field on a catalog entry.
enum LifeValueType: String, Codable {
    case numeric
    case boolean
    case `enum`
    case duration
    case text
    case geo
    case photo
    case currency
}

/// Whether a catalog entry is curated by the system (ships with each
/// ClawJS release) or created by the user.
enum LifeCatalogOrigin: String, Codable {
    case system
    case user
}

struct LifeUnit: Codable, Equatable {
    let id: String
    let label: String
    var group: String?
}

struct LifeValidRange: Codable, Equatable {
    var min: Double?
    var max: Double?
}

/// One entry of a vertical's catalog. Mirrors the ClawJS `CatalogEntry`
/// type exposed by `@clawjs/tracking-core`.
struct LifeCatalogEntry: Identifiable, Equatable, Codable {
    let id: String
    let domain: String
    let label: String
    let unit: LifeUnit
    let valueType: LifeValueType
    var validRange: LifeValidRange?
    var enumValues: [String]?
    var category: String?
    var healthkitTypeId: String?
    var description: String?
    let origin: LifeCatalogOrigin
    var hidden: Bool?
}

/// A single observation. The `value` is stored as a heterogeneous
/// `LifeObservationValue` so the same struct can describe a numeric
/// reading, a boolean, a text journal entry, a photo path, or a geo
/// fix without forcing the UI to know up-front.
struct LifeObservation: Identifiable, Equatable, Codable {
    let id: String
    let variableId: String
    let value: LifeObservationValue
    let unitId: String
    let recordedAt: Double
    let source: LifeObservationSource
    var notes: String?
    var sessionId: String?
    var externalId: String?
}

enum LifeObservationValue: Equatable, Codable {
    case number(Double)
    case bool(Bool)
    case text(String)
    case geo(Double, Double)
    case photo(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let s = try? container.decode(String.self) { self = .text(s); return }
        if let geo = try? container.decode([String: Double].self),
           let lat = geo["lat"], let lng = geo["lng"] {
            self = .geo(lat, lng); return
        }
        if let photo = try? container.decode([String: String].self),
           let ref = photo["photoRef"] {
            self = .photo(ref); return
        }
        throw DecodingError.typeMismatch(
            LifeObservationValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown LifeObservationValue payload")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .text(let s): try container.encode(s)
        case .geo(let lat, let lng): try container.encode(["lat": lat, "lng": lng])
        case .photo(let ref): try container.encode(["photoRef": ref])
        }
    }

    var displayString: String {
        switch self {
        case .number(let n):
            if n.rounded() == n {
                return String(format: "%.0f", n)
            }
            return String(format: "%.2f", n)
        case .bool(let b): return b ? "Yes" : "No"
        case .text(let s): return s
        case .geo(let lat, let lng): return String(format: "%.4f, %.4f", lat, lng)
        case .photo(let ref): return ref
        }
    }

    var numericValue: Double? {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
}

/// A session belongs to a parent vertical (workouts, journal,
/// meetings, etc.) and groups N observations.
struct LifeSession: Identifiable, Equatable, Codable {
    let id: String
    let domain: String
    let type: String
    let startedAt: Double
    var endedAt: Double?
    var notes: String?
}
