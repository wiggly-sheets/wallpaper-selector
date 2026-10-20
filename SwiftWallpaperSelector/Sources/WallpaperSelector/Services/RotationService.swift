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
    private(set) var scheduledInterval: TimeInterval?
    /// The requests that arrived while a rotation was running. They run in the
    /// order they arrived, so no request is lost.
    private var pendingActions: [RotationAction] = []
    private var pendingManualPick: URL?

    /// The message that tells the user why the pick is not on the screen yet.
    static let deferredPickMessage =
        "A rotation is in progress - the wallpaper will be applied when it finishes."

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
        // A settings write that fails is reported where the wallpaper errors
        // are, so the menu bar shows it too. The write runs on a queue, so the
        // failure arrives after the wallpaper was applied.
        settingsManager.onError = { [weak self] error in
            guard case .writeFailed = error else { return }
            self?.reportWallpaperError(error.localizedDescription)
        }
    }

    deinit {
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

    /// Clears a wallpaper error that the new settings may have resolved.
    ///
    /// A pending pick keeps its message: it describes the live state, not a
    /// stale condition.
    func clearWallpaperError() {
        guard pendingManualPick == nil else { return }
        lastError = nil
    }

    /// Reports a wallpaper error that happened outside the rotation.
    ///
    /// The appearance monitor uses the same channel, so a failed wallpaper
    /// change is visible everywhere a rotation error is.
    func reportWallpaperError(_ message: String) {
        setError(message)
    }

    /// Sets the message that tells the user what went wrong.
    ///
    /// A pending pick keeps its message: the deferral tells the user why
    /// their pick is not on the screen yet, and that is what they need to
    /// know while the rotation runs.
    private func setError(_ message: String) {
        guard pendingManualPick == nil else { return }
        lastError = message
    }

    func tick() {
        enqueue(settingsManager.settings.rotationAction)
    }

    func enqueue(_ action: RotationAction) {
        guard !isBusy else {
            // The request waits for the running rotation instead of being lost.
            pendingActions.append(action)
            return
        }
        isBusy = true
        Task { [weak self] in
            await self?.runEnqueued(action)
        }
    }

    @discardableResult
    func perform(_ action: RotationAction) async -> URL? {
        guard !isBusy else {
            // The action waits for the running rotation instead of being lost.
            pendingActions.append(action)
            return nil
        }
        isBusy = true
        defer {
            isBusy = false
            drainPendingActions()
        }
        return await performAction(action)
    }

    private func runEnqueued(_ action: RotationAction) async {
        defer {
            isBusy = false
            drainPendingActions()
        }
        _ = await performAction(action)
    }

    /// Runs the requests that arrived while a rotation was running.
    ///
    /// The wallpaper the user picked by hand is applied last, so the pick
    /// stays on the screen instead of being overwritten by the rotation.
    private func drainPendingActions() {
        guard !isBusy else { return }

        if !pendingActions.isEmpty {
            let pending = pendingActions.removeFirst()
            enqueue(pending)
            return
        }

        if let pick = pendingManualPick {
            // The pick is applied even when the rotation failed: the
            // deferral message must not stay and hide a later failure.
            pendingManualPick = nil
            _ = applyWallpaper(pick)
        }
    }

    private func performAction(_ action: RotationAction) async -> URL? {
        // A deferred pick keeps its message until the pick is applied.
        if pendingManualPick == nil {
            lastError = nil
        }

        // A theme action without a theme changes nothing, so the user has to
        // know why the wallpaper stayed the same.
        if action.isThemeAction, !themeActionsAreBlocked, !hasThemes {
            setError("No themes are configured.")
            return nil
        }

        switch action {
        case .themeShuffle:
            guard !themeActionsAreBlocked, hasThemes else { return nil }
            selectTheme(direction: .shuffle)
            return await applySelectedWallpaper(action: .shuffle)
        case .themeNext:
            guard !themeActionsAreBlocked, hasThemes else { return nil }
            selectTheme(direction: .next)
            return await applySelectedWallpaper(action: .shuffle)
        case .themePrevious:
            guard !themeActionsAreBlocked, hasThemes else { return nil }
            selectTheme(direction: .previous)
            return await applySelectedWallpaper(action: .shuffle)
        case .shuffle, .next, .previous:
            return await applySelectedWallpaper(action: action)
        }
    }

    /// While the appearance is matched, the theme is chosen by the system: a
    /// theme action would show one theme and the wallpaper of another one.
    private var themeActionsAreBlocked: Bool {
        settingsManager.settings.matchSystemAppearance
    }

    private var hasThemes: Bool {
        !settingsManager.settings.themes.isEmpty
    }

    /// Applies a wallpaper that the user picked by hand.
    ///
    /// A running rotation would overwrite the pick, so the pick waits for the
    /// rotation instead of losing it. The wait is reported, so the user does
    /// not see a dead tap.
    @discardableResult
    func apply(_ url: URL) -> Bool {
        guard !isBusy else {
            pendingManualPick = url
            lastError = Self.deferredPickMessage
            return false
        }
        return applyWallpaper(url)
    }

    private func applyWallpaper(_ url: URL) -> Bool {
        do {
            try wallpaperProvider.setWallpaper(url)
            recordWallpaper(url)
            return true
        } catch {
            // The wallpaper reached at least one display, so it is on the
            // screen and has to be recorded. The failed display is reported.
            guard (error as? WallpaperProviderError)?.didSetOnAtLeastOneDisplay == true else {
                setError(error.localizedDescription)
                return false
            }
            recordWallpaper(url)
            // The error is reported after the wallpaper was stored: the
            // write of the settings clears the wallpaper error.
            setError(error.localizedDescription)
            return true
        }
    }

    /// Stores the applied wallpaper. A failed settings write is reported, but
    /// the wallpaper is applied all the same.
    private func recordWallpaper(_ url: URL) {
        settingsManager.update { settings in
            settings.currentWallpaper = url.path
            settings.recordWallpaperInHistory(url.path)
        }
        // A deferred pick keeps its message until the pick is applied.
        if pendingManualPick == nil {
            lastError = nil
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        guard interval > 0 else {
            stop()
            return
        }

        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduledInterval = interval
        isRunning = true
    }

    private func applySelectedWallpaper(action: RotationAction) async -> URL? {
        let folders = themeProvider.effectiveFolders()
        guard !folders.isEmpty else {
            setError("No wallpaper folders are configured.")
            return nil
        }

        let images = await wallpaperLibrary.imageURLs(in: folders)
        guard !images.isEmpty else {
            setError("No wallpaper images were found in the selected folders.")
            return nil
        }

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

        return applyWallpaper(selected) ? selected : nil
    }

    private enum ThemeDirection {
        case shuffle
        case next
        case previous
    }

    private func selectTheme(direction: ThemeDirection) {
        let settings = settingsManager.settings
        let themes = settings.themes
        guard !themes.isEmpty else { return }

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

        // Never rewrite the theme that is already active.
        guard newIndex != currentIndex else { return }
        settingsManager.update { $0.activeThemeID = themes[newIndex].id }
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
