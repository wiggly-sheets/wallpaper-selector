import AppKit
import XCTest
@testable import WallpaperSelector

@MainActor
final class AppCoordinatorTests: XCTestCase {
    /// A newly recorded shortcut has to be registered right away. Reading the
    /// settings again while the change is being published would hand the
    /// manager the previous shortcuts.
    func testShortcutChangeReRegistersTheHotKeysWithTheNewShortcuts() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appState.updateSettings { $0.shortcuts = Shortcuts(showMain: "cmd+1") }

        XCTAssertEqual(hotKeyManager.requestedShortcuts, [Shortcuts(showMain: "cmd+1")])
    }

    /// The app that owned the shortcut may have quit: the shortcut is taken
    /// back when the app becomes active, so the error disappears on its own.
    func testBecomingActiveReRegistersTheHotKeys() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            startsMenuBar: false
        )
        defer { _ = coordinator }
        let registrationsBefore = hotKeyManager.registrationCount

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(hotKeyManager.registrationCount, registrationsBefore + 1)
    }

    /// A wallpaper that could not be applied while the appearance was
    /// matched has to reach the app state, so the menu bar shows it.
    func testAnAppearanceErrorReachesTheAppState() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appearanceMonitor.onError?("The wallpaper could not be applied.")

        XCTAssertEqual(
            coordinator.appState.lastWallpaperError,
            "The wallpaper could not be applied."
        )
    }

    /// A settings write that fails has to reach the menu bar, so the user
    /// sees it without opening the settings window.
    func testAFailedSettingsWriteReachesTheMenuBar() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        // The settings folder cannot be written to, so the next save fails.
        let directory = settingsManager.settingsDirectory
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
        }

        coordinator.appState.updateSettings { $0.folderPaths = ["/never-written"] }
        await settingsManager.waitForPendingWrites()

        XCTAssertTrue(
            coordinator.rotationService.lastError?.contains("Could not save settings") == true,
            "The failed write has to be reported where the wallpaper errors are"
        )
    }

    /// A settings change that was made a moment before the quit has to reach
    /// the disk: the write runs on a queue, so it has to be flushed.
    func testTheQuitFlushesThePendingSettingsWrite() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appState.updateSettings { $0.folderPaths = ["/before-quit"] }

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        let stored = try JSONDecoder().decode(
            WallpaperSettings.self,
            from: Data(contentsOf: settingsManager.settingsURL)
        )
        XCTAssertEqual(stored.folderPaths, ["/before-quit"])
    }

    /// A wallpaper the user picked by hand has to survive the wake-up of the
    /// app: the pin is enforced when the appearance changes, not every time
    /// the app becomes active.
    func testAManualPickSurvivesTheActivation() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let wallpaperProvider = MockWallpaperProvider()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let directory = try makeWallpaperDirectory(in: context)
        let pin = try makeImage(named: "pin.jpg", in: directory)
        let pick = try makeImage(named: "pick.jpg", in: directory)
        // The pin of both appearances is the same, so the test does not
        // depend on the appearance of the machine that runs it.
        settingsManager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersLightWallpaper: pin.path,
            allFoldersDarkWallpaper: pin.path
        ))
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            injectedWallpaperProvider: wallpaperProvider,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        // The pin is applied at startup.
        wallpaperProvider.reset()

        coordinator.appState.setWallpaper(pick)

        XCTAssertEqual(wallpaperProvider.appliedURLs, [pick])

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(
            wallpaperProvider.appliedURLs,
            [pick],
            "The pin must not replace the wallpaper the user picked by hand"
        )
        XCTAssertEqual(settingsManager.settings.currentWallpaper, pick.path)
    }

    /// The pin is a standing instruction of the user: it is applied when the
    /// user changes it.
    func testChangingThePinAppliesTheNewPin() async throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let wallpaperProvider = MockWallpaperProvider()
        let hotKeyManager = RecordingHotKeyManager(settingsManager: settingsManager)
        let directory = try makeWallpaperDirectory(in: context)
        let pin = try makeImage(named: "pin.jpg", in: directory)
        let newPin = try makeImage(named: "new-pin.jpg", in: directory)
        settingsManager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            matchSystemAppearance: true,
            allFoldersLightWallpaper: pin.path,
            allFoldersDarkWallpaper: pin.path
        ))
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: hotKeyManager,
            injectedWallpaperProvider: wallpaperProvider,
            startsMenuBar: false
        )
        defer { _ = coordinator }
        wallpaperProvider.reset()
        let applied = expectation(description: "the new pin is applied")
        coordinator.appearanceMonitor.onAppearanceChanged = { path in
            if path == newPin.standardizedFileURL.path { applied.fulfill() }
        }

        coordinator.appState.updateSettings {
            $0.allFoldersLightWallpaper = newPin.path
            $0.allFoldersDarkWallpaper = newPin.path
        }
        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(wallpaperProvider.appliedURLs, [newPin.standardizedFileURL])
    }

    /// The wallpaper that is on the screen has to reach every Space as soon
    /// as the user turns the setting on. The user does not wait for the next
    /// rotation.
    func testSwitchingAllSpacesOnPutsTheCurrentWallpaperOnEverySpace() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let applier = RecordingAllSpacesApplier()
        let directory = try makeWallpaperDirectory(in: context)
        let wallpaper = try makeImage(named: "current.jpg", in: directory)
        settingsManager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            currentWallpaper: wallpaper.path
        ))
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: RecordingHotKeyManager(settingsManager: settingsManager),
            injectedAllSpacesApplier: applier,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appState.updateSettings { $0.allSpaces = true }

        XCTAssertEqual(applier.appliedURLs, [wallpaper])
    }

    /// The app stops patching when the user turns the setting off. Nothing is
    /// restored: the next wallpaper change ends the global state on its own.
    func testSwitchingAllSpacesOffPutsNoWallpaperOnEverySpace() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let applier = RecordingAllSpacesApplier()
        let directory = try makeWallpaperDirectory(in: context)
        let wallpaper = try makeImage(named: "current.jpg", in: directory)
        settingsManager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            currentWallpaper: wallpaper.path,
            allSpaces: true
        ))
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: RecordingHotKeyManager(settingsManager: settingsManager),
            injectedAllSpacesApplier: applier,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appState.updateSettings { $0.allSpaces = false }

        XCTAssertTrue(applier.appliedURLs.isEmpty)
    }

    /// A wallpaper that could not be put on every Space has to reach the
    /// channel of the wallpaper errors, so the menu bar and the settings show
    /// it.
    func testAFailureOfTheAllSpacesApplyReachesTheWallpaperError() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let applier = RecordingAllSpacesApplier()
        applier.failureMessage = "The wallpaper could not be put on every Space. The store is missing."
        let directory = try makeWallpaperDirectory(in: context)
        let wallpaper = try makeImage(named: "current.jpg", in: directory)
        settingsManager.replace(WallpaperSettings(
            folderPaths: [directory.path],
            currentWallpaper: wallpaper.path
        ))
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: RecordingHotKeyManager(settingsManager: settingsManager),
            injectedAllSpacesApplier: applier,
            startsMenuBar: false
        )
        defer { _ = coordinator }

        coordinator.appState.updateSettings { $0.allSpaces = true }

        XCTAssertEqual(
            coordinator.appState.lastWallpaperError,
            "The wallpaper could not be put on every Space. The store is missing."
        )
    }

    /// The wallpaper only reaches every Space while the setting is on. The
    /// setting is read when the wallpaper is applied, because the user can
    /// turn it off at any moment.
    func testTheWallpaperReachesEverySpaceOnlyWhileTheSettingIsOn() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let applier = RecordingAllSpacesApplier()
        let directory = try makeWallpaperDirectory(in: context)
        let wallpaper = try makeImage(named: "current.jpg", in: directory)
        let coordinator = AppCoordinator(
            settingsManager: settingsManager,
            injectedHotKeyManager: RecordingHotKeyManager(settingsManager: settingsManager),
            injectedAllSpacesApplier: applier,
            startsMenuBar: false
        )
        defer { _ = coordinator }
        let provider = try XCTUnwrap(coordinator.wallpaperProvider as? WallpaperProvider)

        provider.applyToAllSpaces?(wallpaper)

        XCTAssertTrue(
            applier.appliedURLs.isEmpty,
            "The wallpaper must stay on the current Space while the setting is off"
        )

        coordinator.appState.updateSettings { $0.allSpaces = true }
        provider.applyToAllSpaces?(wallpaper)

        XCTAssertEqual(applier.appliedURLs, [wallpaper])
    }

    private func makeWallpaperDirectory(in context: TestSettingsContext) throws -> URL {
        let directory = context.directory(named: "wallpapers")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeImage(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("image".utf8).write(to: url)
        return url
    }
}

/// Records the wallpapers the coordinator wants on every Space.
///
/// The real applier writes the store of macOS and restarts the wallpaper
/// agent, so a test uses this double instead of it.
@MainActor
final class RecordingAllSpacesApplier: AllSpacesApplier {
    private(set) var appliedURLs: [URL] = []
    /// The failure the applier reports instead of a success.
    var failureMessage: String?

    init() {
        // The store and the backup point at a folder that does not exist, so
        // the store of macOS is never touched and no agent is ever killed.
        let unused = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RecordingAllSpacesApplier-\(UUID().uuidString)", isDirectory: true)
        super.init(storeURL: unused, backupURL: unused, restartAgent: {})
    }

    override func apply(_ imageURL: URL) {
        appliedURLs.append(imageURL)
        if let failureMessage { onError?(failureMessage) }
    }
}

/// Records the shortcuts the coordinator asks for without registering a real
/// global hot key.
@MainActor
final class RecordingHotKeyManager: HotKeyManager {
    private(set) var requestedShortcuts: [Shortcuts] = []
    private(set) var registrationCount = 0

    override func register() {
        registrationCount += 1
    }

    override func updateShortcuts(_ shortcuts: Shortcuts) {
        requestedShortcuts.append(shortcuts)
    }
}
