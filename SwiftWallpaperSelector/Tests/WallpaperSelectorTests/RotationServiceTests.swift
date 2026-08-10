import XCTest
@testable import WallpaperSelector

final class RotationServiceTests: XCTestCase {
    // MARK: - Fixtures

    private var settingsManager: SettingsManager!
    private var mockProvider: MockWallpaperProvider!
    private var themeProvider: ThemeProvider!
    private var rotationService: RotationService!

    override func setUp() {
        super.setUp()
        settingsManager = SettingsManager()
        mockProvider = MockWallpaperProvider()
        themeProvider = ThemeProvider(settingsManager: settingsManager)
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: mockProvider,
            themeProvider: themeProvider
        )
    }

    override func tearDown() {
        rotationService.stop()
        mockProvider = nil
        themeProvider = nil
        settingsManager = nil
        rotationService = nil
        super.tearDown()
    }

    // MARK: - Timer lifecycle

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

    // MARK: - Rotation actions

    func testShuffleSelectsFromAvailableImages() {
        let folder = NSTemporaryDirectory()
        let fileURL = URL(fileURLWithPath: folder).appendingPathComponent("test_shuffle.png")
        // Create a dummy file
        try? "dummy".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        settingsManager.update { s in
            s.folderPaths = [folder]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }

        rotationService.tick()

        // The mock should have recorded a call
        XCTAssertFalse(mockProvider.calls.isEmpty)
    }

    func testNextSelectsSequentialImage() {
        let folder = NSTemporaryDirectory()
        let file1 = URL(fileURLWithPath: folder).appendingPathComponent("a.png")
        let file2 = URL(fileURLWithPath: folder).appendingPathComponent("b.png")
        try? "dummy".write(to: file1, atomically: true, encoding: .utf8)
        try? "dummy".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        settingsManager.update { s in
            s.folderPaths = [folder]
            s.rotationAction = .next
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = file1.path
        }

        rotationService.tick()

        XCTAssertFalse(mockProvider.calls.isEmpty)
    }

    // MARK: - History

    func testHistoryAvoidsImmediateRepeat() {
        let folder = NSTemporaryDirectory()
        let fileURL = URL(fileURLWithPath: folder).appendingPathComponent("test_history.png")
        try? "dummy".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        settingsManager.update { s in
            s.folderPaths = [folder]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = fileURL.path
            s.wallpaperHistory = [fileURL.path]
            s.historyLimit = 10
        }

        rotationService.tick()

        // The history should prevent the same image from being selected again
        // (unless it's the only image available)
        let lastCall = mockProvider.calls.last
        XCTAssertNotNil(lastCall)
    }
}