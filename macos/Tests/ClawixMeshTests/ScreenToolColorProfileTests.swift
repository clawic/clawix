import AppKit
import XCTest
@testable import Clawix

final class ScreenToolColorProfileTests: XCTestCase {
    @MainActor
    func testConvertImageToSRGBWritesSRGBColorSpace() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-srgb-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeDisplayP3Fixture(url: url)

        let changed = try ScreenToolService.convertImageToSRGB(url)
        let image = try XCTUnwrap(NSImage(contentsOf: url))
        let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        XCTAssertTrue(changed)
        XCTAssertEqual(rep.pixelsWide, 20)
        XCTAssertEqual(rep.pixelsHigh, 10)
        XCTAssertEqual(rep.cgImage?.colorSpace?.name as String?, CGColorSpace.sRGB as String)
    }

    private static func writeDisplayP3Fixture(url: URL) throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 20,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))

        let cgImage = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: 20, height: 10)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}
