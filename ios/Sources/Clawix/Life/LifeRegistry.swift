import Foundation

enum LifeVerticalStatus: String, Codable {
    case planned
    case alpha
    case stable
    case deprecated
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
    static let entries: [LifeRegistryEntry] = loadEntries()

    static func entry(byId id: String) -> LifeRegistryEntry? {
        entries.first { $0.id == id }
    }

    static func entries(in category: LifeCategory) -> [LifeRegistryEntry] {
        entries.filter { $0.category == category }
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
