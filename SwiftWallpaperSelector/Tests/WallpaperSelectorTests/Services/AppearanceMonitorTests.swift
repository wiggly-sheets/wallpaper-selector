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

@MainActor
private final class RecordingWallpaperProvider: WallpaperSetting {
    private(set) var calls: [URL] = []

    func setWallpaper(_ url: URL) throws {
        calls.append(url)
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
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true)
        )

        monitor.applyAppearanceWallpaperIfNeeded()

        XCTAssertEqual(manager.settings.activeThemeID, darkTheme.id)
        XCTAssertTrue(wallpaperProvider.calls.isEmpty)
        XCTAssertEqual(manager.settings.currentWallpaper, pin.path)
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
            discoverWallpapers: { _ in [fallback] }
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
            appearanceProvider: FixedSystemAppearance(isDarkAppearance: true)
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
        let monitor = AppearanceMonitor(
            settingsManager: manager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: ThemeProvider(settingsManager: manager),
            appearanceProvider: appearance,
            discoverWallpapers: { folders in
                if folders == [lightDirectory.path] {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    return [lightImage]
                }
                return [darkImage]
            }
        )
        monitor.onAppearanceChanged = { path in
            if path == darkImage.path { darkApplied.fulfill() }
        }

        monitor.applyAppearanceWallpaperIfNeeded()
        appearance.isDarkAppearance = true
        monitor.applyAppearanceWallpaperIfNeeded()

        await fulfillment(of: [darkApplied], timeout: 2)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(wallpaperProvider.calls, [darkImage.standardizedFileURL])
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
