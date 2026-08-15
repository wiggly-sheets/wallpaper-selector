import Foundation
import AppKit


final class AppearanceMonitor: NSObject {

    var onAppearanceChanged: ((String?) -> Void)?


    private let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private var observation: NSKeyValueObservation?


    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        super.init()

        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.applyAppearanceWallpaperIfNeeded()
        }
    }

    deinit {
        observation = nil
    }


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

        let selectedPath = isDark ? darkWallpaper : lightWallpaper

        if let path = selectedPath, path.hasPrefix("/"), path != settingsManager.settings.currentWallpaper {
            applyWallpaper(at: URL(fileURLWithPath: path))
        } else if themeChanged {
            let folders = themeProvider.effectiveFolders()
            if let randomURL = randomWallpaperURL(from: folders) {
                applyWallpaper(at: randomURL)
            }
        }
    }


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
