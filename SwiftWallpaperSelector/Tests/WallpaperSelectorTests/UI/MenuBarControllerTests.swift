import XCTest
@testable import WallpaperSelector

@MainActor
final class MenuBarControllerTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var appState: AppState!
    var rotationService: RotationService!
    var controller: MenuBarController!

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
        let viewModel = SettingsViewModel(appState: appState)
        controller = MenuBarController(viewModel: MenuBarViewModel(
            appState: appState,
            settingsViewModel: viewModel
        ))
    }

    override func tearDownWithError() throws {
        if let statusItem = controller.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        rotationService.stop()
        controller = nil
        appState = nil
        rotationService = nil
        settingsManager = nil
        settingsContext = nil
    }

    func testTheStatusItemFollowsTheSetting() {
        XCTAssertEqual(controller.statusItem?.isVisible, true)

        appState.updateSettings { $0.showMenuBarItem = false }
        XCTAssertEqual(controller.statusItem?.isVisible, false)

        appState.updateSettings { $0.showMenuBarItem = true }
        XCTAssertEqual(controller.statusItem?.isVisible, true)
    }
}
