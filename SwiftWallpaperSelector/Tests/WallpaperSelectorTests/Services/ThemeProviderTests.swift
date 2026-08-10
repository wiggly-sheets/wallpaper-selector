import XCTest
@testable import WallpaperSelector

final class ThemeProviderTests: XCTestCase {
    func testSelectedThemeDoesNotFallbackToAllFoldersPins() {
        let manager = SettingsManager()
        defer { manager.replace(WallpaperSettings()) }
        let theme = Theme(id: "theme", name: "Theme", folderPaths: ["/wallpapers"])
        manager.replace(WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [theme],
            activeThemeID: theme.id,
            allFoldersLightWallpaper: "/all/light.jpg",
            allFoldersDarkWallpaper: "/all/dark.jpg"
        ))

        let pair = ThemeProvider(settingsManager: manager).effectiveAppearanceWallpapers(isDarkAppearance: false)

        XCTAssertNil(pair.light)
        XCTAssertNil(pair.dark)
    }
}
