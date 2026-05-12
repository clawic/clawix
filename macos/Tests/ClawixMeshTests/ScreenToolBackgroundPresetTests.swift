import XCTest
@testable import Clawix

final class ScreenToolBackgroundPresetTests: XCTestCase {
    func testBackgroundPresetDefaultsToNone() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.backgroundPresetKey)
        defaults.removeObject(forKey: ScreenToolSettings.backgroundPresetKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.backgroundPresetKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.backgroundPresetKey)
            }
        }

        XCTAssertEqual(ScreenToolSettings.backgroundPreset, .none)
    }

    func testBackgroundPresetTitlesMatchSettingsOptions() {
        XCTAssertEqual(ScreenToolService.BackgroundPreset.allCases.map(\.title), ["None"])
    }
}
