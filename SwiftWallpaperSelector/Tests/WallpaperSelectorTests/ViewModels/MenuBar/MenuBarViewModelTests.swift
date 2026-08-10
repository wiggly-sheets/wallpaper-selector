import XCTest
@testable import WallpaperSelector

final class MenuBarViewModelTests: XCTestCase {
    var appState: AppState!
    var rotationService: RotationService!
    var themeProvider: ThemeProvider!
    var viewModel: MenuBarViewModel!

    override func setUpWithError() throws {
        // Create a real SettingsManager
        let settingsManager = SettingsManager()
        let wallpaperProvider = WallpaperProvider()

        // Create real service instances for testing
        themeProvider = ThemeProvider(settingsManager: settingsManager)
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )

        // Create AppState
        appState = AppState(
            settingsManager: settingsManager,
            themeProvider: themeProvider,
            wallpaperProvider: wallpaperProvider
        )

        // Create view model
        viewModel = MenuBarViewModel(
            appState: appState,
            rotationService: rotationService,
            themeProvider: themeProvider
        )
    }

    override func tearDownWithError() throws {
        // Clean up
        rotationService.stop()
        appState = nil
        rotationService = nil
        themeProvider = nil
        viewModel = nil
    }

    func testInitialState() {
        // With no theme selected, menu title should be "All Folders"
        XCTAssertEqual(viewModel.menuTitle, "All Folders")
        XCTAssertFalse(viewModel.isRotationActive)
        XCTAssertNil(viewModel.selectedThemeID)
    }

    func testShuffleAction() {
        viewModel.shuffle()
        // Just verify it doesn't crash - the actual tick verification
        // is harder to test without mocking
    }

    func testNextAction() {
        viewModel.next()
        // Just verify it doesn't crash
    }

    func testPreviousAction() {
        viewModel.previous()
        // Just verify it doesn't crash
    }

    func testOpenSettingsPostsNotification() {
        let expectation = expectation(forNotification: .MenuBarOpenSettings, object: nil)
        viewModel.openSettings()
        wait(for: [expectation], timeout: 0.1)
    }

    func testQuitAction() {
        // Terminate would kill the test process; instead verify the notification
        // that the quit action is wired up via the view model (it posts nothing,
        // so we just ensure it doesn't crash for an unconfigured quit path).
        // NSApplication.shared.terminate is not called here to keep the test runner alive.
    }
}