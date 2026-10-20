import XCTest
@testable import WallpaperSelector

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var wallpaperProvider: MockWallpaperProvider!
    var wallpaperLibrary: WallpaperLibrary!
    var appState: AppState!
    var rotationService: RotationService!
    var themeProvider: ThemeProvider!
    var settingsViewModel: SettingsViewModel!
    var viewModel: MenuBarViewModel!

    override func setUpWithError() throws {
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        wallpaperProvider = MockWallpaperProvider()
        wallpaperLibrary = WallpaperLibrary()

        themeProvider = ThemeProvider(settingsManager: settingsManager)
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
        settingsViewModel = SettingsViewModel(appState: appState)

        viewModel = MenuBarViewModel(appState: appState, settingsViewModel: settingsViewModel)
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        appState = nil
        rotationService = nil
        themeProvider = nil
        viewModel = nil
        settingsViewModel = nil
        wallpaperLibrary = nil
        wallpaperProvider = nil
        settingsManager = nil
        settingsContext = nil
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.menuTitle, "All Folders")
        XCTAssertFalse(viewModel.isRotationActive)
        XCTAssertNil(viewModel.selectedThemeID)
    }

    func testShuffleAction() async throws {
        let folderURL = try makeFolder(named: "shuffle-images", images: ["a.png"])
        let applied = expectation(description: "wallpaper applied")
        wallpaperProvider.onSetWallpaper = { _ in applied.fulfill() }

        viewModel.shuffle()

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(wallpaperProvider.appliedURLs, [folderURL.appendingPathComponent("a.png")])
    }

    func testNextAction() async throws {
        let folderURL = try makeFolder(named: "next-images", images: ["a.png", "b.png"])
        settingsManager.update { settings in
            settings.currentWallpaper = folderURL.appendingPathComponent("a.png").path
        }
        let applied = expectation(description: "wallpaper applied")
        wallpaperProvider.onSetWallpaper = { _ in applied.fulfill() }

        viewModel.next()

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(wallpaperProvider.appliedURLs, [folderURL.appendingPathComponent("b.png")])
    }

    func testPreviousAction() async throws {
        let folderURL = try makeFolder(named: "previous-images", images: ["a.png", "b.png"])
        settingsManager.update { settings in
            settings.currentWallpaper = folderURL.appendingPathComponent("b.png").path
        }
        let applied = expectation(description: "wallpaper applied")
        wallpaperProvider.onSetWallpaper = { _ in applied.fulfill() }

        viewModel.previous()

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(wallpaperProvider.appliedURLs, [folderURL.appendingPathComponent("a.png")])
    }

    func testOpenSettingsPostsNotification() {
        let expectation = expectation(forNotification: .MenuBarOpenSettings, object: nil)
        viewModel.openSettings()
        wait(for: [expectation], timeout: 0.1)
    }

    /// The menu must show the new value right away, not one change later.
    func testSettingsChangeIsVisibleWithoutWaitingForTheRunLoop() {
        XCTAssertFalse(viewModel.allSpaces)

        appState.updateSettings { $0.allSpaces = true }

        XCTAssertTrue(viewModel.allSpaces)
    }

    /// The wallpaper failure and the hot-key failure must both reach the menu.
    func testTheMenuShowsTheWallpaperAndTheHotKeyFailure() {
        wallpaperProvider.errorToThrow = MockWallpaperProviderError.configuredFailure

        appState.setWallpaper(URL(fileURLWithPath: "/wallpapers/failed.png"))
        settingsViewModel.setHotKeyErrorMessage("The shortcut is already used by another app.")

        XCTAssertNotNil(viewModel.lastWallpaperError)
        XCTAssertEqual(viewModel.hotKeyErrorMessage, "The shortcut is already used by another app.")
        XCTAssertEqual(viewModel.errorMessages.count, 2)
    }

    /// A solved failure must disappear from the menu again.
    func testTheMenuForgetsTheFailureWhenItIsGone() {
        wallpaperProvider.errorToThrow = MockWallpaperProviderError.configuredFailure
        appState.setWallpaper(URL(fileURLWithPath: "/wallpapers/failed.png"))
        settingsViewModel.setHotKeyErrorMessage("The shortcut is already used by another app.")
        XCTAssertEqual(viewModel.errorMessages.count, 2)

        settingsViewModel.setHotKeyErrorMessage(nil)

        XCTAssertEqual(viewModel.errorMessages.count, 1)
    }

    /// The rotation cannot run while the appearance is matched, so the menu
    /// item would do nothing. The flag states the effect, so a view binds it
    /// without negating it.
    func testTheRotationControlIsDisabledWhileTheAppearanceIsMatched() {
        XCTAssertFalse(viewModel.isRotationControlDisabled)

        appState.updateSettings { $0.matchSystemAppearance = true }

        XCTAssertTrue(viewModel.isRotationControlDisabled)
    }

    /// The menu shows the whole history, so the limit of the settings decides
    /// how many wallpapers are offered.
    func testEveryWallpaperOfTheHistoryIsShownInTheMenu() {
        let history = (1...20).map { "/wallpapers/\($0).jpg" }
        settingsManager.update { settings in
            settings.historyLimit = 20
            settings.wallpaperHistory = history
        }

        XCTAssertEqual(viewModel.displayedRecentWallpapers, history)
    }

    /// A wallpaper whose file is gone cannot be applied, so its menu item has
    /// to be disabled.
    func testARecentWallpaperWhoseFileIsGoneCannotBeApplied() throws {
        let folderURL = try makeFolder(named: "recent-images", images: ["there.png"])
        let there = folderURL.appendingPathComponent("there.png")
        let gone = folderURL.appendingPathComponent("gone.png")
        settingsManager.update { settings in
            settings.wallpaperHistory = [there.path, gone.path]
        }

        XCTAssertTrue(viewModel.canApplyRecentWallpaper(there.path))
        XCTAssertFalse(viewModel.canApplyRecentWallpaper(gone.path))
    }

    private func makeFolder(named name: String, images: [String]) throws -> URL {
        let folderURL = settingsContext.directory(named: name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for image in images {
            try Data().write(to: folderURL.appendingPathComponent(image))
        }
        settingsManager.update { settings in
            settings.folderPaths = [folderURL.path]
        }
        return folderURL
    }
}
