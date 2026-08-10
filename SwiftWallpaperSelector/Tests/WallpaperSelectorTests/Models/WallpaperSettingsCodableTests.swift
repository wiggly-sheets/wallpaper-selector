import XCTest
@testable import WallpaperSelector

final class WallpaperSettingsCodableTests: XCTestCase {
    func testDecodesElectronCamelCaseSchema() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"currentWallpaper":"/wallpapers/a.jpg","intervalMinutes":60,"rotationAction":"next","allSpaces":true,"shortcuts":{"showMain":"⌘⇧W","showPreview":null,"showMenu":null},"themes":[],"activeThemeId":"theme-1","matchSystemAppearance":true,"allFoldersLightWallpaper":"/wallpapers/light.jpg","allFoldersDarkWallpaper":null,"appearanceLightThemeId":"theme-1","appearanceDarkThemeId":null,"historyLimit":20,"wallpaperHistory":["/wallpapers/a.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.activeThemeID, "theme-1")
        XCTAssertEqual(settings.appearanceLightThemeID, "theme-1")
        XCTAssertEqual(settings.intervalMinutes, .hour1)
        XCTAssertEqual(settings.historyLimit, 20)
    }

    func testMigratesLegacySingleFolderAndRelativeWallpaper() throws {
        let data = Data("{\"folderPath\":\"/wallpapers\",\"currentWallpaper\":\"sunset.jpg\"}".utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.currentWallpaper, "/wallpapers/sunset.jpg")
        XCTAssertEqual(settings.rotationAction, .shuffle)
    }

    func testEncodesElectronCamelCaseKeys() throws {
        let data = try JSONEncoder().encode(WallpaperSettings(activeThemeID: "theme-1", appearanceDarkThemeID: "theme-2"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["activeThemeId"] as? String, "theme-1")
        XCTAssertEqual(json?["appearanceDarkThemeId"] as? String, "theme-2")
        XCTAssertNil(json?["activeThemeID"])
    }
}
