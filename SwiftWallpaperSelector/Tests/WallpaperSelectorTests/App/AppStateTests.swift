import Combine
import XCTest
@testable import WallpaperSelector

@MainActor
final class AppStateTests: XCTestCase {

    /// A settings write that happens while the change is being published must
    /// not leave the app state one change behind.
    func testANestedSettingsWriteDuringThePublishKeepsTheNewestValue() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        var didWriteNestedSettings = false
        let subscription = appState.settingsPublisher
            .dropFirst()
            .sink { settings in
                // The published value is already the stored one.
                XCTAssertEqual(appState.settings.folderPaths, settings.folderPaths)
                guard !didWriteNestedSettings else { return }
                didWriteNestedSettings = true
                appState.updateSettings { $0.folderPaths = ["/nested"] }
            }
        defer { subscription.cancel() }

        appState.updateSettings { $0.folderPaths = ["/outer"] }

        XCTAssertEqual(appState.settings.folderPaths, ["/nested"])
    }

    /// Every subscriber must end on the newest value when a subscriber writes
    /// settings while the change is published.
    ///
    /// The order in which the subscribers are served is not fixed, so many
    /// subscribers are used: every subscriber that is served after the writer
    /// gets the older value.
    func testEverySubscriberEndsOnTheNewestValueAfterANestedWrite() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        var didWriteNestedSettings = false
        var deliveredValues = [[WallpaperSettings]](repeating: [], count: 64)
        var cancellables: [AnyCancellable] = []

        // The writer comes first: the subscribers that are served after it
        // would get the older value.
        cancellables.append(appState.settingsPublisher
            .dropFirst()
            .sink { _ in
                guard !didWriteNestedSettings else { return }
                didWriteNestedSettings = true
                appState.updateSettings { $0.folderPaths = ["/nested"] }
            })
        for index in 0..<deliveredValues.count {
            cancellables.append(appState.settingsPublisher
                .dropFirst()
                .sink { value in deliveredValues[index].append(value) })
        }
        defer { cancellables.forEach { $0.cancel() } }

        appState.updateSettings { $0.folderPaths = ["/outer"] }

        XCTAssertEqual(appState.settings.folderPaths, ["/nested"])
        for (index, values) in deliveredValues.enumerated() {
            XCTAssertEqual(
                values.last?.folderPaths,
                ["/nested"],
                "Subscriber \(index) must end on the newest value"
            )
        }
    }

    /// A settings change must reach the subscribers only once when no
    /// subscriber writes settings while the change is published.
    func testASettingsChangeIsPublishedOnceToEverySubscriber() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        var deliveryCounts = [Int](repeating: 0, count: 4)
        var cancellables: [AnyCancellable] = []
        for index in 0..<deliveryCounts.count {
            cancellables.append(appState.settingsPublisher
                .dropFirst()
                .sink { _ in deliveryCounts[index] += 1 })
        }
        defer { cancellables.forEach { $0.cancel() } }

        appState.updateSettings { $0.folderPaths = ["/once"] }

        for (index, count) in deliveryCounts.enumerated() {
            XCTAssertEqual(count, 1, "Subscriber \(index) must receive the change only once")
        }
    }

    /// The pins of all folders are chosen from the images of every folder, so
    /// a wallpaper of a folder outside the active theme can be pinned.
    func testTheAllFolderImagesContainTheImagesOfEveryFolder() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        let themeFolder = context.directory(named: "theme-folder")
        let otherFolder = context.directory(named: "other-folder")
        try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let themeImage = themeFolder.appendingPathComponent("theme.png")
        let otherImage = otherFolder.appendingPathComponent("other.png")
        try Data().write(to: themeImage)
        try Data().write(to: otherImage)

        settingsManager.update { settings in
            settings.folderPaths = [themeFolder.path, otherFolder.path]
            settings.themes = [Theme(id: "theme", name: "Theme", folderPaths: [themeFolder.path])]
            settings.activeThemeID = "theme"
        }

        let deadline = Date().addingTimeInterval(10)
        while appState.allFolderImages.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(appState.currentThemeImages, [themeImage])
        XCTAssertTrue(
            appState.allFolderImages.contains(otherImage),
            "The image of the folder outside the theme has to be offered"
        )
    }

    /// The effective scope is the global folder list most of the time: the
    /// image list must then be loaded once, not twice.
    func testTheImageListIsLoadedOnceWhenTheScopeIsTheGlobalFolderList() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let library = WallpaperLibrary()
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: library
        )

        let folder = context.directory(named: "wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("a.png"))

        settingsManager.update { $0.folderPaths = [folder.path] }

        let deadline = Date().addingTimeInterval(10)
        while appState.currentThemeImages.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(appState.currentThemeImages.count, 1)
        XCTAssertEqual(appState.allFolderImages, appState.currentThemeImages)
        let loads = await library.loadCount
        XCTAssertEqual(loads, 1, "The image list must be loaded once when both scopes are the same")
    }

    /// The wallpaper error lives in the rotation service, so a settings
    /// change has to clear it there: the folder the user adds may have
    /// resolved the problem that caused it.
    func testASettingsChangeClearsTheWallpaperError() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: MockWallpaperProvider(),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        await rotationService.perform(.shuffle)
        XCTAssertEqual(rotationService.lastError, "No wallpaper folders are configured.")

        appState.updateSettings { $0.folderPaths = ["/configured"] }

        XCTAssertNil(rotationService.lastError, "The stale wallpaper error has to be cleared")
        XCTAssertNil(appState.lastWallpaperError)
    }

    /// The deferral message describes the live state, not a stale condition,
    /// so a settings change must not clear it while the pick is pending.
    func testASettingsChangeKeepsTheDeferralMessageWhileAPickIsPending() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let mockProvider = MockWallpaperProvider()
        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: mockProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )

        let folder = context.directory(named: "deferred-images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("a.png"))
        let manual = folder.appendingPathComponent("manual.png")
        settingsManager.update { $0.folderPaths = [folder.path] }

        var didPick = false
        var messageAfterTheSettingsChange: String?
        mockProvider.onSetWallpaper = { _ in
            guard !didPick else { return }
            didPick = true
            // The rotation is running, so the pick waits for it.
            _ = rotationService.apply(manual)
            XCTAssertEqual(rotationService.lastError, RotationService.deferredPickMessage)
            appState.updateSettings { $0.intervalMinutes = .hour1 }
            messageAfterTheSettingsChange = rotationService.lastError
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(
            messageAfterTheSettingsChange,
            RotationService.deferredPickMessage,
            "The deferral message must survive the settings change"
        )
    }
}
