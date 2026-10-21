import Foundation

/// Reads the macOS appearance rather than the app's effective appearance.
///
/// `NSApplication.effectiveAppearance` includes an app-specific `appearance`
/// override, so it cannot be used for the "Match System Appearance" feature.
protocol SystemAppearanceProviding {
    var isDarkAppearance: Bool { get }
}

struct SystemAppearanceProvider: SystemAppearanceProviding {
    var isDarkAppearance: Bool {
        (CFPreferencesCopyValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String)?
            .caseInsensitiveCompare("Dark") == .orderedSame
    }
}

@MainActor
final class AppearanceMonitor: NSObject {
    typealias WallpaperDiscovery = @Sendable ([String]) async -> [URL]

    /// The name of the notification that reports a change of the appearance.
    ///
    /// The name is a parameter of the monitor, so a test can listen to a
    /// name that no system notification uses. Every observer of the
    /// distributed centre receives the real notification, so a test that
    /// listens to it breaks when the appearance of the machine changes.
    nonisolated static let appearanceNotificationName = Notification.Name("AppleInterfaceThemeChangedNotification")

    var onAppearanceChanged: ((String?) -> Void)?

    /// Reports every appearance change, even when no wallpaper was applied.
    var onSystemAppearanceChanged: (() -> Void)?

    /// Reports a wallpaper that could not be applied.
    ///
    /// The rotation service has the same channel, so a failed wallpaper
    /// change is visible in the menu bar and in the settings.
    var onError: ((String) -> Void)?

    private let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private let appearanceProvider: SystemAppearanceProviding
    private let fileManager: FileManager
    private let discoverWallpapers: WallpaperDiscovery
    private let notificationCenter: DistributedNotificationCenter
    private var applyTask: Task<Void, Never>?

    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider,
        appearanceProvider: SystemAppearanceProviding = SystemAppearanceProvider(),
        fileManager: FileManager = .default,
        wallpaperLibrary: WallpaperLibrary = .shared,
        discoverWallpapers: WallpaperDiscovery? = nil,
        notificationCenter: DistributedNotificationCenter = .default(),
        notificationName: Notification.Name = AppearanceMonitor.appearanceNotificationName
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        self.appearanceProvider = appearanceProvider
        self.fileManager = fileManager
        self.discoverWallpapers = discoverWallpapers ?? { folders in
            await wallpaperLibrary.imageURLs(in: folders)
        }
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        applyTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    /// Applies the wallpaper of the current appearance.
    ///
    /// The call belongs to the moments in which the appearance context
    /// changes: the startup, a change of the pin, the theme or the matching,
    /// and the system appearance itself. It does not belong to the wake-up of
    /// the app, so a wallpaper the user picked by hand stays on the screen.
    func applyAppearanceWallpaperIfNeeded() {
        applyTask?.cancel()
        applyTask = nil

        // The scope and the shown images depend on the appearance, so the
        // change is reported before any early return.
        onSystemAppearanceChanged?()

        let settings = settingsManager.settings
        guard settings.matchSystemAppearance else { return }

        let isDark = appearanceProvider.isDarkAppearance

        let wallpapers = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: isDark)
        let pinnedPath = isDark ? wallpapers.dark : wallpapers.light

        if let pinnedURL = validWallpaperURL(for: pinnedPath) {
            // Changing Theme must not replace the pin when the pin is already
            // the current wallpaper.
            guard !pathsReferToSameFile(pinnedURL.path, settingsManager.settings.currentWallpaper) else {
                return
            }
            // The pin is a standing instruction of the user: it is enforced
            // when the appearance changes and when the user changes the pin,
            // the theme or the matching itself. It is not enforced when the
            // app wakes up, so a wallpaper the user picked by hand survives.
            applyWallpaper(at: pinnedURL)
            return
        }

        let folders = themeProvider.effectiveFolders(isDarkAppearance: isDark)
        let discoverWallpapers = self.discoverWallpapers
        applyTask = Task { @MainActor [weak self] in
            let availableWallpapers = await discoverWallpapers(folders)
            guard !Task.isCancelled, let self else { return }
            applyFallbackIfRequestIsCurrent(
                availableWallpapers,
                folders: folders,
                expectedDarkAppearance: isDark,
                expectedPinnedPath: pinnedPath
            )
        }
    }

    @objc nonisolated private func systemAppearanceDidChange() {
        Task { @MainActor [weak self] in
            self?.applyAppearanceWallpaperIfNeeded()
        }
    }

    private func applyWallpaper(at url: URL) {
        do {
            try wallpaperProvider.setWallpaper(url)
        } catch {
            // The wallpaper reached at least one display, so it is on the
            // screen and has to be recorded. The failed display is reported.
            guard (error as? WallpaperProviderError)?.didSetOnAtLeastOneDisplay == true else {
                print("[AppearanceMonitor] Failed to apply wallpaper: \(error)")
                onError?(error.localizedDescription)
                return
            }
            recordWallpaper(url)
            print("[AppearanceMonitor] Failed to apply wallpaper on every display: \(error)")
            // The error is reported after the wallpaper was stored: the write
            // of the settings clears the wallpaper error.
            onError?(error.localizedDescription)
            return
        }

        recordWallpaper(url)
        onAppearanceChanged?(url.path)
    }

    /// Stores the applied wallpaper.
    ///
    /// The settings manager writes the file on its write queue and reports a
    /// failed write itself, so the wallpaper is applied all the same.
    private func recordWallpaper(_ url: URL) {
        settingsManager.update {
            $0.currentWallpaper = url.path
            $0.recordWallpaperInHistory(url.path)
        }
    }

    private func applyFallbackIfRequestIsCurrent(
        _ discoveredWallpapers: [URL],
        folders: [String],
        expectedDarkAppearance: Bool,
        expectedPinnedPath: String?
    ) {
        guard settingsManager.settings.matchSystemAppearance,
              appearanceProvider.isDarkAppearance == expectedDarkAppearance,
              themeProvider.effectiveFolders(isDarkAppearance: expectedDarkAppearance) == folders else { return }

        let currentPins = themeProvider.effectiveAppearanceWallpapers(
            isDarkAppearance: expectedDarkAppearance
        )
        let currentPinnedPath = expectedDarkAppearance ? currentPins.dark : currentPins.light
        guard currentPinnedPath == expectedPinnedPath else { return }

        let availableWallpapers = discoveredWallpapers.filter {
            ImageDiscoveryService.imageExtensions.contains($0.pathExtension.lowercased())
        }
        guard !availableWallpapers.isEmpty else { return }

        // A missing pin should not shuffle the desktop every time the app is
        // activated. Keep the current image when it is an available fallback.
        if let currentPath = settingsManager.settings.currentWallpaper,
           availableWallpapers.contains(where: { pathsReferToSameFile($0.path, currentPath) }) {
            return
        }

        if let selectedFallback = availableWallpapers.randomElement(),
           let fallback = validWallpaperURL(for: selectedFallback.path) {
            applyWallpaper(at: fallback)
        }
    }

    private func validWallpaperURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty, NSString(string: path).isAbsolutePath else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        guard ImageDiscoveryService.imageExtensions.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()
        ) else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func pathsReferToSameFile(_ firstPath: String, _ secondPath: String?) -> Bool {
        guard let secondPath else { return false }
        return URL(fileURLWithPath: firstPath).standardizedFileURL.path
            == URL(fileURLWithPath: secondPath).standardizedFileURL.path
    }
}
