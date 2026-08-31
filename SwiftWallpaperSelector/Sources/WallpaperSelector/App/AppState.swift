import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settingsManager: SettingsManager

    @Published private(set) var settings: WallpaperSettings
    @Published private(set) var effectiveFolders: [String] = []
    @Published private(set) var currentWallpaperURL: URL?
    @Published private(set) var currentThemeImages: [URL] = []
    @Published private(set) var isRotationRunning = false
    @Published private(set) var isRotationBusy = false
    @Published private(set) var lastWallpaperError: String?

    private let rotationService: RotationService
    private let themeProvider: ThemeProvider
    private let wallpaperLibrary: WallpaperLibrary
    private var imageLoadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsManager: SettingsManager,
        rotationService: RotationService,
        themeProvider: ThemeProvider,
        wallpaperLibrary: WallpaperLibrary = .shared
    ) {
        self.settingsManager = settingsManager
        self.rotationService = rotationService
        self.themeProvider = themeProvider
        self.wallpaperLibrary = wallpaperLibrary
        settings = settingsManager.settings

        settingsManager.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                self.settings = settings
                self.refreshDerivedState()
            }
            .store(in: &cancellables)

        rotationService.$isRunning
            .assign(to: &$isRotationRunning)
        rotationService.$isBusy
            .assign(to: &$isRotationBusy)
        rotationService.$lastError
            .assign(to: &$lastWallpaperError)

        refreshDerivedState()
    }

    deinit {
        imageLoadTask?.cancel()
    }

    var hasFolders: Bool {
        !effectiveFolders.isEmpty
    }

    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: isDarkAppearance)
    }

    func updateSettings(_ mutation: (inout WallpaperSettings) -> Void) {
        settingsManager.update(mutation)
    }

    func reloadDerivedState() {
        Task { [weak self] in
            guard let self else { return }
            await wallpaperLibrary.invalidate()
            guard !Task.isCancelled else { return }
            refreshDerivedState()
        }
    }

    func setWallpaper(_ path: String) {
        guard path.hasPrefix("/") else { return }
        setWallpaper(URL(fileURLWithPath: path))
    }

    func setWallpaper(_ url: URL) {
        _ = rotationService.apply(url)
    }

    func shuffleWallpaper() {
        rotationService.enqueue(.shuffle)
    }

    func applyNextWallpaper() {
        rotationService.enqueue(.next)
    }

    func applyPreviousWallpaper() {
        rotationService.enqueue(.previous)
    }

    func shuffleTheme() {
        rotationService.enqueue(.themeShuffle)
    }

    func selectNextTheme() {
        rotationService.enqueue(.themeNext)
    }

    func selectPreviousTheme() {
        rotationService.enqueue(.themePrevious)
    }

    func setActiveTheme(_ themeID: String?) {
        guard themeID == nil || settings.themes.contains(where: { $0.id == themeID }) else { return }
        updateSettings { $0.activeThemeID = themeID }
        if !settingsManager.settings.matchSystemAppearance {
            rotationService.enqueue(.shuffle)
        }
    }

    func isCurrentWallpaper(_ path: String) -> Bool {
        settings.currentWallpaper == path
    }

    func isCurrentWallpaper(_ url: URL) -> Bool {
        isCurrentWallpaper(url.path)
    }

    func updateRotationSettings() {
        rotationService.updateSettings()
    }

    private func refreshDerivedState() {
        effectiveFolders = themeProvider.effectiveFolders()
        currentWallpaperURL = settings.currentWallpaper.map(URL.init(fileURLWithPath:))
        refreshImages(for: effectiveFolders)
    }

    private func refreshImages(for folders: [String]) {
        imageLoadTask?.cancel()
        guard !folders.isEmpty else {
            currentThemeImages = []
            return
        }

        imageLoadTask = Task { [weak self, wallpaperLibrary] in
            let images = await wallpaperLibrary.imageURLs(in: folders)
            guard !Task.isCancelled, let self, self.effectiveFolders == folders else { return }
            self.currentThemeImages = images
        }
    }
}
