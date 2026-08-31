import XCTest
@testable import WallpaperSelector

@MainActor
final class WallpaperProviderTests: XCTestCase {

    func testMockProviderRecordsCalls() {
        let mock = MockWallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/test.jpg")

        try! mock.setWallpaper(url)
        XCTAssertEqual(mock.appliedURLs, [url])

        try! mock.setWallpaper(url)
        XCTAssertEqual(mock.appliedURLs, [url, url])
    }

    func testMockProviderThrowsWhenConfigured() {
        let mock = MockWallpaperProvider()
        mock.errorToThrow = MockWallpaperProviderError.configuredFailure

        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        XCTAssertThrowsError(try mock.setWallpaper(url)) { error in
            XCTAssertTrue(error is MockWallpaperProviderError)
        }
    }

    func testMockProviderReset() {
        let mock = MockWallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/test.jpg")

        try! mock.setWallpaper(url)
        XCTAssertEqual(mock.appliedURLs.count, 1)

        mock.reset()
        XCTAssertEqual(mock.appliedURLs.count, 0)
        XCTAssertNil(mock.errorToThrow)
    }


    func testProviderRejectsMissingWallpaperBeforeTouchingDisplays() {
        var didApply = false
        let provider = WallpaperProvider { _ in
            didApply = true
            return [.success(())]
        }
        let url = URL(fileURLWithPath: "/tmp/nonexistent-wallpaper-\(UUID().uuidString).jpg")

        XCTAssertThrowsError(try provider.setWallpaper(url))
        XCTAssertFalse(didApply)
    }

    func testProviderAppliesWallpaperToEveryResolvedDisplay() throws {
        let url = try makeTemporaryWallpaper()
        defer { try? FileManager.default.removeItem(at: url) }
        var appliedURLs: [URL] = []
        let provider = WallpaperProvider { url in
            appliedURLs.append(contentsOf: [url, url, url])
            return [.success(()), .success(()), .success(())]
        }

        try provider.setWallpaper(url)

        XCTAssertEqual(appliedURLs, [url, url, url])
    }

    func testProviderReportsNoDisplays() throws {
        let url = try makeTemporaryWallpaper()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = WallpaperProvider { _ in [] }

        XCTAssertThrowsError(try provider.setWallpaper(url)) { error in
            guard case WallpaperProviderError.noScreens = error else {
                return XCTFail("Expected noScreens, got \(error)")
            }
        }
    }

    func testProviderAggregatesPartialDisplayFailures() throws {
        let url = try makeTemporaryWallpaper()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = WallpaperProvider { _ in
            [.success(()), .failure(MockWallpaperProviderError.configuredFailure), .success(())]
        }

        XCTAssertThrowsError(try provider.setWallpaper(url)) { error in
            guard case let WallpaperProviderError.failedToSetOnDisplays(failed, total, _) = error else {
                return XCTFail("Expected display failure, got \(error)")
            }
            XCTAssertEqual(failed, 1)
            XCTAssertEqual(total, 3)
        }
    }

    private func makeTemporaryWallpaper() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallpaperProviderTests-\(UUID().uuidString).jpg")
        try Data("image".utf8).write(to: url)
        return url
    }

    func testRealProviderThrowsForMissingWallpaper() {
        let provider = WallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/nonexistent-wallpaper-\(UUID().uuidString).jpg")
        XCTAssertThrowsError(try provider.setWallpaper(url))
    }
}
