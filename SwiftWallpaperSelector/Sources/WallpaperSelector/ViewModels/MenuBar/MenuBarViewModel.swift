
import Foundation
import Combine
import SwiftUI

final class MenuBarViewModel: ObservableObject {

    @Published private(set) var menuTitle: String = "Wallpaper Selector"

    @Published private(set) var isRotationActive: Bool = false

    @Published private(set) var selectedThemeID: String? = nil

    @Published private(set) var themes: [Theme] = []

    @Published private(set) var recentWallpapers: [String] = []

    @Published private(set) var currentWallpaper: String?

    @Published private(set) var folderPaths: [String] = []

    @Published private(set) var intervalMinutes: RotationInterval = .off

    @Published private(set) var rotationAction: RotationAction = .shuffle

    @Published private(set) var allSpaces: Bool = false

    @Published private(set) var matchSystemAppearance: Bool = false


    private let appState: AppState
    private let rotationService: RotationService
    private let themeProvider: ThemeProvider

    private var cancellables = Set<AnyCancellable>()


    init(
        appState: AppState,
        rotationService: RotationService,
        themeProvider: ThemeProvider
    ) {
        self.appState = appState
        self.rotationService = rotationService
        self.themeProvider = themeProvider

        _menuTitle = Published(initialValue: buildMenuTitle())
        _isRotationActive = Published(initialValue: appState.isRotationRunning)
        _selectedThemeID = Published(initialValue: appState.settings.activeThemeID)
        _themes = Published(initialValue: appState.settings.themes)
        _recentWallpapers = Published(initialValue: appState.settings.wallpaperHistory)
        _currentWallpaper = Published(initialValue: appState.settings.currentWallpaper)
        _folderPaths = Published(initialValue: appState.settings.folderPaths)
        _intervalMinutes = Published(initialValue: appState.settings.intervalMinutes)
        _rotationAction = Published(initialValue: appState.settings.rotationAction)
        _allSpaces = Published(initialValue: appState.settings.allSpaces)
        _matchSystemAppearance = Published(initialValue: appState.settings.matchSystemAppearance)

        appState.$settings
            .sink { [weak self] _ in
                self?.refreshUIState()
            }
            .store(in: &cancellables)

        refreshUIState()
    }


    func shuffle() {
        rotationService.tick()
    }

    func next() {
        appState.updateSettings { $0.rotationAction = .next }
        rotationService.tick()
    }

    func previous() {
        appState.updateSettings { $0.rotationAction = .previous }
        rotationService.tick()
    }

    func openSettings() {
        NotificationCenter.default.post(name: .MenuBarOpenSettings, object: nil)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func toggleRotation() {
        appState.updateSettings { settings in
            if settings.intervalMinutes == .off {
                settings.intervalMinutes = .hour1
            } else {
                settings.intervalMinutes = .off
            }
        }
        rotationService.updateSettings()
    }

    func setActiveTheme(_ themeID: String?) {
        appState.setActiveTheme(themeID)
    }

    func selectTheme(_ themeID: String?) {
        setActiveTheme(themeID)
    }

    func setInterval(_ interval: RotationInterval) {
        appState.updateSettings { $0.intervalMinutes = interval }
        rotationService.updateSettings()
    }

    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { $0.rotationAction = action }
        rotationService.updateSettings()
    }

    func themeLabel(_ theme: Theme) -> String {
        theme.displayName
    }


    private func buildMenuTitle() -> String {
        if let tid = selectedThemeID,
           let theme = appState.settings.themes.first(where: { $0.id == tid }) {
            return theme.displayName
        }
        return "All Folders"
    }

    private func refreshUIState() {
        isRotationActive = appState.isRotationRunning
        selectedThemeID = appState.settings.activeThemeID
        themes = appState.settings.themes
        recentWallpapers = appState.settings.wallpaperHistory
        currentWallpaper = appState.settings.currentWallpaper
        folderPaths = appState.settings.folderPaths
        intervalMinutes = appState.settings.intervalMinutes
        rotationAction = appState.settings.rotationAction
        allSpaces = appState.settings.allSpaces
        matchSystemAppearance = appState.settings.matchSystemAppearance
        menuTitle = buildMenuTitle()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }
}


extension Notification.Name {
    static let MenuBarOpenSettings = Notification.Name("MenuBarOpenSettings")
}
