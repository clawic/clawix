import XCTest
@testable import Clawix

final class ScreenToolRecordingArgsTests: XCTestCase {
    @MainActor
    func testRecordingArgsIncludeSupportedRecordingOptions() {
        let output = URL(fileURLWithPath: "/tmp/clawix-recording.mov")

        let args = ScreenToolService.recordingArgs(
            output: output,
            playSounds: true,
            showControls: true,
            highlightClicks: true,
            recordAudio: true
        )

        XCTAssertEqual(args, ["-v", "-i", "-J", "video", "-U", "-k", "-g", output.path])
    }

    @MainActor
    func testRecordingArgsCanDisableOptionalFlags() {
        let output = URL(fileURLWithPath: "/tmp/clawix-recording.mov")

        let args = ScreenToolService.recordingArgs(
            output: output,
            playSounds: false,
            showControls: false,
            highlightClicks: false,
            recordAudio: false
        )

        XCTAssertEqual(args, ["-x", "-v", "-i", "-J", "video", output.path])
    }
}
