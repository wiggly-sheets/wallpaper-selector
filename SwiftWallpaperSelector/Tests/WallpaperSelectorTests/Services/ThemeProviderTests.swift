import XCTest
@testable import WallpaperSelector

@MainActor
final class ThemeProviderTests: XCTestCase {
    /// The pins of the selected theme are used, not the pins of all folders.
    /// Both kinds of pins have to survive the normalization, so the test can
    /// tell them apart.
    func testSelectedThemeDoesNotFallbackToAllFoldersPins() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/theme-light.jpg",
            darkWallpaper: "/wallpapers/theme-dark.jpg"
        )
        manager.replace(WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [theme],
            activeThemeID: theme.id,
            allFoldersLightWallpaper: "/wallpapers/light.jpg",
            allFoldersDarkWallpaper: "/wallpapers/dark.jpg"
        ))

        let pair = ThemeProvider(settingsManager: manager).effectiveAppearanceWallpapers(isDarkAppearance: false)

        // The pins of all folders are other images, so the test fails when
        // they are returned instead of the pins of the theme.
        XCTAssertEqual(pair.light, "/wallpapers/theme-light.jpg")
        XCTAssertEqual(pair.dark, "/wallpapers/theme-dark.jpg")
    }

    func testAppearanceThemeWinsWhileAppearanceMatchingIsOn() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let userTheme = Theme(id: "user", name: "User", folderPaths: ["/user"])
        let darkTheme = Theme(id: "dark", name: "Dark", folderPaths: ["/dark"])
        manager.replace(WallpaperSettings(
            folderPaths: ["/user", "/dark"],
            themes: [userTheme, darkTheme],
            activeThemeID: userTheme.id,
            matchSystemAppearance: true,
            appearanceLightThemeID: userTheme.id,
            appearanceDarkThemeID: darkTheme.id
        ))
        let provider = ThemeProvider(settingsManager: manager)

        XCTAssertEqual(provider.effectiveThemeID(isDarkAppearance: true), darkTheme.id)
        XCTAssertEqual(provider.effectiveThemeID(isDarkAppearance: false), userTheme.id)
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: true), ["/dark"])
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: false), ["/user"])
    }

    func testUserThemeWinsWhileAppearanceMatchingIsOff() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let userTheme = Theme(id: "user", name: "User", folderPaths: ["/user"])
        let darkTheme = Theme(id: "dark", name: "Dark", folderPaths: ["/dark"])
        manager.replace(WallpaperSettings(
            folderPaths: ["/user", "/dark"],
            themes: [userTheme, darkTheme],
            activeThemeID: userTheme.id,
            matchSystemAppearance: false,
            appearanceLightThemeID: userTheme.id,
            appearanceDarkThemeID: darkTheme.id
        ))
        let provider = ThemeProvider(settingsManager: manager)

        XCTAssertEqual(provider.effectiveThemeID(isDarkAppearance: true), userTheme.id)
        XCTAssertEqual(provider.effectiveThemeID(isDarkAppearance: false), userTheme.id)
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: true), ["/user"])
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: false), ["/user"])
    }

    func testAllFoldersAreTheScopeWhenThereIsNoEffectiveTheme() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        manager.replace(WallpaperSettings(
            folderPaths: ["/one", "/two"],
            matchSystemAppearance: true
        ))
        let provider = ThemeProvider(settingsManager: manager)

        XCTAssertNil(provider.effectiveThemeID(isDarkAppearance: true))
        XCTAssertNil(provider.effectiveThemeID(isDarkAppearance: false))
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: true), ["/one", "/two"])
        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: false), ["/one", "/two"])
    }

    /// A theme without folders must not empty the scope: the folders are
    /// configured, so the global list is the right scope.
    func testAllFoldersAreTheScopeWhenTheEffectiveThemeHasNoFolders() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let theme = Theme(id: "empty", name: "Empty", folderPaths: [])
        manager.replace(WallpaperSettings(
            folderPaths: ["/one", "/two"],
            themes: [theme],
            activeThemeID: theme.id
        ))
        let provider = ThemeProvider(settingsManager: manager)

        XCTAssertEqual(provider.effectiveFolders(isDarkAppearance: false), ["/one", "/two"])
    }
}
