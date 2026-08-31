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

    var onAppearanceChanged: ((String?) -> Void)?

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
        notificationCenter: DistributedNotificationCenter = .default()
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
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        applyTask?.cancel()
        notificationCenter.removeObserver(self)
    }

    func applyAppearanceWallpaperIfNeeded() {
        applyTask?.cancel()
        applyTask = nil

        let settings = settingsManager.settings
        guard settings.matchSystemAppearance else { return }

        let isDark = appearanceProvider.isDarkAppearance
        let targetThemeID = isDark ? settings.appearanceDarkThemeID : settings.appearanceLightThemeID
        if targetThemeID != settings.activeThemeID {
            settingsManager.update { $0.activeThemeID = targetThemeID }
        }

        let wallpapers = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: isDark)
        let pinnedPath = isDark ? wallpapers.dark : wallpapers.light

        if let pinnedURL = validWallpaperURL(for: pinnedPath) {
            // Changing Theme must not replace the pin when the pin is already
            // the current wallpaper.
            guard !pathsReferToSameFile(pinnedURL.path, settingsManager.settings.currentWallpaper) else {
                return
            }
            applyWallpaper(at: pinnedURL)
            return
        }

        let folders = themeProvider.effectiveFolders()
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
            settingsManager.update {
                $0.currentWallpaper = url.path
                $0.recordWallpaperInHistory(url.path)
            }
            onAppearanceChanged?(url.path)
        } catch {
            print("[AppearanceMonitor] Failed to apply wallpaper: \(error)")
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
              themeProvider.effectiveFolders() == folders else { return }

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
