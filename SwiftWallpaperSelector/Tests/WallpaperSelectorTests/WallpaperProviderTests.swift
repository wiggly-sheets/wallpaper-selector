import XCTest
@testable import WallpaperSelector

final class WallpaperProviderTests: XCTestCase {
    // MARK: - Mock provider

    func testMockProviderRecordsCalls() {
        let mock = MockWallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/test.jpg")

        try! mock.setWallpaper(url, forAllScreens: false)
        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].url, url)
        XCTAssertEqual(mock.calls[0].forAllScreens, false)

        try! mock.setWallpaper(url, forAllScreens: true)
        XCTAssertEqual(mock.calls.count, 2)
        XCTAssertEqual(mock.calls[1].forAllScreens, true)
    }

    func testMockProviderThrowsWhenConfigured() {
        let mock = MockWallpaperProvider()
        mock.throwError = true
        mock.errorToThrow = WallpaperProviderError.noMainScreen

        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        XCTAssertThrowsError(try mock.setWallpaper(url, forAllScreens: false)) { error in
            XCTAssertTrue(error is WallpaperProviderError)
        }
    }

    func testMockProviderReset() {
        let mock = MockWallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/test.jpg")

        try! mock.setWallpaper(url, forAllScreens: false)
        XCTAssertEqual(mock.calls.count, 1)

        mock.reset()
        XCTAssertEqual(mock.calls.count, 0)
        XCTAssertFalse(mock.throwError)
    }

    // MARK: - Real provider error cases

    func testRealProviderThrowsNoMainScreen() {
        let provider = WallpaperProvider()
        let url = URL(fileURLWithPath: "/tmp/nonexistent-wallpaper.jpg")
        // When there's no main screen (or the file doesn't exist), the provider
        // should throw rather than crash. We can't guarantee a main screen in
        // the test environment, so we just verify it throws an error.
        XCTAssertThrowsError(try provider.setWallpaper(url, forAllScreens: false))
    }
}