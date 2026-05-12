import XCTest
@testable import Clawix

final class ScreenToolRecordingSettingsTests: XCTestCase {
    @MainActor
    func testOpenRecordingEditorAfterRecordingDefaultsOff() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.openRecordingEditorAfterRecordingKey)
        defaults.removeObject(forKey: ScreenToolSettings.openRecordingEditorAfterRecordingKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.openRecordingEditorAfterRecordingKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.openRecordingEditorAfterRecordingKey)
            }
        }

        XCTAssertFalse(ScreenToolSettings.openRecordingEditorAfterRecording)
    }
}
