import XCTest
@testable import WallpaperSelector

@MainActor
final class ThemeProviderTests: XCTestCase {
    func testSelectedThemeDoesNotFallbackToAllFoldersPins() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
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
