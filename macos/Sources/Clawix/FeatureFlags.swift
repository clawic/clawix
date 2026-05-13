import Foundation
import SwiftUI

// User-facing visibility tiers for in-development features. Two opt-in
// switches (Beta + Experimental) gate which feature surfaces appear in
// the app. The toggles live in Settings → General; defaults are OFF so
// a clean install ships only the stable surface.
//
// Stored under `appPrefsSuite` so prefs follow the same UserDefaults
// suite as the rest of the app (sidebar prefs, sync settings, language).
//
// Release builds (`#if !DEBUG`) hard-pin both flags to `false` and drop
// the persistence backing entirely. The shipped notarized binary cannot
// surface beta or experimental features regardless of any prior
// UserDefaults state inherited from a sideloaded dev build. This is
// compile-time enforced rather than runtime config so it cannot fail.

enum FeatureTier {
    case stable
    case beta
    case experimental
}

enum AppFeature: Equatable {
    case voiceToText
    case quickAsk
    case secrets
    case mcp
    case localModels
    case browserUsage
    case git
    case remoteMesh
    case badger
    case apps
    case design
    case life
    case skills
    case skillCollections
    case claw
    case identity
    case telegram
    case screenTools
    case macUtilities
    case databaseWorkbench
    case marketplace
    case calendar
    case contacts
    case database
    case index
    case iotHome
    case agents
    case openCode
    case simulators

    var tier: FeatureTier {
        switch self {
        case .voiceToText:        return .beta
        case .quickAsk:           return .experimental
        case .secrets:            return .experimental
        case .mcp:                return .experimental
        case .localModels:        return .experimental
        case .browserUsage:       return .experimental
        case .git:                return .experimental
        case .remoteMesh:         return .experimental
        case .badger:             return .experimental
        case .apps:               return .experimental
        case .design:             return .experimental
        case .life:               return .experimental
        case .skills:             return .experimental
        case .skillCollections:   return .experimental
        case .claw:             return .experimental
        case .identity:           return .experimental
        case .telegram:           return .experimental
        case .screenTools:        return .experimental
        case .macUtilities:       return .experimental
        case .databaseWorkbench:  return .experimental
        case .marketplace:        return .experimental
        case .calendar:           return .experimental
        case .contacts:           return .experimental
        case .database:           return .experimental
        case .index:              return .experimental
        case .iotHome:            return .experimental
        case .agents:             return .experimental
        case .openCode:           return .experimental
        case .simulators:         return .experimental
        }
    }
}

@MainActor
final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

#if DEBUG
    @Published var beta: Bool {
        didSet { store.set(beta, forKey: betaKey) }
    }

    @Published var experimental: Bool {
        didSet { store.set(experimental, forKey: experimentalKey) }
    }

    private let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private let betaKey = "FeatureFlags.beta"
    private let experimentalKey = "FeatureFlags.experimental"

    private init() {
        let s = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        self.beta = s.object(forKey: "FeatureFlags.beta") as? Bool ?? false
        self.experimental = s.object(forKey: "FeatureFlags.experimental") as? Bool ?? false
    }
#else
    let beta: Bool = false
    let experimental: Bool = false
    private init() {}
#endif

    func isVisible(_ feature: AppFeature) -> Bool {
        switch feature.tier {
        case .stable:       return true
        case .beta:         return beta
        case .experimental: return experimental
        }
    }
}
