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

    @MainActor
    func testShowRecordingCountdownDefaultsOff() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.showRecordingCountdownKey)
        defaults.removeObject(forKey: ScreenToolSettings.showRecordingCountdownKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.showRecordingCountdownKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.showRecordingCountdownKey)
            }
        }

        XCTAssertFalse(ScreenToolSettings.showRecordingCountdown)
    }

    @MainActor
    func testDisplayRecordingTimeDefaultsOff() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.displayRecordingTimeKey)
        defaults.removeObject(forKey: ScreenToolSettings.displayRecordingTimeKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.displayRecordingTimeKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.displayRecordingTimeKey)
            }
        }

        XCTAssertFalse(ScreenToolSettings.displayRecordingTime)
    }

    @MainActor
    func testScaleRetinaRecordingsTo1xDefaultsOff() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.scaleRetinaRecordingsTo1xKey)
        defaults.removeObject(forKey: ScreenToolSettings.scaleRetinaRecordingsTo1xKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.scaleRetinaRecordingsTo1xKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.scaleRetinaRecordingsTo1xKey)
            }
        }

        XCTAssertFalse(ScreenToolSettings.scaleRetinaRecordingsTo1x)
    }

    @MainActor
    func testRecordingVideoFPSDefaultsTo60() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.recordingVideoFPSKey)
        defaults.removeObject(forKey: ScreenToolSettings.recordingVideoFPSKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.recordingVideoFPSKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.recordingVideoFPSKey)
            }
        }

        XCTAssertEqual(ScreenToolSettings.recordingVideoFPS, 60)
    }

    @MainActor
    func testRecordingVideoFPSIgnoresUnsupportedValues() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.recordingVideoFPSKey)
        defaults.set(24, forKey: ScreenToolSettings.recordingVideoFPSKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.recordingVideoFPSKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.recordingVideoFPSKey)
            }
        }

        XCTAssertEqual(ScreenToolSettings.recordingVideoFPS, 60)
    }

    @MainActor
    func testRecordRecordingAudioInMonoDefaultsOff() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: ScreenToolSettings.recordRecordingAudioInMonoKey)
        defaults.removeObject(forKey: ScreenToolSettings.recordRecordingAudioInMonoKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: ScreenToolSettings.recordRecordingAudioInMonoKey)
            } else {
                defaults.removeObject(forKey: ScreenToolSettings.recordRecordingAudioInMonoKey)
            }
        }

        XCTAssertFalse(ScreenToolSettings.recordRecordingAudioInMono)
    }

    @MainActor
    func testRecordingTimerFormatsElapsedTime() {
        XCTAssertEqual(ScreenToolRecordingTimerWindow.formattedElapsedTime(0), "00:00")
        XCTAssertEqual(ScreenToolRecordingTimerWindow.formattedElapsedTime(65), "01:05")
        XCTAssertEqual(ScreenToolRecordingTimerWindow.formattedElapsedTime(3661), "1:01:01")
    }
}
