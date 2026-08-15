import XCTest
@testable import WallpaperSelector

final class MenuBarViewModelTests: XCTestCase {
    var appState: AppState!
    var rotationService: RotationService!
    var themeProvider: ThemeProvider!
    var viewModel: MenuBarViewModel!

    override func setUpWithError() throws {
        let settingsManager = SettingsManager()
        let wallpaperProvider = WallpaperProvider()

        themeProvider = ThemeProvider(settingsManager: settingsManager)
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )

        appState = AppState(
            settingsManager: settingsManager,
            themeProvider: themeProvider,
            wallpaperProvider: wallpaperProvider
        )

        viewModel = MenuBarViewModel(
            appState: appState,
            rotationService: rotationService,
            themeProvider: themeProvider
        )
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        appState = nil
        rotationService = nil
        themeProvider = nil
        viewModel = nil
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
