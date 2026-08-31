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

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        appState.$settings
            .sink { [weak self] _ in self?.refreshUIState() }
            .store(in: &cancellables)
        appState.$isRotationRunning
            .sink { [weak self] isRunning in self?.isRotationActive = isRunning }
            .store(in: &cancellables)

        refreshUIState()
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

    private func refreshUIState() {
        let settings = appState.settings
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
