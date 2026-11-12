import XCTest
@testable import WallpaperSelector

final class WallpaperThumbnailRepositoryTests: XCTestCase {
    func testCacheKeepsTheNewestEntriesAndCanBePurged() async throws {
        let repository = WallpaperThumbnailRepository()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // One more image than the cache may hold.
        let urls = try (0..<65).map { index -> URL in
            let url = directory.appendingPathComponent("image-\(index).png")
            try Self.pngData.write(to: url)
            try Self.fixModificationDate(of: url)
            return url
        }

        for url in urls {
            let thumbnail = await repository.thumbnail(for: url, maximumPixelSize: 32)
            XCTAssertNotNil(thumbnail)
        }

        // The oldest entry left the cache, so the file is decoded again.
        try Self.corrupt(urls[0])
        let evicted = await repository.thumbnail(for: urls[0], maximumPixelSize: 32)
        XCTAssertNil(evicted)

        // The newest entry is still cached.
        try Self.corrupt(urls[64])
        let cached = await repository.thumbnail(for: urls[64], maximumPixelSize: 32)
        XCTAssertNotNil(cached)

        // A purge drops the cached thumbnail.
        await repository.purge()
        let purged = await repository.thumbnail(for: urls[64], maximumPixelSize: 32)
        XCTAssertNil(purged)
    }

    /// A corrupt or unsupported file is decoded once. The failure stays in
    /// the cache, so scrolling over it does not decode it again.
    func testADecodeFailureIsCachedUntilTheCacheIsPurged() async throws {
        let repository = WallpaperThumbnailRepository()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: url)
        try Self.fixModificationDate(of: url)

        let first = await repository.thumbnail(for: url, maximumPixelSize: 32)
        XCTAssertNil(first)

        // The file becomes a valid image without a new modification date, so
        // the cache key stays the same. A cached failure means the valid
        // file is not decoded yet.
        try Self.pngData.write(to: url)
        try Self.fixModificationDate(of: url)
        let cachedFailure = await repository.thumbnail(for: url, maximumPixelSize: 32)
        XCTAssertNil(cachedFailure)

        // The purge drops the failure too, so the valid file is decoded.
        await repository.purge()
        let purged = await repository.thumbnail(for: url, maximumPixelSize: 32)
        XCTAssertNotNil(purged)
    }

    /// A cached failure expires: a file that was being written when it was
    /// decoded is tried again after the lifetime.
    func testADecodeFailureIsRetriedAfterItsLifetime() async throws {
        let repository = WallpaperThumbnailRepository(failureLifetime: 0)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: url)
        try Self.fixModificationDate(of: url)

        let first = await repository.thumbnail(for: url, maximumPixelSize: 32)
        XCTAssertNil(first)

        // The file becomes a valid image without a new modification date, so
        // the cache key stays the same. The expired failure has to be dropped
        // and the file decoded again.
        try Self.pngData.write(to: url)
        try Self.fixModificationDate(of: url)
        let retried = await repository.thumbnail(for: url, maximumPixelSize: 32)
        XCTAssertNotNil(retried, "An expired failure must be retried")
    }

    /// Replaces the file content without changing its modification date, so the
    /// cache key stays the same.
    private static func corrupt(_ url: URL) throws {
        try Data("not an image".utf8).write(to: url)
        try fixModificationDate(of: url)
    }

    private static func fixModificationDate(of url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: url.path
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WallpaperThumbnailRepositoryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!
}
