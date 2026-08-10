//
//  MenuBarViewModel.swift
//  WallpaperSelector • MVVM
//
//  Created by Zeb.
//

import Foundation
import Combine
import SwiftUI

/// `MenuBarViewModel` is the single source of UI-state for the menu-bar extra.
/// It contains only the properties that drive the UI and the actions that mutate
/// that state. Business logic (e.g., actual wallpaper selection) lives in the
/// underlying services – `RotationService`, `ThemeProvider`, etc.
///
/// The view model is created by the coordinator and injected into the
/// `MenuBarHost` (the NSViewControllerRepresentable wrapper). It is
/// `@ObservableObject` so SwiftUI-driven previews can also use it.
final class MenuBarViewModel: ObservableObject {
    // MARK: - Published UI State

    /// The title displayed in the status-item button.
    /// It changes when the active theme/folder changes.
    @Published private(set) var menuTitle: String = "Wallpaper Selector"

    /// Whether the automatic rotation timer is currently active.
    @Published private(set) var isRotationActive: Bool = false

    /// The currently selected theme identifier (or `nil` for "All Folders").
    @Published private(set) var selectedThemeID: String? = nil

    /// The list of themes for display in the menu.
    @Published private(set) var themes: [Theme] = []

    /// The list of recent wallpapers for display in the menu.
    @Published private(set) var recentWallpapers: [String] = []

    /// The currently applied wallpaper path (drives the "Recent" checkmark).
    @Published private(set) var currentWallpaper: String?

    /// The configured folder paths (drives "Preview Wallpapers" enablement).
    @Published private(set) var folderPaths: [String] = []

    /// The current rotation interval.
    @Published private(set) var intervalMinutes: RotationInterval = .off

    /// The current rotation action.
    @Published private(set) var rotationAction: RotationAction = .shuffle

    /// Whether wallpapers apply to all spaces.
    @Published private(set) var allSpaces: Bool = false

    /// Whether the wallpaper matches the system light/dark appearance.
    @Published private(set) var matchSystemAppearance: Bool = false

    // MARK: - Dependencies

    private let appState: AppState
    private let rotationService: RotationService
    private let themeProvider: ThemeProvider

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Creates a new view model.
    /// - Parameters:
    ///   - appState: The shared app-wide state.
    ///   - rotationService: Handles timed rotation.
    ///   - themeProvider: Provides computed theme information.
    init(
        appState: AppState,
        rotationService: RotationService,
        themeProvider: ThemeProvider
    ) {
        self.appState = appState
        self.rotationService = rotationService
        self.themeProvider = themeProvider

        // Initialise UI state from existing values.
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

        // Observe settings changes (for themes, appearance, etc.)
        appState.$settings
            .sink { [weak self] _ in
                self?.refreshUIState()
            }
            .store(in: &cancellables)

        // Ensure the view model reflects the latest service state.
        refreshUIState()
    }

    // MARK: - Public API (actions the UI triggers)

    /// Called by the menu item "Shuffle".
    func shuffle() {
        rotationService.tick()
    }

    /// Called by the menu item "Next Wallpaper".
    func next() {
        appState.updateSettings { $0.rotationAction = .next }
        rotationService.tick()
    }

    /// Called by the menu item "Previous Wallpaper".
    func previous() {
        appState.updateSettings { $0.rotationAction = .previous }
        rotationService.tick()
    }

    /// Called when the user selects "Open Settings". Presents the Settings view.
    func openSettings() {
        NotificationCenter.default.post(name: .MenuBarOpenSettings, object: nil)
    }

    /// Called when the user selects "Quit".
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Toggles the automatic rotation on/off (called from menu).
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

    /// Sets the active theme by ID (nil for "All Folders").
    /// This is called from both the picker window and the menu.
    func setActiveTheme(_ themeID: String?) {
        appState.setActiveTheme(themeID)
    }

    /// Select a theme by ID (called from menu).
    func selectTheme(_ themeID: String?) {
        setActiveTheme(themeID)
    }

    /// Sets the rotation interval from the menu.
    func setInterval(_ interval: RotationInterval) {
        appState.updateSettings { $0.intervalMinutes = interval }
        rotationService.updateSettings()
    }

    /// Sets the rotation action from the menu.
    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { $0.rotationAction = action }
        rotationService.updateSettings()
    }

    /// Builds the display label for a theme, matching the original app logic:
    /// trimmed name if present, else folder basename(s) or "Untitled Theme".
    func themeLabel(_ theme: Theme) -> String {
        theme.displayName
    }

    // MARK: - Private Helpers

    private func buildMenuTitle() -> String {
        // Simple heuristic: show theme name if set, otherwise "All Folders".
        if let tid = selectedThemeID,
           let theme = appState.settings.themes.first(where: { $0.id == tid }) {
            return theme.displayName
        }
        return "All Folders"
    }

    private func refreshUIState() {
        // UI state can depend on persisted values; we keep it up-to-date.
        // For example, rotation active status may have changed via external edit.
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

// MARK: - Notification Names

extension Notification.Name {
    static let MenuBarOpenSettings = Notification.Name("MenuBarOpenSettings")
}
