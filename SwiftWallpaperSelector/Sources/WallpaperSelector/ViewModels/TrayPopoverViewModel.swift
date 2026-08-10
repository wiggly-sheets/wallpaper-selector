import Foundation
import Combine
import SwiftUI
import AppKit

/// ViewModel that backs the compact tray popover.
/// Exposes wallpaper grid, theme selection, and auto-rotate controls,
/// all synced from `SettingsManager`. Mutations route through
/// `settingsManager.update` so state stays consistent app-wide.
@MainActor
final class TrayPopoverViewModel: ObservableObject {
    // MARK: - Published state

    /// The list of effective folders (used for the header title).
    @Published private(set) var folderPaths: [String] = []

    /// The image URLs discoverable in the current effective folders.
    @Published private(set) var images: [URL] = []

    /// The user-defined themes.
    @Published private(set) var themes: [Theme] = []

    /// The active theme ID (nil means "All Folders").
    @Published private(set) var activeThemeID: String?

    /// The current rotation interval.
    @Published private(set) var intervalMinutes: RotationInterval = .off

    /// The action performed on each rotation tick.
    @Published private(set) var rotationAction: RotationAction = .shuffle

    /// Whether rotation applies across all Spaces.
    @Published private(set) var allSpaces: Bool = false

    /// The absolute path of the currently applied wallpaper.
    @Published private(set) var currentWallpaperPath: String?

    /// Whether rotation is currently active.
    @Published private(set) var isRotationRunning: Bool = false

    // MARK: - Dependencies

    private let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private let rotationService: RotationService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider,
        rotationService: RotationService
    ) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.themeProvider = themeProvider
        self.rotationService = rotationService

        Task { @MainActor in
            await syncFromSettings()
        }

        settingsManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
            Task { @MainActor in
                await self?.syncFromSettings()
            }
            }
            .store(in: &cancellables)
    }

    /// Called when the "Open" button is tapped — sets by the window controller
    /// to hide the popover and bring up the main window.
    var onShowMainWindow: (() -> Void)?

    // MARK: - Computed properties for UI

    /// Whether any wallpaper action is in flight (synchronous today, so false).
    var isBusy: Bool { false }

    /// The header title derived from the effective folders.
    var foldersTitle: String {
        if folderPaths.isEmpty {
            return "Wallpaper Selector"
        } else if folderPaths.count == 1 {
            return (folderPaths[0] as NSString).lastPathComponent
        } else {
            return "\(folderPaths.count) folders"
        }
    }

    // MARK: - State sync

    func syncFromSettings() async {
        folderPaths = themeProvider.effectiveFolders()
        themes = settingsManager.settings.themes
        activeThemeID = settingsManager.settings.activeThemeID
        intervalMinutes = settingsManager.settings.intervalMinutes
        rotationAction = settingsManager.settings.rotationAction
        allSpaces = settingsManager.settings.allSpaces
        currentWallpaperPath = settingsManager.settings.currentWallpaper
        images = ImageDiscoveryService.collectImageURLs(from: folderPaths)
        isRotationRunning = settingsManager.settings.intervalMinutes != .off && !settingsManager.settings.matchSystemAppearance
    }

    // MARK: - Wallpaper actions

    /// Writes the given wallpaper to disk and records it in history.
    func selectWallpaper(_ url: URL) {
        do {
            try wallpaperProvider.setWallpaper(url, forAllScreens: settingsManager.settings.allSpaces)
            settingsManager.update { s in
                s.currentWallpaper = url.path
                s.recordWallpaperInHistory(url.path)
            }
        } catch {
            print("Failed to set wallpaper: \(error)")
        }
    }

    /// Triggers a shuffle rotation.
    func shuffle() {
        rotationService.tick()
    }

    /// Applies the next wallpaper in sequence.
    func next() {
        settingsManager.update { $0.rotationAction = .next }
        rotationService.tick()
    }

    /// Applies the previous wallpaper in sequence.
    func previous() {
        settingsManager.update { $0.rotationAction = .previous }
        rotationService.tick()
    }

    // MARK: - Theme actions

    /// Sets the active theme (nil for "All Folders") and applies a wallpaper
    /// from the new scope when appearance isn't being matched.
    func selectTheme(_ themeID: String?) {
        settingsManager.update { $0.activeThemeID = themeID }
        if !settingsManager.settings.matchSystemAppearance {
            rotationService.tick()
        }
    }

    /// Moves to the previous theme in the list, cycling.
    func themePrevious() {
        cycleTheme(direction: -1)
    }

    /// Moves to the next theme in the list, cycling.
    func themeNext() {
        cycleTheme(direction: 1)
    }

    /// Picks a random theme.
    func themeShuffle() {
        guard let theme = themes.randomElement() else { return }
        selectTheme(theme.id)
    }

    private func cycleTheme(direction: Int) {
        guard !themes.isEmpty else { return }
        let ids = themes.map(\.id)
        let currentIndex = activeThemeID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + direction + ids.count) % ids.count
        selectTheme(ids[nextIndex])
    }

    // MARK: - Auto-rotate settings

    /// Updates the rotation interval and restarts the rotation timer.
    func setInterval(_ interval: RotationInterval) {
        settingsManager.update { $0.intervalMinutes = interval }
        rotationService.updateSettings()
    }

    /// Updates the rotation action.
    func setRotationAction(_ action: RotationAction) {
        settingsManager.update { $0.rotationAction = action }
    }

    /// Updates whether rotation applies to all Spaces.
    func setAllSpaces(_ enabled: Bool) {
        settingsManager.update { $0.allSpaces = enabled }
    }

    // MARK: - Window actions

    /// Opens the Settings window.
    func openSettings() {
        // Settings is hosted by MenuBarHostingViewController. The old SwiftUI
        // Settings scene selector has no receiver in the native menu-bar app.
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }

    /// Requests the host to hide the popover and show the main window.
    func showMainWindow() {
        onShowMainWindow?()
    }
}
