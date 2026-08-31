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
    @Published private(set) var currentWallpaperPath: String?
    @Published private(set) var isRotationRunning = false

    var onShowMainWindow: (() -> Void)?

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        appState.$settings
            .sink { [weak self] _ in self?.syncFromState() }
            .store(in: &cancellables)
        appState.$currentThemeImages
            .sink { [weak self] images in self?.images = images }
            .store(in: &cancellables)
        appState.$isRotationRunning
            .sink { [weak self] isRunning in self?.isRotationRunning = isRunning }
            .store(in: &cancellables)

        syncFromState()
    }

    var isBusy: Bool {
        appState.isRotationBusy
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

    private func syncFromState() {
        let settings = appState.settings
        folderPaths = appState.effectiveFolders
        themes = settings.themes
        activeThemeID = settings.activeThemeID
        intervalMinutes = settings.intervalMinutes
        rotationAction = settings.rotationAction
        allSpaces = settings.allSpaces
        currentWallpaperPath = settings.currentWallpaper
    }
}
