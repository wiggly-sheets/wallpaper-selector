import XCTest
@testable import WallpaperSelector

private struct FixedSystemAppearance: SystemAppearanceProviding {
    let isDarkAppearance: Bool
}

private final class MutableSystemAppearance: SystemAppearanceProviding {
    var isDarkAppearance: Bool

    init(isDarkAppearance: Bool) {
        self.isDarkAppearance = isDarkAppearance
    }
}

/// A private center: the real macOS appearance notifications never reach it.
private func makePrivateNotificationCenter() -> DistributedNotificationCenter {
    DistributedNotificationCenter()
}

@MainActor
private final class RecordingWallpaperProvider: WallpaperSetting {
    private(set) var calls: [URL] = []

    func setWallpaper(_ url: URL) throws {
        calls.append(url)
    }
}

/// A provider that refuses the wallpaper on some of the displays.
@MainActor
private final class FailingWallpaperProvider: WallpaperSetting {
    private(set) var calls: [URL] = []
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func setWallpaper(_ url: URL) throws {
        calls.append(url)
        throw error
    }
}

/// Records what a request saw, so the test can wait for the request instead
/// of guessing a time.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _wasCancelled = false
    /// The request has finished.
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _wasCancelled
    }

    func record(wasCancelled: Bool) {
        lock.lock()
        _wasCancelled = wasCancelled
        lock.unlock()
        finished.fulfill()
    }
}

