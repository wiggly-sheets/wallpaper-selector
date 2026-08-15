import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class TrayPopoverViewModel: ObservableObject {

    @Published private(set) var folderPaths: [String] = []

    @Published private(set) var images: [URL] = []

    @Published private(set) var themes: [Theme] = []

    @Published private(set) var activeThemeID: String?

    @Published private(set) var intervalMinutes: RotationInterval = .off

    @Published private(set) var rotationAction: RotationAction = .shuffle

    @Published private(set) var allSpaces: Bool = false

    @Published private(set) var currentWallpaperPath: String?

    @Published private(set) var isRotationRunning: Bool = false


    private let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private let themeProvider: ThemeProvider
    private let rotationService: RotationService
    private var cancellables = Set<AnyCancellable>()


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

    var onShowMainWindow: (() -> Void)?


    var isBusy: Bool { false }

    var foldersTitle: String {
        if folderPaths.isEmpty {
            return "Wallpaper Selector"
        } else if folderPaths.count == 1 {
            return (folderPaths[0] as NSString).lastPathComponent
        } else {
            return "\(folderPaths.count) folders"
        }
    }


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

    func shuffle() {
        rotationService.tick()
    }

    func next() {
        settingsManager.update { $0.rotationAction = .next }
        rotationService.tick()
    }

    func previous() {
        settingsManager.update { $0.rotationAction = .previous }
        rotationService.tick()
    }


    func selectTheme(_ themeID: String?) {
        settingsManager.update { $0.activeThemeID = themeID }
        if !settingsManager.settings.matchSystemAppearance {
            rotationService.tick()
        }
    }

    func themePrevious() {
        cycleTheme(direction: -1)
    }

    func themeNext() {
        cycleTheme(direction: 1)
    }

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


    func setInterval(_ interval: RotationInterval) {
        settingsManager.update { $0.intervalMinutes = interval }
        rotationService.updateSettings()
    }

    func setRotationAction(_ action: RotationAction) {
        settingsManager.update { $0.rotationAction = action }
    }

    func setAllSpaces(_ enabled: Bool) {
        settingsManager.update { $0.allSpaces = enabled }
    }


    func openSettings() {
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
    }

    func showMainWindow() {
        onShowMainWindow?()
    }
}
