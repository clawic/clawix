import Foundation

/// Status of a vertical in the ClawJS tracking registry.
enum LifeVerticalStatus: String, Codable {
    case stable
    case devOnly = "dev-only"
    case removed

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "stable", "alpha":
            self = .stable
        case "dev-only", "planned":
            self = .devOnly
        case "removed", "deprecated":
            self = .removed
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown life vertical status: \(rawValue)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One of the ten top-level groupings that the Life sidebar uses to lay
/// out the 80 verticals. The raw value matches the `category` field in
/// `tracking-registry.json`.
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

/// One entry of the 80-vertical canonical registry. Fields mirror the
/// `tracking-registry.json` schema shipped by the ClawJS daemon.
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

/// Caches the parsed registry per launch. Reads from the bundle first
/// (`life-registry.json`) and falls back to an embedded subset so the app
/// is always usable even before the daemon has shipped its copy.
enum LifeRegistry {
    static let entries: [LifeRegistryEntry] = loadEntries()

    static func entry(byId id: String) -> LifeRegistryEntry? {
        entries.first { $0.id == id && $0.status == .stable }
    }

    static func entry(byId id: String, includeDevOnly: Bool) -> LifeRegistryEntry? {
        entries.first { entry in
            entry.id == id && (includeDevOnly || entry.status == .stable)
        }
    }

    static func entries(in category: LifeCategory, includeDevOnly: Bool = false) -> [LifeRegistryEntry] {
        entries.filter { entry in
            entry.category == category && (includeDevOnly || entry.status == .stable)
        }
    }

    private static func loadEntries() -> [LifeRegistryEntry] {
        if let url = Bundle.main.url(forResource: "life-registry", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let envelope = try? JSONDecoder().decode(RegistryEnvelope.self, from: data) {
            return envelope.entries
        }
        // Fallback embedded subset: every product-v1 vertical so the UI is
        // never empty even when the bundled registry resource is missing.
        return embeddedFallback
    }

    private static let embeddedFallback: [LifeRegistryEntry] = [
        LifeRegistryEntry(id: "health", label: "Health", category: .bodyHealth,
                          description: "General HealthKit-style metrics",
                          catalogSize: 120, hasSessions: false, healthkitMapping: true,
                          sensitive: true, status: .stable,
                          packageName: "@clawjs/health", servicePort: 4700, iconHint: "heart"),
        LifeRegistryEntry(id: "sleep", label: "Sleep", category: .bodyHealth,
                          description: "Sleep duration, stages, quality, naps",
                          catalogSize: 10, hasSessions: true, healthkitMapping: true,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/sleep", servicePort: 4701, iconHint: "moon"),
        LifeRegistryEntry(id: "workouts", label: "Workouts", category: .bodyHealth,
                          description: "Workouts with parent sessions + child observations",
                          catalogSize: 35, hasSessions: true, healthkitMapping: true,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/workouts", servicePort: 4713, iconHint: "dumbbell"),
        LifeRegistryEntry(id: "emotions", label: "Emotions", category: .mindEmotions,
                          description: "Mood, anxiety, energy, joy, stress",
                          catalogSize: 12, hasSessions: false, healthkitMapping: false,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/emotions", servicePort: 4714, iconHint: "smile"),
        LifeRegistryEntry(id: "journal", label: "Journal", category: .mindEmotions,
                          description: "Long-form reflections with prompts",
                          catalogSize: 6, hasSessions: true, healthkitMapping: false,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/journal", servicePort: 4715, iconHint: "book"),
        LifeRegistryEntry(id: "habits", label: "Habits", category: .timeProductivity,
                          description: "Daily habits, streaks and targets",
                          catalogSize: 18, hasSessions: false, healthkitMapping: false,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/habits", servicePort: 4723, iconHint: "check"),
        LifeRegistryEntry(id: "time-tracking", label: "Time tracking", category: .timeProductivity,
                          description: "Manual pomodoros and focus sessions",
                          catalogSize: 12, hasSessions: true, healthkitMapping: false,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/time-tracking", servicePort: 4724, iconHint: "timer"),
        LifeRegistryEntry(id: "goals", label: "Goals", category: .metaReflection,
                          description: "Long-term aspirations and milestones",
                          catalogSize: 8, hasSessions: false, healthkitMapping: false,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/goals", servicePort: 4762, iconHint: "flag"),
        LifeRegistryEntry(id: "finance", label: "Finance", category: .careerMoney,
                          description: "Transactions, budgets, savings, accounts, net worth",
                          catalogSize: 60, hasSessions: false, healthkitMapping: false,
                          sensitive: true, status: .stable,
                          packageName: "@clawjs/finance", servicePort: 4760, iconHint: "wallet"),
        LifeRegistryEntry(id: "nutrition", label: "Nutrition", category: .bodyHealth,
                          description: "Macros and foods consumed",
                          catalogSize: 230, hasSessions: false, healthkitMapping: true,
                          sensitive: false, status: .stable,
                          packageName: "@clawjs/nutrition", servicePort: 4702, iconHint: "apple")
    ]
}
