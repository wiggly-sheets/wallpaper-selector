import Foundation
import Combine
import SwiftUI
import AppKit

/// Top-level application coordinator that owns all long-lived services.
final class AppCoordinator: ObservableObject {
    // MARK: - Services (owned by the coordinator)

    let settingsManager: SettingsManager
    let wallpaperProvider: WallpaperProvider
    let themeProvider: ThemeProvider
    let rotationService: RotationService
    let appearanceMonitor: AppearanceMonitor
    private(set) var hotKeyManager: HotKeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    private let allSpacesService = AllSpacesService()

    // MARK: - Published Properties (after stored properties to avoid init order issues)

    @Published var appState: AppState!
    @Published var settingsViewModel: SettingsViewModel!

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var previousAppearanceSettings: WallpaperSettings?
    private var menuBarHostingController: MenuBarHostingViewController?

    // MARK: - Init

    init() {
        // 1. Create the persistence layer first.
        settingsManager = SettingsManager()

        // 2. The wallpaper provider is used by multiple services.
        wallpaperProvider = WallpaperProvider()

        // 3. Create ThemeProvider.
        let initialThemeProvider = ThemeProvider(settingsManager: settingsManager)
        themeProvider = initialThemeProvider

        // 4. RotationService owns the timer.
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: initialThemeProvider
        )

        // 5. AppearanceMonitor watches for light/dark mode changes.
        appearanceMonitor = AppearanceMonitor(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: initialThemeProvider
        )

        // 6. Hot-key manager registers global shortcuts.
        hotKeyManager = HotKeyManager(settingsManager: settingsManager)

        // 7. Launch-at-login manager.
        launchAtLoginManager = LaunchAtLoginManager()

        // 8. Create AppState and SettingsViewModel
        let state = AppState(
            settingsManager: settingsManager,
            themeProvider: initialThemeProvider,
            wallpaperProvider: wallpaperProvider
        )
        appState = state
        // Pass launchAtLoginManager to SettingsViewModel for the launch-at-login toggle
        settingsViewModel = SettingsViewModel(appState: appState, launchAtLoginManager: launchAtLoginManager)
        previousAppearanceSettings = appState.settings

        // One settings mutation must update every long-lived service. Earlier
        // SwiftUI controls only changed view-model copies, and even persisted
        // mutations could leave rotation and global shortcuts stale.
        appState.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSettingsChange() }
            .store(in: &cancellables)

        startMenuBar()

        // 9. Start the rotation service if interval is set.
        rotationService.updateSettings()

        // 10. Apply the initial appearance-based wallpaper if needed.
        appearanceMonitor.applyAppearanceWallpaperIfNeeded()

        // 10b. After ANY wallpaper apply (manual grid click, shuffle, or automatic
        // rotation) while All Spaces is on, surface the macOS Wallpaper settings
        // so the user can confirm "Show on all Spaces" there. Every apply path
        // (AppState.setWallpaper and RotationService) bumps `currentWallpaper`,
        // so observing it centrally keeps the hook in one place. `dropFirst()`
        // skips the initial static value restored from disk at launch.
        appState.$settings
            .map(\.currentWallpaper)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyAllSpacesIfNeeded()
            }
            .store(in: &cancellables)

        // 11. Begin observing app state transitions for background / foreground.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func updateHotKeys() {
        self.hotKeyManager.register()
    }

    // MARK: - Private Helpers

    private func handleSettingsChange() {
        let current = appState.settings
        let previous = previousAppearanceSettings
        previousAppearanceSettings = current

        self.rotationService.updateSettings()
        self.hotKeyManager.updateShortcuts()
        self.appState.reloadDerivedState()
        let appearanceContextChanged = previous?.matchSystemAppearance != current.matchSystemAppearance
            || previous?.activeThemeID != current.activeThemeID
            || previous?.appearanceLightThemeID != current.appearanceLightThemeID
            || previous?.appearanceDarkThemeID != current.appearanceDarkThemeID
            || previous?.allFoldersLightWallpaper != current.allFoldersLightWallpaper
            || previous?.allFoldersDarkWallpaper != current.allFoldersDarkWallpaper
            || previous?.themes != current.themes
        if previous?.allSpaces != current.allSpaces {
            allSpacesService.setEnabled(current.allSpaces)
        }
        if current.matchSystemAppearance && appearanceContextChanged {
            self.appearanceMonitor.applyAppearanceWallpaperIfNeeded()
        }
    }

    /// `WindowGroup` only creates its initial scene at launch, so using a
    /// hidden secondary group for this host left the status item uncreated.
    /// Load and retain the AppKit controller explicitly instead.
    private func startMenuBar() {
        let controller = MenuBarHostingViewController(
            appState: appState,
            rotationService: rotationService,
            settingsViewModel: settingsViewModel
        )
        menuBarHostingController = controller
        _ = controller.view
    }

    @objc private func handleDidBecomeActive() {
        self.appearanceMonitor.applyAppearanceWallpaperIfNeeded()
    }

    /// Apply the virtual-space option after each wallpaper change, matching the
    /// original app's all-spaces contract as closely as public APIs allow.
    private func applyAllSpacesIfNeeded() {
        guard appState.settings.allSpaces else { return }
        allSpacesService.setEnabled(true)
    }
}
