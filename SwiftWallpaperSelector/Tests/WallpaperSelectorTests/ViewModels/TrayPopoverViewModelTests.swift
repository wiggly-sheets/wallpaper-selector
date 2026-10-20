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

        appState.updateSettings { $0.allSpaces = true }

        XCTAssertTrue(viewModel.allSpaces)
    }

    /// The folders come from the effective folders, not from the raw settings.
    func testFolderPathsFollowTheEffectiveFolders() throws {
        let folder = settingsContext.directory(named: "wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        appState.updateSettings { $0.folderPaths = [folder.path] }

        XCTAssertEqual(viewModel.folderPaths, [folder.path])
    }

    /// The popover has to know when the system picks the theme, so it can
    /// disable the theme buttons.
    func testTheAppearanceMatchingIsVisibleToThePopover() {
        XCTAssertFalse(viewModel.matchSystemAppearance)

        appState.updateSettings { $0.matchSystemAppearance = true }

        XCTAssertTrue(viewModel.matchSystemAppearance)
    }

    /// The rotation cannot run while the appearance is matched, so the
    /// interval picker would do nothing. The flag states the effect, so a
    /// view binds it without negating it.
    func testTheRotationControlIsDisabledWhileTheAppearanceIsMatched() {
        XCTAssertFalse(viewModel.isRotationControlDisabled)

        appState.updateSettings { $0.matchSystemAppearance = true }

        XCTAssertTrue(viewModel.isRotationControlDisabled)
    }

    /// The theme actions can be used by hand at any time, so the rotation
    /// interval must not grey them out.
    func testTheThemeActionsAreEnabledWhileTheTimerIsOff() {
        XCTAssertEqual(viewModel.intervalMinutes, .off)
        appState.updateSettings { $0.themes = [Theme(id: "theme", name: "Theme", folderPaths: [])] }

        XCTAssertTrue(viewModel.isThemeActionEnabled)
    }

    /// A theme action without a theme changes nothing.
    func testTheThemeActionsAreDisabledWithoutATheme() {
        XCTAssertFalse(viewModel.isThemeActionEnabled)
    }

    /// While the appearance is matched, the system picks the theme: a theme
    /// action would show one theme and the wallpaper of another one.
    func testTheThemeActionsAreDisabledWhileTheAppearanceIsMatched() {
        appState.updateSettings { $0.themes = [Theme(id: "theme", name: "Theme", folderPaths: [])] }
        XCTAssertTrue(viewModel.isThemeActionEnabled)

        appState.updateSettings { $0.matchSystemAppearance = true }

        XCTAssertFalse(viewModel.isThemeActionEnabled)
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
