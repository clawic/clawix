import AppKit
import XCTest
@testable import Clawix

final class ScreenToolRetinaScalingTests: XCTestCase {
    @MainActor
    func testScaleRetinaImageTo1xDownscalesTwoXImage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-retina-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeFixture(url: url, pixelsWide: 40, pixelsHigh: 20, pointsWide: 20, pointsHigh: 10)

        let changed = try ScreenToolService.scaleRetinaImageTo1xIfNeeded(url)
        let rep = try XCTUnwrap(NSImage(contentsOf: url)?.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        XCTAssertTrue(changed)
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    @MainActor
    func testScaleRetinaImageTo1xLeavesOneXImageAlone() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-retina-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeFixture(url: url, pixelsWide: 20, pixelsHigh: 10, pointsWide: 20, pointsHigh: 10)

        let changed = try ScreenToolService.scaleRetinaImageTo1xIfNeeded(url)
        let rep = try XCTUnwrap(NSImage(contentsOf: url)?.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        XCTAssertFalse(changed)
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
    }

    private static func writeFixture(
        url: URL,
        pixelsWide: Int,
        pixelsHigh: Int,
        pointsWide: CGFloat,
        pointsHigh: CGFloat
    ) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: pointsWide, height: pointsHigh)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}
