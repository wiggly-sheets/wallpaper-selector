import XCTest
@testable import WallpaperSelector

@MainActor
final class WallpaperProviderTests: XCTestCase {

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

    /// A display that accepted the wallpaper means the wallpaper is on the
    /// screen, even though another display refused it.
    func testTheProviderReportsThatAtLeastOneDisplayWasSet() throws {
        let url = try makeTemporaryWallpaper()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = WallpaperProvider { _ in
            [.success(()), .failure(MockWallpaperProviderError.configuredFailure)]
        }

        XCTAssertThrowsError(try provider.setWallpaper(url)) { error in
            guard let providerError = error as? WallpaperProviderError else {
                return XCTFail("Expected a wallpaper provider error, got \(error)")
            }
            XCTAssertTrue(providerError.didSetOnAtLeastOneDisplay)
        }
    }

    /// No display accepted the wallpaper, so nothing is on the screen.
    func testTheProviderReportsThatNoDisplayWasSet() throws {
        let url = try makeTemporaryWallpaper()
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = WallpaperProvider { _ in
            [.failure(MockWallpaperProviderError.configuredFailure)]
        }

        XCTAssertThrowsError(try provider.setWallpaper(url)) { error in
            guard let providerError = error as? WallpaperProviderError else {
                return XCTFail("Expected a wallpaper provider error, got \(error)")
            }
            XCTAssertFalse(providerError.didSetOnAtLeastOneDisplay)
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
