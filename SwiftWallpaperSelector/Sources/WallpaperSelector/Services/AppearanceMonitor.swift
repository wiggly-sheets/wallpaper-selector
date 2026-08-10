import Foundation
import AppKit

// MARK: - AppearanceMonitor

/// Observes system appearance changes and applies the appropriate
/// light/dark wallpaper when `matchSystemAppearance` is enabled.
///
/// Uses KVO on `NSApplication.effectiveAppearance` to detect
/// appearance changes, since there is no dedicated notification.
final class AppearanceMonitor: NSObject {
    // MARK: - Public

    /// Closure called when the wallpaper should be changed due to an appearance change.
    var onAppearanceChanged: ((String?) -> Void)?

    // MARK: - Private

    private let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private var observation: NSKeyValueObservation?

    // MARK: - Init

    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        super.init()

        // Observe effectiveAppearance changes on NSApplication
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.applyAppearanceWallpaperIfNeeded()
        }
    }

    deinit {
        observation = nil
    }

    // MARK: - Public API

    /// Check the current appearance and apply the appropriate wallpaper
    /// if `matchSystemAppearance` is enabled.
    func applyAppearanceWallpaperIfNeeded() {
        let settings = settingsManager.settings
        guard settings.matchSystemAppearance else { return }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let targetThemeID = isDark ? settings.appearanceDarkThemeID : settings.appearanceLightThemeID
        let themeChanged = targetThemeID != settings.activeThemeID
        if themeChanged {
            settingsManager.update { $0.activeThemeID = targetThemeID }
        }
        let (lightWallpaper, darkWallpaper) = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: isDark)

        // Select the appropriate wallpaper based on current appearance
        let selectedPath = isDark ? darkWallpaper : lightWallpaper

        if let path = selectedPath, path.hasPrefix("/"), path != settingsManager.settings.currentWallpaper {
            applyWallpaper(at: URL(fileURLWithPath: path))
        } else if themeChanged {
            // Fall back to a random image from the current scope
            let folders = themeProvider.effectiveFolders()
            if let randomURL = randomWallpaperURL(from: folders) {
                applyWallpaper(at: randomURL)
            }
        }
    }

    // MARK: - Private

    private func applyWallpaper(at url: URL) {
        do {
            try wallpaperProvider.setWallpaper(url, forAllScreens: true)
            settingsManager.update {
                $0.currentWallpaper = url.path
                $0.recordWallpaperInHistory(url.path)
            }
            onAppearanceChanged?(url.path)
        } catch {
            print("[AppearanceMonitor] Failed to apply wallpaper: \(error)")
        }
    }

    private func randomWallpaperURL(from folders: [String]) -> URL? {
        let urls = ImageDiscoveryService.collectImageURLs(from: folders)
        return urls.randomElement()
    }
}
