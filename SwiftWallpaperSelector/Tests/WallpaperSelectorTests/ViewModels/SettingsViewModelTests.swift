import XCTest
@testable import WallpaperSelector

@MainActor
final class SettingsViewModelTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var wallpaperProvider: MockWallpaperProvider!
    var rotationService: RotationService!
    var appState: AppState!
    var viewModel: SettingsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        settingsManager.replace(WallpaperSettings())

        wallpaperProvider = MockWallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let wallpaperLibrary = WallpaperLibrary()
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
        appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
        viewModel = SettingsViewModel(appState: appState)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        appState = nil
        rotationService = nil
        wallpaperProvider = nil
        settingsManager = nil
        settingsContext = nil
        try super.tearDownWithError()
    }

    func testAddFolderUpdatesPublishedPropertyAndAppState() {
        XCTAssertTrue(viewModel.folderPaths.isEmpty)
        viewModel.addFolder("/tmp")
        XCTAssertEqual(viewModel.folderPaths, ["/tmp"])
        XCTAssertEqual(appState.settings.folderPaths, ["/tmp"])
    }

    func testAddThemeUpdatesPublishedPropertyAndAppState() {
        XCTAssertTrue(viewModel.themes.isEmpty)
        let theme = Theme(name: "Test Theme", folderPaths: ["/tmp"])
        viewModel.addTheme(theme)
        XCTAssertEqual(viewModel.themes.count, 1)
        XCTAssertEqual(viewModel.themes.first?.name, "Test Theme")
        XCTAssertEqual(appState.settings.themes.first?.name, "Test Theme")
    }

    func testToggleMatchSystemAppearance() {
        XCTAssertFalse(viewModel.matchSystemAppearance)
        viewModel.toggleMatchSystemAppearance()
        XCTAssertTrue(viewModel.matchSystemAppearance)
        XCTAssertTrue(appState.settings.matchSystemAppearance)
        viewModel.toggleMatchSystemAppearance()
        XCTAssertFalse(viewModel.matchSystemAppearance)
    }

    func testSettersWriteThroughToAppState() {
        viewModel.setAllSpaces(true)
        viewModel.setMatchSystemAppearance(true)
        viewModel.setInterval(.hour1)
        viewModel.setRotationAction(.themeNext)

        XCTAssertTrue(appState.settings.allSpaces)
        XCTAssertTrue(appState.settings.matchSystemAppearance)
        XCTAssertEqual(appState.settings.intervalMinutes, .hour1)
        XCTAssertEqual(appState.settings.rotationAction, .themeNext)
    }

    func testAppearanceOverridesWriteThroughToAppState() {
        viewModel.addFolder("/tmp")
        viewModel.addTheme(Theme(id: "light-theme", name: "Light", folderPaths: []))
        viewModel.addTheme(Theme(id: "dark-theme", name: "Dark", folderPaths: []))
        viewModel.setAppearanceOverrides(
            lightThemeID: "light-theme",
            darkThemeID: "dark-theme",
            lightWallpaper: "/tmp/light.jpg",
            darkWallpaper: "/tmp/dark.jpg"
        )

        XCTAssertEqual(appState.settings.appearanceLightThemeID, "light-theme")
        XCTAssertEqual(appState.settings.appearanceDarkThemeID, "dark-theme")
        XCTAssertEqual(appState.settings.allFoldersLightWallpaper, "/tmp/light.jpg")
        XCTAssertEqual(appState.settings.allFoldersDarkWallpaper, "/tmp/dark.jpg")
    }

    func testUpdateShortcuts() {
        let shortcuts = Shortcuts(showMain: "cmd+1")
        viewModel.setShortcuts(shortcuts)
        XCTAssertEqual(viewModel.shortcuts.showMain, "cmd+1")
        XCTAssertEqual(appState.settings.shortcuts.showMain, "cmd+1")
    }

    func testAssigningShortcutClearsSameShortcutFromOtherActions() {
        viewModel.setShortcuts(Shortcuts(
            showMain: "cmd+1",
            showPreview: "cmd+2",
            showMenu: "cmd+3"
        ))

        viewModel.setShowPreviewShortcut("cmd+1")

        XCTAssertNil(appState.settings.shortcuts.showMain)
        XCTAssertEqual(appState.settings.shortcuts.showPreview, "cmd+1")
        XCTAssertEqual(appState.settings.shortcuts.showMenu, "cmd+3")
    }

    func testSetWallpaperFromAbsolutePathUsesFileURLAndEveryDisplay() {
        appState.setWallpaper("/tmp/wallpaper.jpg")

        XCTAssertEqual(wallpaperProvider.appliedURLs, [URL(fileURLWithPath: "/tmp/wallpaper.jpg")])
        XCTAssertEqual(appState.settings.currentWallpaper, "/tmp/wallpaper.jpg")
    }

    func testHistoryLimitKeepsMostRecentWallpapers() {
        appState.updateSettings { settings in
            settings.wallpaperHistory = ["newest", "second", "third", "fourth", "fifth", "oldest"]
        }

        viewModel.setHistoryLimit(5)

        XCTAssertEqual(appState.settings.wallpaperHistory, ["newest", "second", "third", "fourth", "fifth"])
    }

    func testEditFolderPreservesOrderAndUpdatesThemeReferences() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/first", "/old", "/last"]
            settings.themes = [
                Theme(id: "theme", name: "Theme", folderPaths: ["/old", "/last"])
            ]
        }

        viewModel.replaceFolder(oldPath: "/old", with: "/replacement")

        XCTAssertEqual(appState.settings.folderPaths, ["/first", "/replacement", "/last"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/replacement", "/last"])
    }

    func testEditFolderRejectsDuplicateDestination() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/first", "/second"]
            settings.themes = [Theme(id: "theme", name: "Theme", folderPaths: ["/first"])]
        }

        viewModel.replaceFolder(oldPath: "/first", with: "/second")

        XCTAssertEqual(appState.settings.folderPaths, ["/first", "/second"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/first"])
    }

    func testRemoveFolderAlsoRemovesThemeReferences() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/remove", "/keep"]
            settings.themes = [
                Theme(id: "theme", name: "Theme", folderPaths: ["/remove", "/keep"])
            ]
        }

        viewModel.removeFolder("/remove")

        XCTAssertEqual(appState.settings.folderPaths, ["/keep"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/keep"])
    }

    func testRemoveThemeClearsEveryThemeReference() {
        let theme = Theme(id: "remove", name: "Theme", folderPaths: [])
        appState.updateSettings { settings in
            settings.themes = [theme]
            settings.activeThemeID = theme.id
            settings.appearanceLightThemeID = theme.id
            settings.appearanceDarkThemeID = theme.id
        }

        viewModel.removeTheme(id: theme.id)

        XCTAssertTrue(appState.settings.themes.isEmpty)
        XCTAssertNil(appState.settings.activeThemeID)
        XCTAssertNil(appState.settings.appearanceLightThemeID)
        XCTAssertNil(appState.settings.appearanceDarkThemeID)
    }

    func testReplaceThemeCanExplicitlyClearAppearancePins() {
        let theme = Theme(
            id: "theme",
            name: "Before",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { $0.themes = [theme] }

        viewModel.replaceTheme(
            id: theme.id,
            with: Theme(id: "ignored", name: "After", folderPaths: ["/wallpapers"])
        )

        XCTAssertEqual(appState.settings.themes[0].id, theme.id)
        XCTAssertEqual(appState.settings.themes[0].name, "After")
        XCTAssertNil(appState.settings.themes[0].lightWallpaper)
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }

    func testAppearanceWallpaperSetterClearsPinsForSpecificTheme() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { $0.themes = [theme] }

        viewModel.setAppearanceWallpapers(light: nil, dark: nil, forThemeID: theme.id)

        XCTAssertNil(appState.settings.themes[0].lightWallpaper)
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }

    func testAppearanceConfigurationUpdatesMappingAndClearsPinsAtomically() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { settings in
            settings.themes = [theme]
            settings.appearanceLightThemeID = theme.id
            settings.appearanceDarkThemeID = theme.id
        }

        viewModel.setAppearanceConfiguration(
            lightThemeID: nil,
            darkThemeID: theme.id,
            lightWallpaper: nil,
            darkWallpaper: nil,
            forThemeID: theme.id
        )

        XCTAssertNil(appState.settings.appearanceLightThemeID)
        XCTAssertEqual(appState.settings.appearanceDarkThemeID, theme.id)
        XCTAssertNil(appState.settings.themes[0].lightWallpaper)
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }
}