final class AppearanceMonitorTests: XCTestCase {
    @MainActor
    func testThemeChangeKeepsValidPinThatIsAlreadyCurrent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try makeImage(named: "dark.jpg", in: directory)
        let lightTheme = Theme(id: "light", name: "Light", folderPaths: [directory.path])
        let darkTheme = Theme(
            id: "dark",
            name: "Dark",
            folderPaths: [directory.path],
            darkWallpaper: pin.path
        )
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            currentWallpaper: pin.path,
            themes: [lightTheme, darkTheme],
            activeThemeID: lightTheme.id,
            matchSystemAppearance: true,
            appearanceLightThemeID: lightTheme.id,
            appearanceDarkThemeID: darkTheme.id
        ))
        let wallpaperProvider = RecordingWallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: manager)
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )

        monitor.applyAppearanceWallpaperIfNeeded()

        // The appearance theme is in effect, but the theme the user picked is kept.
        XCTAssertEqual(themeProvider.effectiveThemeID(isDarkAppearance: true), darkTheme.id)
        XCTAssertEqual(themeProvider.effectiveFolders(isDarkAppearance: true), [directory.path])
        XCTAssertEqual(manager.settings.activeThemeID, lightTheme.id)
        XCTAssertTrue(wallpaperProvider.calls.isEmpty)
        XCTAssertEqual(manager.settings.currentWallpaper, pin.path)
    }

    @MainActor
    func testMissingAppearanceThemeKeepsUserThemeAndFallsBackToAllFolders() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let userDirectory = directory.appendingPathComponent("user", isDirectory: true)
        let otherDirectory = directory.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let theme = Theme(id: "user", name: "User", folderPaths: [userDirectory.path])
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [userDirectory.path, otherDirectory.path],
            themes: [theme],
            activeThemeID: theme.id,
            matchSystemAppearance: true
        ))
        let wallpaperProvider = RecordingWallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: manager)
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )

        monitor.applyAppearanceWallpaperIfNeeded()

        // No appearance theme is configured: the user's theme survives and the
        // scope widens to all folders.
        XCTAssertEqual(manager.settings.activeThemeID, theme.id)
        XCTAssertNil(themeProvider.effectiveThemeID(isDarkAppearance: true))
        XCTAssertEqual(
            themeProvider.effectiveFolders(isDarkAppearance: true),
            [userDirectory.path, otherDirectory.path]
        )
    }

    @MainActor
    func testMissingPinFallsBackToAvailableWallpaper() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fallback = try makeImage(named: "fallback.jpg", in: directory)
        let theme = Theme(
            id: "dark",
            name: "Dark",
            folderPaths: [directory.path],
            darkWallpaper: directory.appendingPathComponent("missing.jpg").path
        )
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            currentWallpaper: "/not/in/the/theme.jpg",
            themes: [theme],
            matchSystemAppearance: true,
            appearanceDarkThemeID: theme.id
        ))
        let wallpaperProvider = RecordingWallpaperProvider()
        let applied = expectation(description: "fallback applied")
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            discoverWallpapers: { _ in [fallback] },
            notificationCenter: makePrivateNotificationCenter()
        )
        monitor.onAppearanceChanged = { _ in applied.fulfill() }

        monitor.applyAppearanceWallpaperIfNeeded()
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(wallpaperProvider.calls, [fallback.standardizedFileURL])
        XCTAssertEqual(manager.settings.currentWallpaper, fallback.path)
    }

    @MainActor
    func testInjectedSystemAppearanceChoosesDarkPin() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lightPin = try makeImage(named: "light.jpg", in: directory)
        let darkPin = try makeImage(named: "dark.jpg", in: directory)
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersLightWallpaper: lightPin.path,
            allFoldersDarkWallpaper: darkPin.path
        ))
        let wallpaperProvider = RecordingWallpaperProvider()
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(wallpaperProvider.calls, [darkPin.standardizedFileURL])
        XCTAssertEqual(manager.settings.currentWallpaper, darkPin.path)
    }

    @MainActor
    func testNewAppearanceRequestCancelsStaleFallback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lightDirectory = directory.appendingPathComponent("light", isDirectory: true)
        let darkDirectory = directory.appendingPathComponent("dark", isDirectory: true)
        try FileManager.default.createDirectory(at: lightDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: darkDirectory, withIntermediateDirectories: true)
        let lightImage = try makeImage(named: "light.jpg", in: lightDirectory)
        let darkImage = try makeImage(named: "dark.jpg", in: darkDirectory)
        let lightTheme = Theme(id: "light", name: "Light", folderPaths: [lightDirectory.path])
        let darkTheme = Theme(id: "dark", name: "Dark", folderPaths: [darkDirectory.path])
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [lightDirectory.path, darkDirectory.path],
            themes: [lightTheme, darkTheme],
            matchSystemAppearance: true,
            appearanceLightThemeID: lightTheme.id,
            appearanceDarkThemeID: darkTheme.id
        ))
        let appearance = MutableSystemAppearance(isDarkAppearance: false)
        let wallpaperProvider = RecordingWallpaperProvider()
        let darkApplied = expectation(description: "latest fallback applied")
        let staleRequest = RequestLog(finished: expectation(description: "stale request finished"))
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: appearance,
            discoverWallpapers: { folders in
                if folders == [lightDirectory.path] {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    // The request runs in the task of the monitor, so it sees
                    // the cancellation of that task.
                    staleRequest.record(wasCancelled: Task.isCancelled)
                    return [lightImage]
                }
                return [darkImage]
            },
            notificationCenter: makePrivateNotificationCenter()
        )
        monitor.onAppearanceChanged = { path in
            if path == darkImage.path { darkApplied.fulfill() }
        }

        monitor.applyAppearanceWallpaperIfNeeded()
        appearance.isDarkAppearance = true
        monitor.applyAppearanceWallpaperIfNeeded()

        // The test waits for the stale request itself, so it does not depend
        // on a margin that a loaded machine can outlast.
        await fulfillment(of: [darkApplied, staleRequest.finished], timeout: 2)

        XCTAssertTrue(staleRequest.wasCancelled, "The stale request has to be cancelled")
        XCTAssertEqual(wallpaperProvider.calls, [darkImage.standardizedFileURL])
    }

    /// The scope of the app follows the system appearance, so every change has
    /// to be reported, even when no wallpaper was applied.
    @MainActor
    func testEveryAppearanceChangeIsReported() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeSettingsManager(in: directory)
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: RecordingWallpaperProvider(),
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: false),
            notificationCenter: makePrivateNotificationCenter()
        )
        var reportCount = 0
        monitor.onSystemAppearanceChanged = { reportCount += 1 }

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(reportCount, 1)
    }

    /// The wallpaper reached one of the two displays, so it is on the screen
    /// and has to be recorded.
    @MainActor
    func testAPartialDisplayFailureStillRecordsTheWallpaper() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try makeImage(named: "dark.jpg", in: directory)
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersDarkWallpaper: pin.path
        ))
        let wallpaperProvider = FailingWallpaperProvider(
            error: WallpaperProviderError.failedToSetOnDisplays(
                failedCount: 1,
                totalCount: 2,
                underlying: MockWallpaperProviderError.configuredFailure
            )
        )
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(wallpaperProvider.calls, [pin.standardizedFileURL])
        XCTAssertEqual(manager.settings.currentWallpaper, pin.path)
    }

    /// A wallpaper that could not be applied has to be reported: the rotation
    /// path reports it, so the appearance path has to report it too.
    @MainActor
    func testAFailedWallpaperIsReported() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try makeImage(named: "dark.jpg", in: directory)
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersDarkWallpaper: pin.path
        ))
        let wallpaperProvider = FailingWallpaperProvider(
            error: WallpaperProviderError.failedToSetOnDisplays(
                failedCount: 2,
                totalCount: 2,
                underlying: MockWallpaperProviderError.configuredFailure
            )
        )
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )
        var reportedErrors: [String] = []
        monitor.onError = { reportedErrors.append($0) }

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(reportedErrors.count, 1)
        XCTAssertTrue(
            reportedErrors.first?.contains("Failed to set wallpaper on 2 of 2 displays") == true,
            "The failure has to be reported, got \(reportedErrors.first ?? "no message")"
        )
    }

    /// The wallpaper reached one of the two displays, so it is on the screen
    /// and has to be recorded. The failed display is reported anyway.
    @MainActor
    func testAPartialDisplayFailureIsReportedAndTheWallpaperIsRecorded() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try makeImage(named: "dark.jpg", in: directory)
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersDarkWallpaper: pin.path
        ))
        let wallpaperProvider = FailingWallpaperProvider(
            error: WallpaperProviderError.failedToSetOnDisplays(
                failedCount: 1,
                totalCount: 2,
                underlying: MockWallpaperProviderError.configuredFailure
            )
        )
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )
        var reportedErrors: [String] = []
        monitor.onError = { reportedErrors.append($0) }

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(reportedErrors.count, 1)
        XCTAssertTrue(
            reportedErrors.first?.contains("Failed to set wallpaper on 1 of 2 displays") == true,
            "The failed display has to be reported, got \(reportedErrors.first ?? "no message")"
        )
        XCTAssertEqual(manager.settings.currentWallpaper, pin.path)
    }

    /// The wallpaper could not be stored, so it must not be reported as
    /// applied.
    @MainActor
    func testAFailedSettingsWriteIsNotReportedAsApplied() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pin = try makeImage(named: "dark.jpg", in: directory)
        let manager = makeSettingsManager(in: directory)
        manager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersDarkWallpaper: pin.path
        ))
        let wallpaperProvider = RecordingWallpaperProvider()
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true),
            notificationCenter: makePrivateNotificationCenter()
        )
        var reportedPaths: [String?] = []
        monitor.onAppearanceChanged = { reportedPaths.append($0) }

        // The settings file cannot be written anymore.
        try FileManager.default.removeItem(at: manager.settingsDirectory)
        try Data("not-a-directory".utf8).write(to: manager.settingsDirectory)

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(wallpaperProvider.calls, [pin.standardizedFileURL])
        XCTAssertTrue(reportedPaths.isEmpty, "The wallpaper must not be reported as applied")
        XCTAssertNotNil(manager.lastError)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppearanceMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeImage(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("image".utf8).write(to: url)
        return url
    }

    @MainActor
    private func makeSettingsManager(in directory: URL) -> SettingsManager {
        SettingsManager(
            settingsDirectory: directory.appendingPathComponent("settings", isDirectory: true),
            defaultSettingsDirectory: directory.appendingPathComponent("default", isDirectory: true),
            migrateLegacySettings: false
        )
    }
}
