import Combine
import Foundation

@MainActor
final class TrayPopoverViewModel: ObservableObject {
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var images: [URL] = []
    @Published private(set) var themes: [Theme] = []
    @Published private(set) var activeThemeID: String?
    @Published private(set) var intervalMinutes: RotationInterval = .off
    @Published private(set) var rotationAction: RotationAction = .shuffle
    @Published private(set) var allSpaces = false
    @Published private(set) var matchSystemAppearance = false
    @Published private(set) var currentWallpaperPath: String?
    @Published private(set) var isRotationRunning = false
    /// The app is changing a wallpaper, so the buttons must grey out.
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    var onShowMainWindow: (() -> Void)?

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        appState.settingsPublisher
            .sink { [weak self] settings in self?.syncFromState(settings) }
            .store(in: &cancellables)
        appState.$effectiveFolders
            .sink { [weak self] folders in self?.folderPaths = folders }
            .store(in: &cancellables)
        appState.$currentThemeImages
            .sink { [weak self] images in self?.images = images }
            .store(in: &cancellables)
        appState.$isRotationRunning
            .sink { [weak self] isRunning in self?.isRotationRunning = isRunning }
            .store(in: &cancellables)
        appState.$isRotationBusy
            .sink { [weak self] isBusy in self?.isBusy = isBusy }
            .store(in: &cancellables)
        appState.$lastWallpaperError
            .sink { [weak self] error in self?.lastError = error }
            .store(in: &cancellables)

        syncFromState(appState.settings)
    }

    var foldersTitle: String {
        switch folderPaths.count {
        case 0:
            return "Wallpaper Selector"
        case 1:
            return (folderPaths[0] as NSString).lastPathComponent
        default:
            return "\(folderPaths.count) folders"
        }
    }

    /// The rotation cannot run while the appearance is matched, so the
    /// interval picker would do nothing. The name states the effect, so a
    /// view binds it without negating it.
    var isRotationControlDisabled: Bool {
        matchSystemAppearance
    }

    /// The theme actions need a theme, and the system picks the theme while
    /// the appearance is matched: a theme action would show one theme and
    /// the wallpaper of another one. The rotation interval does not matter:
    /// the theme actions can be used by hand at any time.
    var isThemeActionEnabled: Bool {
        !themes.isEmpty && !matchSystemAppearance
    }

    func selectWallpaper(_ url: URL) {
        appState.setWallpaper(url)
    }

    func shuffle() {
        appState.shuffleWallpaper()
    }

    func next() {
        appState.applyNextWallpaper()
    }

    func previous() {
        appState.applyPreviousWallpaper()
    }

    func selectTheme(_ themeID: String?) {
        appState.setActiveTheme(themeID)
    }

    func themePrevious() {
        appState.selectPreviousTheme()
    }

    func themeNext() {
        appState.selectNextTheme()
    }

    func themeShuffle() {
        appState.shuffleTheme()
    }

    func setInterval(_ interval: RotationInterval) {
        appState.updateSettings { $0.intervalMinutes = interval }
    }

    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { $0.rotationAction = action }
    }

    func setAllSpaces(_ enabled: Bool) {
        appState.updateSettings { $0.allSpaces = enabled }
    }

    func openSettings() {
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }

    func showMainWindow() {
        onShowMainWindow?()
    }

    private func syncFromState(_ settings: WallpaperSettings) {
        themes = settings.themes
        activeThemeID = settings.activeThemeID
        intervalMinutes = settings.intervalMinutes
        rotationAction = settings.rotationAction
        allSpaces = settings.allSpaces
        matchSystemAppearance = settings.matchSystemAppearance
        currentWallpaperPath = settings.currentWallpaper
    }
}
