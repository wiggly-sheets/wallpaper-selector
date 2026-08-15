import XCTest
@testable import WallpaperSelector

final class HotKeyManagerTests: XCTestCase {
    func testParsesElectronAccelerator() {
        let manager = HotKeyManager(settingsManager: SettingsManager())
        let combo = manager.parseAccelerator("CommandOrControl+Shift+S")

        XCTAssertEqual(combo?.keyCode, 1)
        XCTAssertNotNil(combo)
    }

    func testParsesRecorderGlyphAccelerator() {
        let manager = HotKeyManager(settingsManager: SettingsManager())
        let combo = manager.parseAccelerator("⌘⇧F12")

        XCTAssertEqual(combo?.keyCode, 111)
    }
}
