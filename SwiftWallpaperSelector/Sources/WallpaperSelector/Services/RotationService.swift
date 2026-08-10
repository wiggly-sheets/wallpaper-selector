import Foundation
import AppKit

// MARK: - RotationService

/// Manages timed wallpaper rotation using a `DispatchSourceTimer`.
///
/// On each tick the service:
/// 1. Reads the current settings from `SettingsManager`.
/// 2. Determines the effective folder list via `ThemeProvider`.
/// 3. Selects the next image based on `rotationAction`, respecting history.
/// 4. Updates `currentWallpaper` in `SettingsManager`.
/// 5. Delegates to `WallpaperSetting.setWallpaper`.
///
/// The timer is paused whenever `matchSystemAppearance` is `true`.
final class RotationService {
    // MARK: - Public

    /// The interval (in seconds) between rotation ticks.
    /// A value of `0` means the timer is stopped.
    var intervalSeconds: TimeInterval {
        get { _intervalSeconds }
        set { updateInterval(newValue) }
    }

    /// Whether the rotation timer is currently running.
    private(set) var isRunning: Bool = false

    /// Closure called whenever the active theme changes.
    var themeChangeListener: (() -> Void)?

    // MARK: - Dependencies

    let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider

    // MARK: - Private State

    private var timer: DispatchSourceTimer?
    private var _intervalSeconds: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.wallpaper-selector.rotation", qos: .utility)

    // MARK: - Init

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

    // MARK: - Public API

    /// Start the rotation timer if `intervalMinutes > 0` and `matchSystemAppearance` is `false`.
    func start() {
        let settings = settingsManager.settings
        guard settings.intervalMinutes != .off, !settings.matchSystemAppearance else {
            stop()
            return
        }
        startTimer(intervalSeconds: TimeInterval(settings.intervalMinutes.rawValue * 60))
    }

    /// Stop the rotation timer.
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    /// Update the timer based on current settings (call when settings change).
    func updateSettings() {
        let settings = settingsManager.settings
        if settings.intervalMinutes == .off || settings.matchSystemAppearance {
            stop()
        } else {
            startTimer(intervalSeconds: TimeInterval(settings.intervalMinutes.rawValue * 60))
        }
    }

    /// Manually trigger a rotation tick (useful for testing or immediate application).
    /// This method is synchronous — it performs the rotation inline and blocks until complete.
    func tick() {
        performRotation()
    }

    // MARK: - Private

    private func startTimer(intervalSeconds: TimeInterval) {
        guard intervalSeconds > 0 else {
            stop()
            return
        }
        if isRunning {
            // Already running — restart with new interval.
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

    /// Apply a wallpaper: update `currentWallpaper`, record history, and set it on the desktop.
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

    /// Rotate the active theme per `direction` and apply a random wallpaper from the new theme's scope.
    ///
    /// - `"random"`: pick a random theme, avoiding the current one when more than one exists.
    /// - `"next"` / `"previous"`: cycle through the themes array.
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

    /// Pick a random wallpaper URL from the given folders, avoiding current/history repeats.
    private func randomWallpaperURL(from folders: [String]) -> URL? {
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return nil }
        return shuffleSelection(
            from: images,
            excluding: settingsManager.settings.wallpaperHistory,
            currentPath: settingsManager.settings.currentWallpaper
        )
    }

    /// Select the next wallpaper URL based on the rotation action.
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

    /// Pick a random image, avoiding recent history when possible.
    private func shuffleSelection(
        from allImages: [URL],
        excluding history: [String],
        currentPath: String?
    ) -> URL {
        // Filter out images that are in the history (unless all are in history)
        let candidates = allImages.filter { url in
            !history.contains(url.path) && url.path != currentPath
        }
        let pool = candidates.isEmpty ? allImages : candidates
        return pool.randomElement() ?? allImages.first!
    }

    /// Pick the next image after `currentPath` in the list, cycling.
    private func sequentialSelection(
        from allImages: [URL],
        after currentPath: String?,
        direction: Int
    ) -> URL {
        guard let currentPath = currentPath,
              let currentIndex = allImages.firstIndex(where: { $0.path == currentPath }) else {
            // No current wallpaper or not in list — return first or last
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

// MARK: - WallpaperSettings Extension

extension WallpaperSettings {
    /// Record a wallpaper path in the history, deduplicating and respecting the limit.
    mutating func recordWallpaperInHistory(_ path: String) {
        wallpaperHistory.removeAll { $0 == path }
        wallpaperHistory.insert(path, at: 0)
        if wallpaperHistory.count > historyLimit {
            wallpaperHistory = Array(wallpaperHistory.prefix(historyLimit))
        }
    }
}
