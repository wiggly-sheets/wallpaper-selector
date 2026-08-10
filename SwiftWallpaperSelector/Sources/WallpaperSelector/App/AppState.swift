//
//  AppState.swift
//  WallpaperSelector
//
//  Created by Zeb on <#date #>.
//  Description: The top‑level coordinator object that owns the persistence layer
//               (SettingsManager) and exposes derived, UI‑ready state.
//
//               • Holds a weak reference to SettingsManager (the single source of
//                 truth for persisted settings). <br>
//               • Publishes derived/computed values that the UI consumes
//                 (e.g., effective folders, selected wallpapers, rotation status). <br>
//               • Provides an update closure so views can mutate settings in a
//                 controlled way.
//
//               All view models and services obtain the shared AppState instance
//               via the Coordinator (see `AppCoordinator`).  This eliminates direct
//               SettingsManager references in view code and enables full
//               unit‑testability.
//

import Foundation
import Combine
import AppKit

final class AppState: ObservableObject {
    let settingsManager: SettingsManager
    private let wallpaperProvider: WallpaperSetting
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var settings: WallpaperSettings = .init()
    @Published var effectiveFolders: [String] = []
    @Published var currentWallpaperURL: URL? = nil
    @Published var isRotationRunning: Bool = false

    init(settingsManager: SettingsManager,
         themeProvider: ThemeProvider,
         wallpaperProvider: WallpaperSetting) {
        self.settingsManager = settingsManager
        self.wallpaperProvider = wallpaperProvider
        self.settings = settingsManager.settings

        refreshDerivedState()
        settingsManager.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.settings = settings
                self?.refreshDerivedState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Appearance

    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        let provider = ThemeProvider(settingsManager: settingsManager)
        return provider.effectiveAppearanceWallpapers(isDarkAppearance: isDarkAppearance)
    }

    // MARK: - Settings Mutation

    func updateSettings(_ mutation: (inout WallpaperSettings) -> Void) {
        settingsManager.update(mutation)
        // Local mutations need synchronous read-after-write semantics for
        // command handlers and SwiftUI bindings. The publisher below remains
        // responsible for edits arriving from the filesystem watcher.
        settings = settingsManager.settings
        refreshDerivedState()
    }

    func reloadDerivedState() {
        refreshDerivedState()
    }

    private func refreshDerivedState() {
        let provider = ThemeProvider(settingsManager: settingsManager)
        effectiveFolders = provider.effectiveFolders()
        currentWallpaperURL = settingsManager.settings.currentWallpaper.map { URL(fileURLWithPath: $0) }
        isRotationRunning = settings.intervalMinutes != .off && !settings.matchSystemAppearance
    }

    // MARK: - Wallpaper Actions

    /// Apply a specific wallpaper path
    func setWallpaper(_ path: String) {
        guard path.hasPrefix("/") else { return }
        setWallpaper(URL(fileURLWithPath: path))
    }

    func setWallpaper(_ url: URL) {
        do {
            // Display coverage is independent from macOS's virtual-Space
            // preference. The original app always updates every display;
            // `allSpaces` only controls System Settings automation.
            try wallpaperProvider.setWallpaper(url, forAllScreens: true)
            updateSettings { settings in
                settings.currentWallpaper = url.path
                settings.recordWallpaperInHistory(url.path)
            }
        } catch {
            print("[AppState] Failed to set wallpaper: \(error)")
        }
    }

    /// Shuffle wallpaper from effective folders
    func shuffleWallpaper() {
        let folders = effectiveFolders
        guard !folders.isEmpty else { return }
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return }

        let currentPath = settings.currentWallpaper
        let history = settings.wallpaperHistory

        // Filter out images that are in the history (unless all are in history)
        let candidates = images.filter { url in
            !history.contains(url.path) && url.path != currentPath
        }
        let pool = candidates.isEmpty ? images : candidates
        if let selected = pool.randomElement() {
            setWallpaper(selected)
        }
    }

    /// Apply next wallpaper in sequence
    func applyNextWallpaper() {
        applySequentialWallpaper(direction: 1)
    }

    /// Apply previous wallpaper in sequence
    func applyPreviousWallpaper() {
        applySequentialWallpaper(direction: -1)
    }

    private func applySequentialWallpaper(direction: Int) {
        let folders = effectiveFolders
        guard !folders.isEmpty else { return }
        let images = ImageDiscoveryService.collectImageURLs(from: folders)
        guard !images.isEmpty else { return }

        let currentPath = settings.currentWallpaper

        guard let currentPath = currentPath,
              let currentIndex = images.firstIndex(where: { $0.path == currentPath }) else {
            // No current wallpaper or not in list — return first or last
            let selected = direction > 0 ? images.first! : images.last!
            setWallpaper(selected)
            return
        }

        let nextIndex = currentIndex + direction
        if nextIndex >= images.count {
            setWallpaper(images.first!)
        } else if nextIndex < 0 {
            setWallpaper(images.last!)
        } else {
            setWallpaper(images[nextIndex])
        }
    }

    /// Apply appearance-based wallpaper if needed (called when matchSystemAppearance changes or appearance changes)
    func applyAppearanceWallpaperIfNeeded() {
        guard !settings.matchSystemAppearance else {
            // When matchSystemAppearance is ON, we let the appearance monitor handle it
            return
        }
        // When matchSystemAppearance is OFF, we just apply the current theme's wallpaper
        // (this is a no-op if we're already showing the correct wallpaper)
        // But we should ensure we're showing a wallpaper from the current effective scope
        if let current = settings.currentWallpaper,
           effectiveFolders.contains(URL(fileURLWithPath: current).deletingLastPathComponent().path) {
            // Current wallpaper is already in effective folders, do nothing
            return
        }
        // Otherwise, shuffle to get a wallpaper from current scope
        shuffleWallpaper()
    }

    // MARK: - Theme Management

    /// Set active theme by ID (nil for "All Folders")
    func setActiveTheme(_ themeID: String?) {
        updateSettings { settings in
            settings.activeThemeID = themeID
        }
        // When theme changes, we may need to apply appearance wallpaper if matchSystemAppearance is ON
        if settings.matchSystemAppearance {
            // AppearanceMonitor will handle this via its observer
        } else {
            // When not matching appearance, just ensure we have a wallpaper from the new theme
            shuffleWallpaper()
        }
    }

    // MARK: - Computed Properties for UI

    var hasFolders: Bool {
        !effectiveFolders.isEmpty
    }

    var isRotationBusy: Bool {
        // We could add a flag if needed, but for now just return false
        false
    }

    var currentThemeImages: [URL] {
        ImageDiscoveryService.collectImageURLs(from: effectiveFolders)
    }

    func isCurrentWallpaper(_ path: String) -> Bool {
        settings.currentWallpaper == path
    }

    func isCurrentWallpaper(_ url: URL) -> Bool {
        settings.currentWallpaper == url.path
    }

    // MARK: - Settings Update Helper

    /// Call when settings have changed to update derived state and restart rotation if needed
    func updateRotationSettings() {
        reloadDerivedState()
        // RotationService is observing settings via its own updateSettings call
        // We just need to ensure derived state is refreshed
    }
}
