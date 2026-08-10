import XCTest
@testable import WallpaperSelector

// Minimal dummy wallpaper provider to satisfy AppState initializer.
final class DummyWallpaperProvider: WallpaperSetting {
    private(set) var appliedURLs: [URL] = []
    private(set) var allScreenFlags: [Bool] = []

    func setWallpaper(_ url: URL, forAllScreens: Bool) throws {
        appliedURLs.append(url)
        allScreenFlags.append(forAllScreens)
    }
}

final class SettingsViewModelTests: XCTestCase {
    var appState: AppState!
    var viewModel: SettingsViewModel!

    override func setUp() {
        super.setUp()
        // Create a fresh SettingsManager with default settings to avoid disk side effects.
        let settingsManager = SettingsManager()
        // Reset to a clean settings model.
        settingsManager.replace(WallpaperSettings())

        // Create AppState with dummy dependencies for testing
        let dummyProvider = DummyWallpaperProvider()
        appState = AppState(
            settingsManager: settingsManager,
            themeProvider: ThemeProvider(settingsManager: settingsManager),
            wallpaperProvider: dummyProvider
        )
        viewModel = SettingsViewModel(appState: appState)
    }

    override func tearDown() {
        viewModel = nil
        appState = nil
        super.tearDown()
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

    func testSetWallpaperFromAbsolutePathUsesFileURLAndEveryDisplay() {
        let provider = DummyWallpaperProvider()
        let state = AppState(
            settingsManager: appState.settingsManager,
            themeProvider: ThemeProvider(settingsManager: appState.settingsManager),
            wallpaperProvider: provider
        )

        state.setWallpaper("/tmp/wallpaper.jpg")

        XCTAssertEqual(provider.appliedURLs, [URL(fileURLWithPath: "/tmp/wallpaper.jpg")])
        XCTAssertEqual(provider.allScreenFlags, [true])
        XCTAssertEqual(state.settings.currentWallpaper, "/tmp/wallpaper.jpg")
    }

    func testHistoryLimitKeepsMostRecentWallpapers() {
        appState.updateSettings { settings in
            settings.wallpaperHistory = ["newest", "second", "third", "fourth", "fifth", "oldest"]
        }

        viewModel.setHistoryLimit(5)

        XCTAssertEqual(appState.settings.wallpaperHistory, ["newest", "second", "third", "fourth", "fifth"])
    }
}
