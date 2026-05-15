import Foundation
import SwiftUI

// User-facing visibility tiers for the v1 surface. Product surfaces are either
// stable or explicitly developer-only. A surface may not remain hidden merely
// because it was previously beta or experimental; the developer switch is only
// for tools that are not product v1.
//
// Stored under `appPrefsSuite` so prefs follow the same UserDefaults
// suite as the rest of the app (sidebar prefs, sync settings, language).
//
// Release builds (`#if !DEBUG`) hard-pin developer-only surfaces to `false`
// and drop the persistence backing entirely. The shipped notarized binary
// cannot surface dev tooling regardless of any prior UserDefaults state
// inherited from a sideloaded dev build.

enum FeatureTier {
    case stable
    case devOnly
}

enum AppFeature: Equatable, CaseIterable {
    case voiceToText
    case quickAsk
    case secrets
    case mcp
    case localModels
    case browserUsage
    case git
    case remoteMesh
    case publishing
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
        case .simulators:
            return .devOnly
        default:
            return .stable
        }
    }
}

@MainActor
final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

#if DEBUG
    @Published var developerSurfaces: Bool {
        didSet { store.set(developerSurfaces, forKey: developerSurfacesKey) }
    }

    private let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private let developerSurfacesKey = ClawixPersistentSurfaceKeys.featureFlagsDeveloperSurfaces

    private init() {
        let s = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        self.developerSurfaces = s.object(forKey: ClawixPersistentSurfaceKeys.featureFlagsDeveloperSurfaces) as? Bool ?? false
    }
#else
    let developerSurfaces: Bool = false
    private init() {}
#endif

    func isVisible(_ feature: AppFeature) -> Bool {
        switch feature.tier {
        case .stable:  return true
        case .devOnly: return developerSurfaces
        }
    }
}
