import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    let settingsManager: SettingsManager
    let wallpaperProvider: WallpaperProvider
    let themeProvider: ThemeProvider
    let rotationService: RotationService
    let appearanceMonitor: AppearanceMonitor
    let hotKeyManager: HotKeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    let appState: AppState
    let settingsViewModel: SettingsViewModel

    private let allSpacesService: AllSpacesService
    private var cancellables = Set<AnyCancellable>()
    private var previousSettings: WallpaperSettings
    private var menuBarHostingController: MenuBarHostingViewController?

    init() {
        let settingsManager = SettingsManager()
        let wallpaperProvider = WallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )
        let appearanceMonitor = AppearanceMonitor(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )
        let launchAtLoginManager = LaunchAtLoginManager()
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider
        )

        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        self.rotationService = rotationService
        self.appearanceMonitor = appearanceMonitor
        hotKeyManager = HotKeyManager(settingsManager: settingsManager)
        self.launchAtLoginManager = launchAtLoginManager
        self.appState = appState
        settingsViewModel = SettingsViewModel(
            appState: appState,
            launchAtLoginManager: launchAtLoginManager
        )
        allSpacesService = AllSpacesService()
        previousSettings = settingsManager.settings

        appState.$settings
            .dropFirst()
            .sink { [weak self] _ in self?.handleSettingsChange() }
            .store(in: &cancellables)

        startMenuBar()
        allSpacesService.onResult = { [weak self] result in
            guard case let .manualActionRequired(enabled, reason) = result else { return }
            self?.menuBarHostingController?.showAllSpacesManualFallback(
                enabled: enabled,
                reason: reason
            )
        }
        hotKeyManager.onHotKeyPressed = { [weak self] identifier in
            self?.menuBarHostingController?.handleHotKey(identifier)
        }
        hotKeyManager.register()
        rotationService.updateSettings()
        appearanceMonitor.applyAppearanceWallpaperIfNeeded()

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

    private func handleSettingsChange() {
        let current = appState.settings
        let previous = previousSettings
        previousSettings = current

        rotationService.updateSettings()
        if previous.shortcuts != current.shortcuts {
            hotKeyManager.updateShortcuts()
        }

        if previous.allSpaces != current.allSpaces {
            allSpacesService.setEnabled(current.allSpaces)
        }

        let appearanceContextChanged = previous.matchSystemAppearance != current.matchSystemAppearance
            || previous.appearanceLightThemeID != current.appearanceLightThemeID
            || previous.appearanceDarkThemeID != current.appearanceDarkThemeID
            || previous.allFoldersLightWallpaper != current.allFoldersLightWallpaper
            || previous.allFoldersDarkWallpaper != current.allFoldersDarkWallpaper
            || previous.themes != current.themes

        if current.matchSystemAppearance && appearanceContextChanged {
            appearanceMonitor.applyAppearanceWallpaperIfNeeded()
        }
    }

    private func startMenuBar() {
        let controller = MenuBarHostingViewController(
            appState: appState,
            settingsViewModel: settingsViewModel
        )
        menuBarHostingController = controller
        _ = controller.view
    }

    @objc private func handleDidBecomeActive() {
        appearanceMonitor.applyAppearanceWallpaperIfNeeded()
    }
}
