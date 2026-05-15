import Foundation

enum LifeVerticalStatus: String, Codable {
    case stable
    case devOnly = "dev-only"
    case removed
}

enum LifeCategory: String, Codable, CaseIterable {
    case bodyHealth = "body-health"
    case mindEmotions = "mind-emotions"
    case timeProductivity = "time-productivity"
    case creativeOutput = "creative-output"
    case consumptionLeisure = "consumption-leisure"
    case relationsSocial = "relations-social"
    case worldPlaces = "world-places"
    case possessionsIdentity = "possessions-identity"
    case careerMoney = "career-money"
    case metaReflection = "meta-reflection"

    var label: String {
        switch self {
        case .bodyHealth: return "Body & Health"
        case .mindEmotions: return "Mind & Emotions"
        case .timeProductivity: return "Time & Productivity"
        case .creativeOutput: return "Creative output"
        case .consumptionLeisure: return "Consumption & Leisure"
        case .relationsSocial: return "Relations & Social"
        case .worldPlaces: return "World & Places"
        case .possessionsIdentity: return "Possessions & Identity"
        case .careerMoney: return "Career & Money"
        case .metaReflection: return "Meta / Reflection"
        }
    }
}

struct LifeRegistryEntry: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    let category: LifeCategory
    let description: String
    let catalogSize: Int
    let hasSessions: Bool
    let healthkitMapping: Bool
    let sensitive: Bool
    let status: LifeVerticalStatus
    let packageName: String
    let servicePort: Int?
    let iconHint: String?
}

private struct RegistryEnvelope: Decodable {
    let schemaVersion: Int
    let entries: [LifeRegistryEntry]
}

enum LifeRegistry {
    private static let allEntries: [LifeRegistryEntry] = loadEntries()

    static var entries: [LifeRegistryEntry] {
        entries(includeDevOnly: false)
    }

    static func entries(includeDevOnly: Bool) -> [LifeRegistryEntry] {
        allEntries.filter { includeDevOnly || $0.status == .stable }
    }

    static func entry(byId id: String) -> LifeRegistryEntry? {
        allEntries.first { $0.id == id && $0.status == .stable }
    }

    static func entry(byId id: String, includeDevOnly: Bool) -> LifeRegistryEntry? {
        allEntries.first { entry in
            entry.id == id && (includeDevOnly || entry.status == .stable)
        }
    }

    static func entries(in category: LifeCategory, includeDevOnly: Bool = false) -> [LifeRegistryEntry] {
        allEntries.filter { entry in
            entry.category == category && (includeDevOnly || entry.status == .stable)
        }
    }

    private static func loadEntries() -> [LifeRegistryEntry] {
        if let url = Bundle.main.url(forResource: "life-registry", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let envelope = try? JSONDecoder().decode(RegistryEnvelope.self, from: data) {
            return envelope.entries
        }
        return []
    }
}
