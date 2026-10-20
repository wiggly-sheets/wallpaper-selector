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
