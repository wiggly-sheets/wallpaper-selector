import Foundation
import Combine
import SwiftUI
import AppKit

final class AppCoordinator: ObservableObject {

    let settingsManager: SettingsManager
    let wallpaperProvider: WallpaperProvider
    let themeProvider: ThemeProvider
    let rotationService: RotationService
    let appearanceMonitor: AppearanceMonitor
    private(set) var hotKeyManager: HotKeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    private let allSpacesService = AllSpacesService()


    @Published var appState: AppState!
    @Published var settingsViewModel: SettingsViewModel!


    private var cancellables = Set<AnyCancellable>()
    private var previousAppearanceSettings: WallpaperSettings?
    private var menuBarHostingController: MenuBarHostingViewController?


    init() {
        settingsManager = SettingsManager()

        wallpaperProvider = WallpaperProvider()

        let initialThemeProvider = ThemeProvider(settingsManager: settingsManager)
        themeProvider = initialThemeProvider

        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: initialThemeProvider
        )

        appearanceMonitor = AppearanceMonitor(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: initialThemeProvider
        )

        hotKeyManager = HotKeyManager(settingsManager: settingsManager)

        launchAtLoginManager = LaunchAtLoginManager()

        let state = AppState(
            settingsManager: settingsManager,
            themeProvider: initialThemeProvider,
            wallpaperProvider: wallpaperProvider
        )
        appState = state
        settingsViewModel = SettingsViewModel(appState: appState, launchAtLoginManager: launchAtLoginManager)
        previousAppearanceSettings = appState.settings

        appState.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleSettingsChange() }
            .store(in: &cancellables)

        startMenuBar()

        rotationService.updateSettings()

        appearanceMonitor.applyAppearanceWallpaperIfNeeded()

        appState.$settings
            .map(\.currentWallpaper)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyAllSpacesIfNeeded()
            }
            .store(in: &cancellables)

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


    func updateHotKeys() {
        self.hotKeyManager.register()
    }


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

    private func applyAllSpacesIfNeeded() {
        guard appState.settings.allSpaces else { return }
        allSpacesService.setEnabled(true)
    }
}
