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

    convenience init() {
        self.init(settingsManager: SettingsManager(), injectedHotKeyManager: nil, startsMenuBar: true)
    }

    init(
        settingsManager: SettingsManager,
        injectedHotKeyManager: HotKeyManager?,
        startsMenuBar: Bool
    ) {
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
        hotKeyManager = injectedHotKeyManager ?? HotKeyManager(settingsManager: settingsManager)
        self.launchAtLoginManager = launchAtLoginManager
        self.appState = appState
        settingsViewModel = SettingsViewModel(
            appState: appState,
            launchAtLoginManager: launchAtLoginManager
        )
        allSpacesService = AllSpacesService()
        previousSettings = settingsManager.settings

        appState.settingsPublisher
            .dropFirst()
            .sink { [weak self] settings in self?.handleSettingsChange(settings) }
            .store(in: &cancellables)

        // The system can change the appearance without a settings change: the
        // effective folders and the shown images have to follow it.
        appearanceMonitor.onSystemAppearanceChanged = { [weak self] in
            self?.appState.refreshDerivedState()
        }

        // A wallpaper that could not be applied is reported through the same
        // channel as a failed rotation, so it shows up in the menu bar and in
        // the settings.
        appearanceMonitor.onError = { [weak self] message in
            self?.rotationService.reportWallpaperError(message)
        }

        if startsMenuBar {
            startMenuBar()
        }
        allSpacesService.onResult = { [weak self] result in
            guard case let .manualActionRequired(enabled, reason) = result else { return }
            // The alert runs a modal loop: it must not spin inside the
            // settings publish cascade.
            DispatchQueue.main.async { [weak self] in
                self?.menuBarHostingController?.showAllSpacesManualFallback(
                    enabled: enabled,
                    reason: reason
                )
            }
        }
        hotKeyManager.onHotKeyPressed = { [weak self] identifier in
            self?.menuBarHostingController?.handleHotKey(identifier)
        }
        hotKeyManager.onRegistrationError = { [weak self] message in
            self?.settingsViewModel.setHotKeyErrorMessage(message)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func handleSettingsChange(_ current: WallpaperSettings) {
        let previous = previousSettings
        previousSettings = current

        rotationService.updateSettings()
        if previous.shortcuts != current.shortcuts {
            hotKeyManager.updateShortcuts(current.shortcuts)
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
            // The wallpaper application writes the settings again. Running it
            // inside the publish cascade would nest a second publish.
            Task { @MainActor [weak self] in
                self?.appearanceMonitor.applyAppearanceWallpaperIfNeeded()
            }
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
        // The app that owned the shortcut may have quit: registering again
        // takes the shortcut back. A successful registration reports no error,
        // so the error item disappears on its own.
        hotKeyManager.register()
    }

    /// The settings are written on a queue, so a change that was made a
    /// moment before the quit has to be flushed before the app goes away.
    @objc private func handleWillTerminate() {
        settingsManager.flushPendingWrites()
    }
}
