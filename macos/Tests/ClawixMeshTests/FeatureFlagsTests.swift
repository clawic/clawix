import XCTest
@testable import Clawix

@MainActor
final class FeatureFlagsTests: XCTestCase {
    func test_openCodeIsExperimental() {
        XCTAssertEqual(AppFeature.openCode.tier, .experimental)
    }

    func test_openCodeRuntimeIsIgnoredWhenExperimentalFeaturesAreOff() {
        let flags = FeatureFlags.shared
        let previousExperimental = flags.experimental
        let appDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        let bridgeDefaults = UserDefaults(suiteName: "clawix.bridge") ?? .standard
        let previousRuntime = appDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)
        let previousBridgeRuntime = bridgeDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)

        defer {
            flags.experimental = previousExperimental
            restore(previousRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: appDefaults)
            restore(previousBridgeRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: bridgeDefaults)
        }

        flags.experimental = false
        appDefaults.set(AgentRuntimeChoice.opencode.rawValue, forKey: AgentRuntimeChoice.runtimeKey)

        XCTAssertEqual(AgentRuntimeChoice.loadPersisted(), .codex)

        AgentRuntimeChoice.persist(
            runtime: .opencode,
            openCodeModel: AgentRuntimeChoice.defaultOpenCodeModel
        )
        XCTAssertEqual(appDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.codex.rawValue)
        XCTAssertEqual(bridgeDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.codex.rawValue)
    }

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
