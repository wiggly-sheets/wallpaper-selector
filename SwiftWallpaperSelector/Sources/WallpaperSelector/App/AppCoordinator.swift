import AppKit
import Combine
import Foundation

/// A screen of the Mac that can report the wallpaper it shows.
///
/// The protocol is the seam a test uses: the screens of macOS cannot be
/// built in a test.
@MainActor
protocol DesktopScreenProviding: AnyObject {
    /// The wallpaper of the screen.
    var desktopImageURL: URL? { get }
}

extension NSScreen: DesktopScreenProviding {
    var desktopImageURL: URL? {
        NSWorkspace.shared.desktopImageURL(for: self)
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let settingsManager: SettingsManager
    let wallpaperProvider: WallpaperSetting
    let themeProvider: ThemeProvider
    let rotationService: RotationService
    let appearanceMonitor: AppearanceMonitor
    let hotKeyManager: HotKeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    let appState: AppState
    let settingsViewModel: SettingsViewModel

    private let allSpacesApplier: AllSpacesApplier
    private let desktopImageURL: @MainActor () -> URL?
    private var cancellables = Set<AnyCancellable>()
    private var previousSettings: WallpaperSettings
    private var menuBarHostingController: MenuBarHostingViewController?

    convenience init() {
        self.init(
            settingsManager: SettingsManager(),
            injectedHotKeyManager: nil,
            injectedWallpaperProvider: nil,
            allSpacesApplier: AllSpacesApplier(
                storeURL: WallpaperStore.defaultStoreURL,
                agent: .live
            ),
            injectedDesktopImageURL: { AppCoordinator.currentDesktopImageURL() },
            startsMenuBar: true
        )
    }

    init(
        settingsManager: SettingsManager,
        injectedHotKeyManager: HotKeyManager?,
        injectedWallpaperProvider: WallpaperSetting? = nil,
        allSpacesApplier: AllSpacesApplier,
        injectedDesktopImageURL: @escaping @MainActor () -> URL? = { AppCoordinator.currentDesktopImageURL() },
        notificationName: Notification.Name = AppearanceMonitor.appearanceNotificationName,
        startsMenuBar: Bool
    ) {
        let applier = allSpacesApplier
        let wallpaperProvider = injectedWallpaperProvider ?? WallpaperProvider(
            applyToAllSpaces: { url in
                // The user can turn the setting off at any moment, so it is
                // read when the wallpaper is applied and not when the app
                // starts.
                guard settingsManager.settings.allSpaces else { return }
                applier.apply(url)
            }
        )
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider
        )
        let appearanceMonitor = AppearanceMonitor(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            notificationName: notificationName
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
        self.allSpacesApplier = applier
        self.desktopImageURL = injectedDesktopImageURL
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

        // A wallpaper that could not be put on every Space is reported
        // through the same channel, so the menu bar and the settings show it
        // too.
        allSpacesApplier.onResult = { [weak self] result in
            guard case .failure(let failure) = result else { return }
            self?.rotationService.reportWallpaperError(failure.errorDescription ?? "")
        }

        if startsMenuBar {
            startMenuBar()
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
            if current.allSpaces {
                applyCurrentWallpaperToAllSpaces()
            }
            // The app only stops patching when the setting is switched off.
            // Nothing is restored: the next wallpaper change writes a
            // per-Space entry through `setDesktopImageURL`, which ends the
            // global state on its own.
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

    /// Puts the wallpaper that is on the screen on every Space.
    ///
    /// The wallpaper on the screen is the one the user sees, also when it
    /// was changed in the System Settings and not through the app. The
    /// wallpaper of the settings is the fallback, for a screen that reports
    /// no wallpaper at all.
    ///
    /// The wallpaper is put on every Space right away, so the user does not
    /// have to wait for the next rotation. A wallpaper that is gone is left
    /// alone: the next rotation picks a new one.
    private func applyCurrentWallpaperToAllSpaces() {
        guard let url = wallpaperOnScreen() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        allSpacesApplier.apply(url)
    }

    /// The wallpaper that is on the screen.
    private func wallpaperOnScreen() -> URL? {
        if let onScreen = desktopImageURL() { return onScreen }
        guard let path = settingsManager.settings.currentWallpaper else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The wallpaper of the screen of the Mac.
    ///
    /// The app is an accessory app without a key window, so the screen with
    /// the key can be missing: the user turns All Spaces on from the menu
    /// bar while no window has the key. Every screen is asked in turn, so
    /// the wallpaper of a screen that shows one is found.
    ///
    /// The screens are a parameter, so a test can ask for the wallpaper
    /// without a Mac in front of it.
    @MainActor
    static func currentDesktopImageURL(
        screens: [DesktopScreenProviding] = NSScreen.screens.map { $0 as DesktopScreenProviding }
    ) -> URL? {
        for screen in screens {
            if let url = screen.desktopImageURL { return url }
        }
        return nil
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
        // The wallpaper of the appearance is not applied here: the pin is
        // enforced when the appearance changes and when the user changes the
        // pin, the theme or the matching. A wallpaper the user picked by hand
        // has to survive the wake-up of the app.
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
