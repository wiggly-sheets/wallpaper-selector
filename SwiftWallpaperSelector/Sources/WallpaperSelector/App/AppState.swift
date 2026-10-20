import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settingsManager: SettingsManager

    /// Holds the current settings.
    ///
    /// A subject is used instead of `@Published` because `@Published` publishes
    /// in `willSet`: a subscriber would receive the new value while the
    /// `settings` property still holds the old one.
    private let settingsSubject: CurrentValueSubject<WallpaperSettings, Never>

    /// Publishes every settings change. The new value is stored before it is
    /// published, so `settings` already holds it while the subscribers run.
    var settingsPublisher: AnyPublisher<WallpaperSettings, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    /// The current settings.
    var settings: WallpaperSettings {
        settingsSubject.value
    }

    @Published private(set) var effectiveFolders: [String] = []
    @Published private(set) var currentWallpaperURL: URL?
    @Published private(set) var currentThemeImages: [URL] = []
    /// The images of every configured folder. The pins of all folders are
    /// chosen from this list, not from the images of the active theme.
    @Published private(set) var allFolderImages: [URL] = []
    @Published private(set) var isRotationRunning = false
    @Published private(set) var isRotationBusy = false
    @Published private(set) var lastWallpaperError: String?

    private let rotationService: RotationService
    private let themeProvider: ThemeProvider
    private let wallpaperLibrary: WallpaperLibrary
    private var imageLoadTask: Task<Void, Never>?
    private var allFolderImageLoadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Counts the published settings. A change during a publish means that a
    /// subscriber wrote settings while the change was delivered.
    private var settingsGeneration: UInt = 0

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
        settingsSubject = CurrentValueSubject(settingsManager.settings)

        settingsManager.settingsPublisher
            .sink { [weak self] settings in
                guard let self else { return }
                self.applySettings(settings)
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
        allFolderImageLoadTask?.cancel()
    }

    var hasFolders: Bool {
        !effectiveFolders.isEmpty
    }

    func updateSettings(_ mutation: (inout WallpaperSettings) -> Void) {
        settingsManager.update(mutation)
    }

    func setWallpaper(_ path: String) {
        guard path.hasPrefix("/") else { return }
        setWallpaper(URL(fileURLWithPath: path))
    }

    func setWallpaper(_ url: URL) {
        // A running rotation would overwrite the pick, so the rotation
        // service applies it when the rotation is done. The wait is reported
        // through `lastWallpaperError`.
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

    /// Stores the new settings and then notifies the subscribers.
    ///
    /// `objectWillChange` fires before the value changes, so SwiftUI redraws
    /// with the new value.
    private func applySettings(_ settings: WallpaperSettings) {
        // The wallpaper error lives in the rotation service, so a settings
        // change has to clear it there: the new settings may have resolved
        // the problem that caused it.
        rotationService.clearWallpaperError()
        objectWillChange.send()
        settingsGeneration &+= 1
        // The generation is counted after the increment: only a nested write
        // counts the generation up while the change is published.
        let generationBeforeSend = settingsGeneration
        settingsSubject.send(settings)
        if settingsGeneration != generationBeforeSend {
            // A subscriber wrote settings while the change was published: the
            // subscribers after it would still get the older value. The newest
            // value is published again, so every subscriber ends on it.
            settingsSubject.send(settingsSubject.value)
        }
        refreshDerivedState()
    }

    func refreshDerivedState() {
        effectiveFolders = themeProvider.effectiveFolders()
        currentWallpaperURL = settings.currentWallpaper.map(URL.init(fileURLWithPath:))
        refreshImages(for: effectiveFolders)
        refreshAllFolderImages(for: settings.folderPaths)
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

    private func refreshAllFolderImages(for folders: [String]) {
        allFolderImageLoadTask?.cancel()
        guard !folders.isEmpty else {
            allFolderImages = []
            return
        }

        allFolderImageLoadTask = Task { [weak self, wallpaperLibrary] in
            let images = await wallpaperLibrary.imageURLs(in: folders)
            guard !Task.isCancelled, let self, self.settings.folderPaths == folders else { return }
            self.allFolderImages = images
        }
    }
}
