import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var menuTitle = "All Folders"
    @Published private(set) var isRotationActive = false
    @Published private(set) var selectedThemeID: String?
    @Published private(set) var themes: [Theme] = []
    @Published private(set) var recentWallpapers: [String] = []
    @Published private(set) var currentWallpaper: String?
    @Published private(set) var folderPaths: [String] = []
    @Published private(set) var intervalMinutes: RotationInterval = .off
    @Published private(set) var rotationAction: RotationAction = .shuffle
    @Published private(set) var allSpaces = false
    @Published private(set) var matchSystemAppearance = false
    @Published private(set) var lastWallpaperError: String?
    @Published private(set) var hotKeyErrorMessage: String?

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, settingsViewModel: SettingsViewModel) {
        self.appState = appState

        appState.settingsPublisher
            .sink { [weak self] settings in self?.refreshUIState(settings) }
            .store(in: &cancellables)
        appState.$isRotationRunning
            .sink { [weak self] isRunning in self?.isRotationActive = isRunning }
            .store(in: &cancellables)
        appState.$lastWallpaperError
            .sink { [weak self] error in self?.lastWallpaperError = error }
            .store(in: &cancellables)
        settingsViewModel.$hotKeyErrorMessage
            .sink { [weak self] message in self?.hotKeyErrorMessage = message }
            .store(in: &cancellables)

        refreshUIState(appState.settings)
    }

    /// The failures the menu bar has to show: the last wallpaper failure and
    /// the hot-key registration failure.
    var errorMessages: [String] {
        [lastWallpaperError, hotKeyErrorMessage].compactMap { $0 }
    }

    /// The rotation cannot run while the appearance is matched, so the menu
    /// item would do nothing. The name states the effect, so a view binds it
    /// without negating it.
    var isRotationControlDisabled: Bool {
        matchSystemAppearance
    }

    /// The wallpapers of the recent menu. The history is already bounded by
    /// the limit of the settings, so every entry is shown.
    var displayedRecentWallpapers: [String] {
        recentWallpapers
    }

    /// A wallpaper whose file is gone cannot be applied, so its menu item is
    /// disabled.
    func canApplyRecentWallpaper(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
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

    func openSettings() {
        NotificationCenter.default.post(name: .MenuBarOpenSettings, object: nil)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func toggleRotation() {
        setInterval(intervalMinutes == .off ? .hour1 : .off)
    }

    func setActiveTheme(_ themeID: String?) {
        appState.setActiveTheme(themeID)
    }

    func selectTheme(_ themeID: String?) {
        setActiveTheme(themeID)
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

    func setMatchSystemAppearance(_ enabled: Bool) {
        appState.updateSettings { $0.matchSystemAppearance = enabled }
    }

    func themeLabel(_ theme: Theme) -> String {
        theme.displayName
    }

    private func refreshUIState(_ settings: WallpaperSettings) {
        selectedThemeID = settings.activeThemeID
        themes = settings.themes
        recentWallpapers = settings.wallpaperHistory
        currentWallpaper = settings.currentWallpaper
        folderPaths = settings.folderPaths
        intervalMinutes = settings.intervalMinutes
        rotationAction = settings.rotationAction
        allSpaces = settings.allSpaces
        matchSystemAppearance = settings.matchSystemAppearance
        menuTitle = settings.activeThemeID
            .flatMap { id in settings.themes.first { $0.id == id }?.displayName }
            ?? "All Folders"
    }
}

extension Notification.Name {
    static let MenuBarOpenSettings = Notification.Name("MenuBarOpenSettings")
}
