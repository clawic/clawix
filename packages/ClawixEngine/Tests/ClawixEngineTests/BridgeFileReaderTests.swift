import XCTest
@testable import ClawixEngine

final class BridgeFileReaderTests: XCTestCase {
    func testDirectoryPathReturnsReadableListing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-bridge-file-reader-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("artifact-folder", isDirectory: true)
        let childFolder = folder.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        try "hello".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = BridgeFileReader.load(path: folder.path)

        XCTAssertNil(result.error)
        XCTAssertFalse(result.isMarkdown)
        XCTAssertTrue(result.content?.contains("child/") == true)
        XCTAssertTrue(result.content?.contains("notes.txt") == true)
    }

    func testEmptyDirectoryPathReturnsReadablePlaceholder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-bridge-empty-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = BridgeFileReader.load(path: root.path)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.content, "(empty folder)")
    }
}
