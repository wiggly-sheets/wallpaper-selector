import XCTest
@testable import WallpaperSelector

final class ImageDiscoveryServiceTests: XCTestCase {
    private func createTempFolder() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        return folder
    }

    private func createFile(at folder: URL, name: String) throws {
        let fileURL = folder.appendingPathComponent(name)
        try "dummy".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func testCollectImageURLsReturnsOnlyImages() throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try createFile(at: folder, name: "a.png")
        try createFile(at: folder, name: "b.jpg")
        try createFile(at: folder, name: "c.txt")
        try createFile(at: folder, name: "d.JPEG")
        try createFile(at: folder, name: "e.webp")
        try createFile(at: folder, name: "f.gif")

        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path])
        let expected = ["a.png", "b.jpg", "d.JPEG", "e.webp"].map { folder.appendingPathComponent($0) }
        XCTAssertEqual(result.map { $0.standardizedFileURL }, expected.map { $0.standardizedFileURL }, "ImageDiscoveryService should return only supported image files")
    }

    func testCollectImageURLsHandlesEmptyFolder() throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path])
        XCTAssertTrue(result.isEmpty, "Empty folder should produce an empty result array")
    }

    func testCollectImageURLsMergesMultipleFolders() throws {
        let folder1 = try createTempFolder()
        let folder2 = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder1); try? FileManager.default.removeItem(at: folder2) }

        try createFile(at: folder1, name: "img1.png")
        try createFile(at: folder1, name: "doc1.txt")
        try createFile(at: folder2, name: "img2.jpg")
        try createFile(at: folder2, name: "img3.webp")
        try createFile(at: folder2, name: "notes.md")

        let result = ImageDiscoveryService.collectImageURLs(from: [folder1.path, folder2.path])
        let expected = [
            folder1.appendingPathComponent("img1.png"),
            folder2.appendingPathComponent("img2.jpg"),
            folder2.appendingPathComponent("img3.webp")
        ]
        XCTAssertEqual(result.map { $0.standardizedFileURL }, expected.map { $0.standardizedFileURL }, "ImageDiscoveryService should preserve configured folder order")
    }
}
