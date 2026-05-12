import XCTest
@testable import Clawix

final class ScreenToolRecordingArgsTests: XCTestCase {
    @MainActor
    func testRecordingArgsIncludeSupportedRecordingOptions() {
        let output = URL(fileURLWithPath: "/tmp/clawix-recording.mov")

        let args = ScreenToolService.recordingArgs(
            output: output,
            playSounds: true,
            showCursor: true,
            showControls: true,
            highlightClicks: true,
            recordAudio: true
        )

        XCTAssertEqual(args, ["-v", "-J", "video", "-i", "-U", "-k", "-g", output.path])
    }

    @MainActor
    func testRecordingArgsCanDisableOptionalFlags() {
        let output = URL(fileURLWithPath: "/tmp/clawix-recording.mov")

        let args = ScreenToolService.recordingArgs(
            output: output,
            playSounds: false,
            showCursor: false,
            showControls: false,
            highlightClicks: false,
            recordAudio: false
        )

        XCTAssertEqual(args, ["-x", "-v", "-J", "video", output.path])
    }

    @MainActor
    func testRecordingArgsCanHideCursor() {
        let output = URL(fileURLWithPath: "/tmp/clawix-recording.mov")

        let args = ScreenToolService.recordingArgs(
            output: output,
            playSounds: true,
            showCursor: false,
            showControls: true,
            highlightClicks: true,
            recordAudio: false
        )

        XCTAssertEqual(args, ["-v", "-J", "video", "-U", "-k", output.path])
    }

    @MainActor
    func testRetinaVideoScaleArgumentsDownscaleToEvenHalfDimensions() {
        let input = URL(fileURLWithPath: "/tmp/clawix-recording.mov")
        let output = URL(fileURLWithPath: "/tmp/clawix-recording-1x.mov")

        let args = ScreenToolService.retinaVideoScaleArguments(input: input, output: output)

        XCTAssertEqual(args, [
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-filter:v", "scale=trunc(iw/4)*2:trunc(ih/4)*2",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "18",
            "-c:a", "copy",
            "-movflags", "+faststart",
            output.path
        ])
    }

    @MainActor
    func testMonoRecordingAudioArgumentsCopyVideoAndConvertAudio() {
        let input = URL(fileURLWithPath: "/tmp/clawix-recording.mov")
        let output = URL(fileURLWithPath: "/tmp/clawix-recording-mono.mov")

        let args = ScreenToolService.monoRecordingAudioArguments(input: input, output: output)

        XCTAssertEqual(args, [
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", "copy",
            "-c:a", "aac",
            "-ac", "1",
            "-movflags", "+faststart",
            output.path
        ])
    }

    @MainActor
    func testRecordingPostProcessingArgumentsCanScaleAndConvertAudioTogether() {
        let input = URL(fileURLWithPath: "/tmp/clawix-recording.mov")
        let output = URL(fileURLWithPath: "/tmp/clawix-recording-processed.mov")

        let args = ScreenToolService.recordingPostProcessingArguments(
            input: input,
            output: output,
            scaleRetinaTo1x: true,
            monoAudio: true
        )

        XCTAssertEqual(args, [
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-filter:v", "scale=trunc(iw/4)*2:trunc(ih/4)*2",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "18",
            "-c:a", "aac",
            "-ac", "1",
            "-movflags", "+faststart",
            output.path
        ])
    }
}
