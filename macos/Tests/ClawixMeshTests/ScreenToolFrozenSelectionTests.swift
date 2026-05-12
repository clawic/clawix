import AppKit
import XCTest
@testable import Clawix

final class ScreenToolFrozenSelectionTests: XCTestCase {
    @MainActor
    func testWriteFrozenSelectionCropsSelectedArea() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-frozen-selection-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try Self.makeFixtureImage(pixelsWide: 40, pixelsHigh: 20, pointsWide: 20, pointsHigh: 10)
        let changed = try ScreenToolService.writeFrozenSelection(
            from: image,
            selectionRect: NSRect(x: 5, y: 2, width: 8, height: 4),
            to: url
        )
        let rep = try XCTUnwrap(NSImage(contentsOf: url)?.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        XCTAssertTrue(changed)
        XCTAssertEqual(rep.pixelsWide, 16)
        XCTAssertEqual(rep.pixelsHigh, 8)
    }

    private static func makeFixtureImage(
        pixelsWide: Int,
        pixelsHigh: Int,
        pointsWide: CGFloat,
        pointsHigh: CGFloat
    ) throws -> NSImage {
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
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
