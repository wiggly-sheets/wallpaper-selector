import XCTest
@testable import WallpaperSelector

@MainActor
final class RotationServiceTests: XCTestCase {

    private var settingsContext: TestSettingsContext!
    private var settingsManager: SettingsManager!
    private var mockProvider: MockWallpaperProvider!
    private var themeProvider: ThemeProvider!
    private var rotationService: RotationService!
    private var wallpaperLibrary: WallpaperLibrary!

    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        mockProvider = MockWallpaperProvider()
        themeProvider = ThemeProvider(settingsManager: settingsManager)
        wallpaperLibrary = WallpaperLibrary()
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: mockProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        mockProvider = nil
        themeProvider = nil
        settingsManager = nil
        rotationService = nil
        wallpaperLibrary = nil
        settingsContext = nil
        try super.tearDownWithError()
    }


    func testStartWhenIntervalIsSetAndAppearanceMatchingOff() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertTrue(rotationService.isRunning)
    }

    func testStopWhenIntervalIsOff() {
        settingsManager.update { s in
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertFalse(rotationService.isRunning)
    }

    func testStopWhenMatchSystemAppearanceIsOn() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = true
        }
        rotationService.start()
        XCTAssertFalse(rotationService.isRunning)
    }

    func testUpdateSettingsStopsTimerWhenIntervalTurnedOff() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertTrue(rotationService.isRunning)

        settingsManager.update { s in
            s.intervalMinutes = .off
        }
        rotationService.updateSettings()
        XCTAssertFalse(rotationService.isRunning)
    }


    func testShuffleSelectsFromAvailableImages() async throws {
        let folderURL = settingsContext.directory(named: "shuffle-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent("test_shuffle.png")
        try "dummy".write(to: fileURL, atomically: true, encoding: .utf8)

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(mockProvider.appliedURLs, [fileURL])
    }

    func testNextSelectsSequentialImage() async throws {
        let folderURL = settingsContext.directory(named: "next-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let file1 = folderURL.appendingPathComponent("a.png")
        let file2 = folderURL.appendingPathComponent("b.png")
        try "dummy".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy".write(to: file2, atomically: true, encoding: .utf8)

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .next
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = file1.path
        }

        await rotationService.perform(.next)

        XCTAssertEqual(mockProvider.appliedURLs, [file2])
    }


    func testHistoryAvoidsImmediateRepeat() async throws {
        let folderURL = settingsContext.directory(named: "history-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent("test_history.png")
        try "dummy".write(to: fileURL, atomically: true, encoding: .utf8)

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = fileURL.path
            s.wallpaperHistory = [fileURL.path]
            s.historyLimit = 10
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(mockProvider.appliedURLs.last, fileURL)
    }

    func testFailedWallpaperApplyDoesNotPublishFalseCurrentWallpaperOrHistory() {
        let original = WallpaperSettings(
            currentWallpaper: "/wallpapers/original.png",
            wallpaperHistory: ["/wallpapers/original.png"]
        )
        settingsManager.replace(original)
        mockProvider.errorToThrow = MockWallpaperProviderError.configuredFailure

        let applied = rotationService.apply(URL(fileURLWithPath: "/wallpapers/failed.png"))

        XCTAssertFalse(applied)
        XCTAssertEqual(settingsManager.settings.currentWallpaper, original.currentWallpaper)
        XCTAssertEqual(settingsManager.settings.wallpaperHistory, original.wallpaperHistory)
        XCTAssertNotNil(rotationService.lastError)
    }

    func testManualNextDoesNotReplaceScheduledRotationAction() async throws {
        let folderURL = settingsContext.directory(named: "manual-next-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let first = folderURL.appendingPathComponent("a.png")
        let second = folderURL.appendingPathComponent("b.png")
        try Data().write(to: first)
        try Data().write(to: second)
        settingsManager.update { settings in
            settings.folderPaths = [folderURL.path]
            settings.currentWallpaper = first.path
            settings.rotationAction = .themeShuffle
        }

        await rotationService.perform(.next)

        XCTAssertEqual(mockProvider.appliedURLs.last, second)
        XCTAssertEqual(settingsManager.settings.rotationAction, .themeShuffle)
    }
}
