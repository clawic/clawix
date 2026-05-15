import XCTest
@testable import Clawix

@MainActor
final class FeatureFlagsTests: XCTestCase {
    func test_currentProductSurfacesAreStable() {
        let devOnly = AppFeature.allCases.filter { $0.tier == .devOnly }
        XCTAssertEqual(devOnly, [.simulators])
        XCTAssertEqual(AppFeature.openCode.tier, .stable)
        XCTAssertEqual(AppFeature.screenTools.tier, .stable)
        XCTAssertEqual(AppFeature.macUtilities.tier, .stable)
        XCTAssertEqual(AppFeature.agents.tier, .stable)
        XCTAssertEqual(AppFeature.skills.tier, .stable)
    }

    func test_openCodeRuntimePersistsAsStableSurface() {
        let appDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        let bridgeDefaults = UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite) ?? .standard
        let previousRuntime = appDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)
        let previousBridgeRuntime = bridgeDefaults.object(forKey: AgentRuntimeChoice.runtimeKey)

        defer {
            restore(previousRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: appDefaults)
            restore(previousBridgeRuntime, key: AgentRuntimeChoice.runtimeKey, defaults: bridgeDefaults)
        }

        appDefaults.set(AgentRuntimeChoice.opencode.rawValue, forKey: AgentRuntimeChoice.runtimeKey)

        XCTAssertEqual(AgentRuntimeChoice.loadPersisted(), .opencode)

        AgentRuntimeChoice.persist(
            runtime: .opencode,
            openCodeModel: AgentRuntimeChoice.defaultOpenCodeModel
        )
        XCTAssertEqual(appDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.opencode.rawValue)
        XCTAssertEqual(bridgeDefaults.string(forKey: AgentRuntimeChoice.runtimeKey), AgentRuntimeChoice.opencode.rawValue)
    }

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
