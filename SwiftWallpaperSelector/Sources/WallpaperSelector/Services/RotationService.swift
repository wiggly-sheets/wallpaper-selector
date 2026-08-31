import Combine
import Foundation

@MainActor
final class RotationService: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    let settingsManager: SettingsManager

    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private let wallpaperLibrary: WallpaperLibrary
    private var timer: Timer?
    private var scheduledInterval: TimeInterval?

    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider,
        wallpaperLibrary: WallpaperLibrary = .shared
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        self.wallpaperLibrary = wallpaperLibrary
        super.init()
    }

    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        let settings = settingsManager.settings
        guard settings.intervalMinutes != .off, !settings.matchSystemAppearance else {
            stop()
            return
        }
        scheduleTimer(interval: TimeInterval(settings.intervalMinutes.rawValue * 60))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scheduledInterval = nil
        isRunning = false
    }

    func updateSettings() {
        let settings = settingsManager.settings
        guard settings.intervalMinutes != .off, !settings.matchSystemAppearance else {
            stop()
            return
        }

        let desiredInterval = TimeInterval(settings.intervalMinutes.rawValue * 60)
        guard !isRunning || scheduledInterval != desiredInterval else { return }
        scheduleTimer(interval: desiredInterval)
    }

    func tick() {
        enqueue(settingsManager.settings.rotationAction)
    }

    func enqueue(_ action: RotationAction) {
        guard !isBusy else { return }
        Task { [weak self] in
            _ = await self?.perform(action)
        }
    }

    @discardableResult
    func perform(_ action: RotationAction) async -> URL? {
        guard !isBusy else { return nil }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        switch action {
        case .themeShuffle:
            guard selectTheme(direction: .shuffle) else { return nil }
            return await applySelectedWallpaper(action: .shuffle)
        case .themeNext:
            guard selectTheme(direction: .next) else { return nil }
            return await applySelectedWallpaper(action: .shuffle)
        case .themePrevious:
            guard selectTheme(direction: .previous) else { return nil }
            return await applySelectedWallpaper(action: .shuffle)
        case .shuffle, .next, .previous:
            return await applySelectedWallpaper(action: action)
        }
    }

    @discardableResult
    func apply(_ url: URL) -> Bool {
        do {
            try wallpaperProvider.setWallpaper(url)
            settingsManager.update { settings in
                settings.currentWallpaper = url.path
                settings.recordWallpaperInHistory(url.path)
            }
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        guard interval > 0 else {
            stop()
            return
        }

        timer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduledInterval = interval
        isRunning = true
    }

    @objc private func timerDidFire() {
        tick()
    }

    private func applySelectedWallpaper(action: RotationAction) async -> URL? {
        let folders = themeProvider.effectiveFolders()
        guard !folders.isEmpty else { return nil }

        let images = await wallpaperLibrary.imageURLs(in: folders)
        guard !images.isEmpty else { return nil }

        let settings = settingsManager.settings
        let selected: URL
        switch action {
        case .shuffle:
            selected = shuffleSelection(
                from: images,
                excluding: settings.wallpaperHistory,
                currentPath: settings.currentWallpaper
            )
        case .next:
            selected = sequentialSelection(from: images, after: settings.currentWallpaper, direction: 1)
        case .previous:
            selected = sequentialSelection(from: images, after: settings.currentWallpaper, direction: -1)
        case .themeShuffle, .themeNext, .themePrevious:
            return nil
        }

        return apply(selected) ? selected : nil
    }

    private enum ThemeDirection {
        case shuffle
        case next
        case previous
    }

    private func selectTheme(direction: ThemeDirection) -> Bool {
        let settings = settingsManager.settings
        let themes = settings.themes
        guard !themes.isEmpty else { return false }

        let currentIndex = themes.firstIndex { $0.id == settings.activeThemeID }
        let newIndex: Int

        switch direction {
        case .shuffle:
            let alternatives = themes.indices.filter { $0 != currentIndex }
            newIndex = alternatives.randomElement() ?? currentIndex ?? 0
        case .next:
            newIndex = ((currentIndex ?? -1) + 1) % themes.count
        case .previous:
            let previousIndex = (currentIndex ?? 0) - 1
            newIndex = previousIndex < 0 ? themes.count - 1 : previousIndex
        }

        guard newIndex != currentIndex else { return false }
        settingsManager.update { $0.activeThemeID = themes[newIndex].id }
        return true
    }

    private func shuffleSelection(
        from images: [URL],
        excluding history: [String],
        currentPath: String?
    ) -> URL {
        let unseen = images.filter { !history.contains($0.path) && $0.path != currentPath }
        if let selected = unseen.randomElement() {
            return selected
        }

        let alternatives = images.filter { $0.path != currentPath }
        return alternatives.randomElement() ?? images[0]
    }

    private func sequentialSelection(
        from images: [URL],
        after currentPath: String?,
        direction: Int
    ) -> URL {
        guard let currentPath,
              let currentIndex = images.firstIndex(where: { $0.path == currentPath }) else {
            return direction > 0 ? images[0] : images[images.count - 1]
        }

        let nextIndex = currentIndex + direction
        if nextIndex >= images.count {
            return images[0]
        }
        if nextIndex < 0 {
            return images[images.count - 1]
        }
        return images[nextIndex]
    }
}

extension WallpaperSettings {
    mutating func recordWallpaperInHistory(_ path: String) {
        wallpaperHistory.removeAll { $0 == path }
        wallpaperHistory.insert(path, at: 0)
        let validLimit = max(1, historyLimit)
        if wallpaperHistory.count > validLimit {
            wallpaperHistory = Array(wallpaperHistory.prefix(validLimit))
        }
    }
}
