import XCTest
@testable import WallpaperSelector

final class ShortcutsCodableTests: XCTestCase {
    /// One wrong-typed shortcut must not wipe the other ones.
    func testAWrongTypedShortcutDoesNotWipeTheOtherShortcuts() throws {
        let data = Data("""
        {"showMain":42,"showPreview":"cmd+2","showMenu":"cmd+3"}
        """.utf8)

        let shortcuts = try JSONDecoder().decode(Shortcuts.self, from: data)

        XCTAssertNil(shortcuts.showMain)
        XCTAssertEqual(shortcuts.showPreview, "cmd+2")
        XCTAssertEqual(shortcuts.showMenu, "cmd+3")
    }

    func testAWrongTypedShortcutDoesNotRejectTheSettingsFile() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"rotationAction":"next","shortcuts":{"showMain":42,"showPreview":"cmd+2"}}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertNil(settings.shortcuts.showMain)
        XCTAssertEqual(settings.shortcuts.showPreview, "cmd+2")
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.rotationAction, .next)
    }

    func testTheShortcutsKeepTheirKeysWhenTheyAreEncoded() throws {
        let data = try JSONEncoder().encode(
            Shortcuts(showMain: "cmd+1", showPreview: "cmd+2", showMenu: "cmd+3")
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["showMain"] as? String, "cmd+1")
        XCTAssertEqual(json?["showPreview"] as? String, "cmd+2")
        XCTAssertEqual(json?["showMenu"] as? String, "cmd+3")
    }
}
