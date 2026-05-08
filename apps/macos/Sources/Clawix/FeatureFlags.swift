import Foundation
import SwiftUI

// User-facing visibility tiers for in-development features. Two opt-in
// switches (Beta + Experimental) gate which feature surfaces appear in
// the app. The toggles live in Settings → General; defaults are OFF so
// a clean install ships only the stable surface.
//
// Stored under `appPrefsSuite` so prefs follow the same UserDefaults
// suite as the rest of the app (sidebar prefs, sync settings, language).

enum FeatureTier {
    case stable
    case beta
    case experimental
}

enum AppFeature {
    case voiceToText
    case quickAsk
    case secrets
    case mcp
    case localModels
    case browserUsage
    case git

    var tier: FeatureTier {
        switch self {
        case .voiceToText:  return .beta
        case .quickAsk:     return .experimental
        case .secrets:      return .experimental
        case .mcp:          return .experimental
        case .localModels:  return .experimental
        case .browserUsage: return .experimental
        case .git:          return .experimental
        }
    }
}

@MainActor
final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

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

    func isVisible(_ feature: AppFeature) -> Bool {
        switch feature.tier {
        case .stable:       return true
        case .beta:         return beta
        case .experimental: return experimental
        }
    }
}
