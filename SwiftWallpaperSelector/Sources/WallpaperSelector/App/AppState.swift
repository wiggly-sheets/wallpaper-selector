
import Foundation
import Combine
import AppKit

final class AppState: ObservableObject {
    let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var settings: WallpaperSettings = .init()
    @Published var effectiveFolders: [String] = []
    @Published var currentWallpaperURL: URL? = nil
    @Published var isRotationRunning: Bool = false

    init(settingsManager: SettingsManager,
         themeProvider: ThemeProvider,
         wallpaperProvider: WallpaperSetting) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.settings = settingsManager.settings

        refreshDerivedState()
        settingsManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.settings = settings
                self?.refreshDerivedState()
            }
            .store(in: &cancellables)
    }


    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        let provider = ThemeProvider(settingsManager: settingsManager)
        return provider.effectiveAppearanceWallpapers(isDarkAppearance: isDarkAppearance)
    }


    func updateSettings(_ mutation: (inout WallpaperSettings) -> Void) {
        settingsManager.update(mutation)
        settings = settingsManager.settings
        refreshDerivedState()
    }

    func reloadDerivedState() {
        refreshDerivedState()
    }

    private func refreshDerivedState() {
        let provider = ThemeProvider(settingsManager: settingsManager)
        effectiveFolders = provider.effectiveFolders()
        currentWallpaperURL = settingsManager.settings.currentWallpaper.map { URL(fileURLWithPath: $0) }
        isRotationRunning = settings.intervalMinutes != .off && !settings.matchSystemAppearance
    }


    func setWallpaper(_ path: String) {
        guard path.hasPrefix("/") else { return }
        setWallpaper(URL(fileURLWithPath: path))
    }

    func setWallpaper(_ url: URL) {
        do {
            try wallpaperProvider.setWallpaper(url, forAllScreens: true)
            updateSettings { settings in
                settings.currentWallpaper = url.path
                settings.recordWallpaperInHistory(url.path)
            }
        } catch {
            print("[AppState] Failed to set wallpaper: \(error)")
        }
    }

    func shuffleWallpaper() {
        let folders = effectiveFolders
        guard !folders.isEmpty else { return }
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return }

        let currentPath = settings.currentWallpaper
        let history = settings.wallpaperHistory

        let candidates = images.filter { url in
            !history.contains(url.path) && url.path != currentPath
        }
        let pool = candidates.isEmpty ? images : candidates
        if let selected = pool.randomElement() {
            setWallpaper(selected)
        }
    }

    func applyNextWallpaper() {
        applySequentialWallpaper(direction: 1)
    }

    func applyPreviousWallpaper() {
        applySequentialWallpaper(direction: -1)
    }

    private func applySequentialWallpaper(direction: Int) {
        let folders = effectiveFolders
        guard !folders.isEmpty else { return }
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return }

        let currentPath = settings.currentWallpaper

        guard let currentPath = currentPath,
              let currentIndex = images.firstIndex(where: { $0.path == currentPath }) else {
            let selected = direction > 0 ? images.first! : images.last!
            setWallpaper(selected)
            return
        }

        let nextIndex = currentIndex + direction
        if nextIndex >= images.count {
            setWallpaper(images.first!)
        } else if nextIndex < 0 {
            setWallpaper(images.last!)
        } else {
            setWallpaper(images[nextIndex])
        }
    }

    func applyAppearanceWallpaperIfNeeded() {
        guard !settings.matchSystemAppearance else {
            return
        }
        if let current = settings.currentWallpaper,
           effectiveFolders.contains(URL(fileURLWithPath: current).deletingLastPathComponent().path) {
            return
        }
        shuffleWallpaper()
    }


    func setActiveTheme(_ themeID: String?) {
        updateSettings { settings in
            settings.activeThemeID = themeID
        }
        if settings.matchSystemAppearance {
        } else {
            shuffleWallpaper()
        }
    }


    var hasFolders: Bool {
        !effectiveFolders.isEmpty
    }

    var isRotationBusy: Bool {
        false
    }

    var currentThemeImages: [URL] {
        ImageDiscoveryService.collectImageURLs(from: effectiveFolders)
    }

    func isCurrentWallpaper(_ path: String) -> Bool {
        settings.currentWallpaper == path
    }

    func isCurrentWallpaper(_ url: URL) -> Bool {
        settings.currentWallpaper == url.path
    }


    func updateRotationSettings() {
        reloadDerivedState()
    }
}
