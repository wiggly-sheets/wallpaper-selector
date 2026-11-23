import XCTest
@testable import WallpaperSelector

@MainActor
final class TrayPopoverViewModelTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var appState: AppState!
    var rotationService: RotationService!
    var viewModel: TrayPopoverViewModel!

    override func setUpWithError() throws {
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: MockWallpaperProvider(),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )
        appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )
        viewModel = TrayPopoverViewModel(appState: appState)
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        viewModel = nil
        appState = nil
        rotationService = nil
        settingsManager = nil
        settingsContext = nil
    }

    /// The popover must show the new value right away, not one change later.
    func testSettingsChangeIsVisibleWithoutWaitingForTheRunLoop() {
        XCTAssertFalse(viewModel.allSpaces)
        XCTAssertFalse(viewModel.matchSystemAppearance)

        appState.updateSettings {
            $0.allSpaces = true
            $0.matchSystemAppearance = true
        }

        XCTAssertTrue(viewModel.allSpaces)
        XCTAssertTrue(viewModel.matchSystemAppearance)
    }

    /// The folders come from the effective folders, not from the raw settings.
    func testFolderPathsFollowTheEffectiveFolders() throws {
        let folder = settingsContext.directory(named: "wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A path with a trailing `.` component names the same folder but is
        // not the canonical path, so the view model has to normalize it.
        appState.updateSettings { $0.folderPaths = [folder.path + "/."] }

        // The `.` component is dropped, so the view model returns the
        // canonical path instead of the path the settings were given.
        XCTAssertEqual(viewModel.folderPaths, [folder.standardizedFileURL.path])
    }

    /// The theme actions can be used by hand at any time, but they need a
    /// theme and the system picks the theme while the appearance is matched.
    func testTheThemeActionsNeedAThemeAndAnUnmatchedAppearance() {
        // No theme, timer off: the actions are disabled.
        XCTAssertEqual(viewModel.intervalMinutes, .off)
        XCTAssertFalse(viewModel.isThemeActionEnabled)

        appState.updateSettings { $0.themes = [Theme(id: "theme", name: "Theme", folderPaths: [])] }
        XCTAssertTrue(viewModel.isThemeActionEnabled, "A theme action can be used while the timer is off")

        appState.updateSettings { $0.matchSystemAppearance = true }
        XCTAssertFalse(viewModel.isThemeActionEnabled)
    }

    /// The recent list follows the history order and skips files that are
    /// gone, because such a tile could not apply a wallpaper.
    func testRecentImagesFollowTheHistoryAndSkipMissingFiles() throws {
        let folder = settingsContext.directory(named: "wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("first.jpg")
        let second = folder.appendingPathComponent("second.jpg")
        try Data().write(to: first)
        try Data().write(to: second)
        let missing = folder.appendingPathComponent("missing.jpg")

        appState.updateSettings {
            $0.folderPaths = [folder.path]
            $0.wallpaperHistory = [missing.path, second.path, first.path]
        }
        viewModel.showsRecentOnly = true

        XCTAssertEqual(
            viewModel.displayedImages.map(\.lastPathComponent),
            ["second.jpg", "first.jpg"]
        )

        viewModel.showsRecentOnly = false
        XCTAssertEqual(viewModel.displayedImages, viewModel.images)
    }

    /// The buttons must grey out while a wallpaper change runs. The flag has
    /// to be published, so the view is redrawn.
    func testTheBusyFlagFollowsTheAppState() {
        var received: [Bool] = []
        let subscription = viewModel.$isBusy.sink { received.append($0) }
        defer { subscription.cancel() }

        XCTAssertFalse(viewModel.isBusy)

        appState.shuffleWallpaper()

        XCTAssertTrue(viewModel.isBusy)
        XCTAssertEqual(received, [false, true])
    }
}
