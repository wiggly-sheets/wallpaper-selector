import Carbon
import XCTest
@testable import WallpaperSelector

@MainActor
final class HotKeyManagerTests: XCTestCase {
    func testParsesElectronAccelerator() throws {
        let context = try TestSettingsContext()
        let manager = HotKeyManager(settingsManager: context.makeSettingsManager())
        let combo = try XCTUnwrap(manager.parseAccelerator("CommandOrControl+Shift+S"))

        XCTAssertEqual(combo.keyCode, 1)
        XCTAssertEqual(combo.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testParsesRecorderGlyphAccelerator() throws {
        let context = try TestSettingsContext()
        let manager = HotKeyManager(settingsManager: context.makeSettingsManager())
        let combo = try XCTUnwrap(manager.parseAccelerator("⌘⇧F12"))

        XCTAssertEqual(combo.keyCode, 111)
        XCTAssertEqual(combo.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testUnreadableShortcutIsReportedAsRegistrationFailure() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        settingsManager.update { $0.shortcuts = Shortcuts(showMain: "not a shortcut") }
        let manager = HotKeyManager(settingsManager: settingsManager)
        var reportedError: String?
        var didReport = false
        manager.onRegistrationError = { error in
            didReport = true
            reportedError = error
        }

        manager.register()

        XCTAssertTrue(didReport)
        XCTAssertNotNil(reportedError)
        XCTAssertTrue(reportedError?.contains("not a shortcut") == true)
    }

    func testRegistrationWithoutShortcutsReportsNoError() throws {
        let context = try TestSettingsContext()
        let manager = HotKeyManager(settingsManager: context.makeSettingsManager())
        var reportedError: String?
        var didReport = false
        manager.onRegistrationError = { error in
            didReport = true
            reportedError = error
        }

        manager.register()

        XCTAssertTrue(didReport)
        XCTAssertNil(reportedError)
    }
}
