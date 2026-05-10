import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DictationProcessingTests: XCTestCase {
    func testWhisperSpecialTokenOnlyTranscriptIsTreatedAsEmpty() {
        let raw = """
        <|startoftranscript|><|en|><|transcribe|><|0.00|><|endoftext|>

        <|startoftranscript|><|en|><|transcribe|><|0.00|><|endoftext|>
        """

        XCTAssertEqual(DictationCoordinator.processForDelivery(raw, language: "en"), "")
    }

    func testWhisperSpecialTokensAreRemovedFromRealTranscript() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|0.00|>hello world<|1.20|><|endoftext|>"

        XCTAssertEqual(DictationCoordinator.processForDelivery(raw, language: "en"), "hello world")
    }

    func testLowEnergyCaptureSkipsWhisperDecode() {
        let silence = Array(repeating: Float(0.0004), count: 16_000)

        XCTAssertTrue(DictationCoordinator.shouldSkipWhisperDecode(samples: silence))
    }

    func testAudibleCaptureUsesWhisperDecode() {
        let audible = (0..<16_000).map { index in
            sin(Float(index) / 16.0) * 0.08
        }

        XCTAssertFalse(DictationCoordinator.shouldSkipWhisperDecode(samples: audible))
    }
}
