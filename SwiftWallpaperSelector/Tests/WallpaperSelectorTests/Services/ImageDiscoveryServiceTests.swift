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

    func testCollectImageURLsSkipsDirectoriesNamedLikeImages() throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try createFile(at: folder, name: "real.png")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("looks-like-an-image.png"),
            withIntermediateDirectories: true
        )

        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path])

        XCTAssertEqual(
            result.map { $0.lastPathComponent },
            ["real.png"],
            "A directory that is named like an image is not a wallpaper"
        )
    }

    func testCollectImageURLsHandlesEmptyFolder() throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path])
        XCTAssertTrue(result.isEmpty, "Empty folder should produce an empty result array")
    }

    /// Overlapping folders must not list the same file twice.
    func testCollectImageURLsSkipsAFileThatWasAlreadyCollected() throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try createFile(at: folder, name: "a.png")
        try createFile(at: folder, name: "b.png")

        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path, folder.path + "/"])

        XCTAssertEqual(
            result.map { $0.lastPathComponent },
            ["a.png", "b.png"],
            "A file that was already collected must not be listed twice"
        )
    }

    /// Two folders that reach the same file through a symlink are the same
    /// file: it must not be listed twice.
    func testCollectImageURLsSkipsAFileThatWasAlreadyCollectedThroughASymlink() throws {
        let folder = try createTempFolder()
        let linkedFolder = try createTempFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: linkedFolder)
        }

        try createFile(at: folder, name: "a.png")
        try createFile(at: folder, name: "b.png")
        // The second folder reaches the same files through a symlink.
        for name in ["a.png", "b.png"] {
            try FileManager.default.createSymbolicLink(
                at: linkedFolder.appendingPathComponent(name),
                withDestinationURL: folder.appendingPathComponent(name)
            )
        }

        let result = ImageDiscoveryService.collectImageURLs(from: [folder.path, linkedFolder.path])

        XCTAssertEqual(
            result.map { $0.lastPathComponent },
            ["a.png", "b.png"],
            "A file that was already collected through a symlink must not be listed twice"
        )
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
