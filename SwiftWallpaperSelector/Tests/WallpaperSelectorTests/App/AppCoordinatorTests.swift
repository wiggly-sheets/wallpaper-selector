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
