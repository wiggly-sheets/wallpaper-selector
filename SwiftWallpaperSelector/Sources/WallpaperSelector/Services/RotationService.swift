import Foundation
import AppKit


final class RotationService {

    var intervalSeconds: TimeInterval {
        get { _intervalSeconds }
        set { updateInterval(newValue) }
    }

    private(set) var isRunning: Bool = false

    var themeChangeListener: (() -> Void)?


    let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider


    private var timer: DispatchSourceTimer?
    private var _intervalSeconds: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.wallpaper-selector.rotation", qos: .utility)


    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
    }

    deinit {
        stop()
    }


    func start() {
        let settings = settingsManager.settings
        guard settings.intervalMinutes != .off, !settings.matchSystemAppearance else {
            stop()
            return
        }
        startTimer(intervalSeconds: TimeInterval(settings.intervalMinutes.rawValue * 60))
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    func updateSettings() {
        let settings = settingsManager.settings
        if settings.intervalMinutes == .off || settings.matchSystemAppearance {
            stop()
        } else {
            startTimer(intervalSeconds: TimeInterval(settings.intervalMinutes.rawValue * 60))
        }
    }

    func tick() {
        performRotation()
    }


    private func startTimer(intervalSeconds: TimeInterval) {
        guard intervalSeconds > 0 else {
            stop()
            return
        }
        if isRunning {
            stop()
        }
        stop()

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + intervalSeconds,
            repeating: intervalSeconds
        )
        source.setEventHandler { [weak self] in
            self?.performRotation()
        }
        source.resume()
        timer = source
        isRunning = true
    }

    private func updateInterval(_ newValue: TimeInterval) {
        _intervalSeconds = newValue
        if isRunning {
            if newValue <= 0 {
                stop()
            } else {
                startTimer(intervalSeconds: newValue)
            }
        }
    }

    private func performRotation() {
        let settings = settingsManager.settings

        switch settings.rotationAction {
        case .themeShuffle:
            applyThemeRotation(direction: "random")
        case .themeNext:
            applyThemeRotation(direction: "next")
        case .themePrevious:
            applyThemeRotation(direction: "previous")
        default:
            let folders = themeProvider.effectiveFolders()
            guard !folders.isEmpty else { return }

            guard let url = selectNextWallpaper(
                from: folders,
                action: settings.rotationAction,
                history: settings.wallpaperHistory,
                historyLimit: settings.historyLimit
            ) else { return }

            applyWallpaper(url)
        }
    }

    private func applyWallpaper(_ url: URL) {
        settingsManager.update { s in
            s.currentWallpaper = url.path
            s.recordWallpaperInHistory(url.path)
        }

        do {
            try wallpaperProvider.setWallpaper(url, forAllScreens: true)
        } catch {
            print("[RotationService] Failed to set wallpaper: \(error)")
        }
    }

    func applyThemeRotation(direction: String) {
        let settings = settingsManager.settings
        let themes = settings.themes
        guard !themes.isEmpty else { return }

        let currentIndex = themes.firstIndex { $0.id == settings.activeThemeID }

        let newIndex: Int
        switch direction {
        case "random":
            var candidates = Array(themes.indices)
            if let currentIndex = currentIndex {
                candidates.removeAll { $0 == currentIndex }
            }
            newIndex = candidates.randomElement() ?? currentIndex ?? 0
        case "next":
            newIndex = ((currentIndex ?? -1) + 1) % themes.count
        case "previous":
            let step = (currentIndex ?? 0) - 1
            newIndex = step < 0 ? themes.count - 1 : step
        default:
            return
        }

        guard newIndex != currentIndex else { return }

        let theme = themes[newIndex]
        settingsManager.update { s in
            s.activeThemeID = theme.id
        }
        themeChangeListener?()

        guard let url = randomWallpaperURL(from: themeProvider.effectiveFolders()) else { return }
        applyWallpaper(url)
    }

    private func randomWallpaperURL(from folders: [String]) -> URL? {
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return nil }
        return shuffleSelection(
            from: images,
            excluding: settingsManager.settings.wallpaperHistory,
            currentPath: settingsManager.settings.currentWallpaper
        )
    }

    private func selectNextWallpaper(
        from folders: [String],
        action: RotationAction,
        history: [String],
        historyLimit: Int
    ) -> URL? {
        let allImages = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !allImages.isEmpty else { return nil }

        let currentPath = settingsManager.settings.currentWallpaper

        switch action {
        case .shuffle:
            return shuffleSelection(from: allImages, excluding: history, currentPath: currentPath)
        case .next:
            return sequentialSelection(from: allImages, after: currentPath, direction: 1)
        case .previous:
            return sequentialSelection(from: allImages, after: currentPath, direction: -1)
        default:
            return nil
        }
    }

    private func shuffleSelection(
        from allImages: [URL],
        excluding history: [String],
        currentPath: String?
    ) -> URL {
        let candidates = allImages.filter { url in
            !history.contains(url.path) && url.path != currentPath
        }
        let pool = candidates.isEmpty ? allImages : candidates
        return pool.randomElement() ?? allImages.first!
    }

    private func sequentialSelection(
        from allImages: [URL],
        after currentPath: String?,
        direction: Int
    ) -> URL {
        guard let currentPath = currentPath,
              let currentIndex = allImages.firstIndex(where: { $0.path == currentPath }) else {
            return direction > 0 ? allImages.first! : allImages.last!
        }

        let nextIndex = currentIndex + direction
        if nextIndex >= allImages.count {
            return allImages.first!
        } else if nextIndex < 0 {
            return allImages.last!
        } else {
            return allImages[nextIndex]
        }
    }
}


extension WallpaperSettings {
    mutating func recordWallpaperInHistory(_ path: String) {
        wallpaperHistory.removeAll { $0 == path }
        wallpaperHistory.insert(path, at: 0)
        if wallpaperHistory.count > historyLimit {
            wallpaperHistory = Array(wallpaperHistory.prefix(historyLimit))
        }
    }
}
