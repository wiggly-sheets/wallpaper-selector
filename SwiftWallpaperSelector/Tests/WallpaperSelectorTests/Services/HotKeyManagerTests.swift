import XCTest
@testable import WallpaperSelector

@MainActor
final class HotKeyManagerTests: XCTestCase {
    func testParsesElectronAccelerator() throws {
        let context = try TestSettingsContext()
        let manager = HotKeyManager(settingsManager: context.makeSettingsManager())
        let combo = manager.parseAccelerator("CommandOrControl+Shift+S")

        XCTAssertEqual(combo?.keyCode, 1)
        XCTAssertNotNil(combo)
    }

    func testParsesRecorderGlyphAccelerator() throws {
        let context = try TestSettingsContext()
        let manager = HotKeyManager(settingsManager: context.makeSettingsManager())
        let combo = manager.parseAccelerator("⌘⇧F12")

        XCTAssertEqual(combo?.keyCode, 111)
    }
}
