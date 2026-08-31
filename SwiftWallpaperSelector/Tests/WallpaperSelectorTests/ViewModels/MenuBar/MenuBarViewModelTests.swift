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

        viewModel = MenuBarViewModel(appState: appState)
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        appState = nil
        rotationService = nil
        themeProvider = nil
        viewModel = nil
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

    func testShuffleAction() {
        viewModel.shuffle()
    }

    func testNextAction() {
        viewModel.next()
    }

    func testPreviousAction() {
        viewModel.previous()
    }

    func testOpenSettingsPostsNotification() {
        let expectation = expectation(forNotification: .MenuBarOpenSettings, object: nil)
        viewModel.openSettings()
        wait(for: [expectation], timeout: 0.1)
    }

    func testQuitAction() {
    }
}
