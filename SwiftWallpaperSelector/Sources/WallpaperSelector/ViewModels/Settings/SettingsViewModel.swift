import Foundation
import Combine
import SwiftUI
import AppKit

/// Controls how the app forces the system appearance (nativeTheme.themeSource equivalent).
enum ThemeSource: String, CaseIterable {
    case auto
    case light
    case dark

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// ViewModel that wraps `AppState` to expose all settings fields as
/// `@Published` properties and provides mutation methods that delegate
/// to `AppState.updateSettings`.
///
/// The view layer binds directly to this object; it never touches
/// `SettingsManager` or `WallpaperSettings` directly.
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Settings Fields

    /// The list of folder paths participating in rotation / theme selection.
    @Published var folderPaths: [String] = []

    /// The user-defined themes (named subsets of folders).
    @Published var themes: [Theme] = []

    /// The current rotation interval.
    @Published var intervalMinutes: RotationInterval = .off

    /// The action performed on each rotation tick.
    @Published var rotationAction: RotationAction = .shuffle

    /// Whether the wallpaper should follow the system appearance (light/dark).
    @Published var matchSystemAppearance: Bool = false

    /// Whether the rotation applies across all Spaces (virtual desktops).
    @Published var allSpaces: Bool = false

    /// User-configurable keyboard shortcuts.
    @Published var shortcuts: Shortcuts = .default

    /// Maximum number of entries kept in the wallpaper history.
    @Published var historyLimit: Int = 10

    /// The absolute path of the currently applied wallpaper.
    @Published var currentWallpaper: String? = nil

    // MARK: - Appearance-themed Properties

    /// Theme ID for light appearance (appearance-specific theme override)
    @Published var appearanceLightThemeID: String? = nil

    /// Theme ID for dark appearance (appearance-specific theme override)
    @Published var appearanceDarkThemeID: String? = nil

    /// Light wallpaper path (appearance-specific wallpaper override)
    @Published var allFoldersLightWallpaper: String? = nil

    /// Dark wallpaper path (appearance-specific wallpaper override)
    @Published var allFoldersDarkWallpaper: String? = nil

    /// Active theme ID (nil means "All Folders")
    @Published var activeThemeID: String? = nil

    /// Whether the app is set to launch at login.
    @Published var launchAtLogin: Bool = false

    /// Forced system appearance (theme source). Not persisted; read from `NSApp.appearance`.
    @Published var themeSource: ThemeSource = .auto

    /// `nil` means Application Support; any value is a user-selected folder.
    @Published var settingsFolderPath: String? = nil

    // MARK: - Dependencies

    /// The shared coordinator object that owns the persisted settings.
    private let appState: AppState
    private let themeProvider: ThemeProvider
    private let launchAtLoginManager: LaunchAtLoginManager

    // MARK: - Initialization

    /// Creates a new `SettingsViewModel` backed by the given `AppState`.
    /// - Parameters:
    ///   - appState: The shared app state coordinator.
    ///   - launchAtLoginManager: Manager for launch-at-login functionality.
    init(appState: AppState, launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()) {
        self.appState = appState
        self.themeProvider = ThemeProvider(settingsManager: appState.settingsManager)
        self.launchAtLoginManager = launchAtLoginManager
        syncFromAppState()

        // Keep published properties in lockstep with AppState changes.
        appState.$settings
            .sink { [weak self] _ in self?.syncFromAppState() }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties for UI

    var hasFolders: Bool {
        !folderPaths.isEmpty
    }

    /// The list of image URLs from the current effective folders (used for appearance overrides).
    var currentThemeImages: [URL] {
        ImageDiscoveryService.collectImageURLs(from: themeProvider.effectiveFolders())
    }

    // MARK: - Save

    /// Explicitly persists the current settings state.
    /// This is a no-op at the model layer since `SettingsManager`
    /// auto-saves on every mutation, but it provides a clear
    /// `viewModel.save()` entry point for the Save button.
    func save() {
        appState.updateSettings { _ in }
    }

    // MARK: - Folder Management

    /// Adds a folder path to the settings.  Duplicate paths are ignored.
    func addFolder(_ path: String) {
        guard !folderPaths.contains(path) else { return }
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.folderPaths.append(path)
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Removes a folder path from the settings.
    func removeFolder(_ path: String) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.folderPaths.removeAll { $0 == path }
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Edits an existing folder path in the settings.
    func editFolder(id: String, newPath: String) {
        appState.updateSettings { settings in
            if let index = settings.folderPaths.firstIndex(of: id) {
                var newSettings = settings
                newSettings.folderPaths[index] = newPath
                settings = newSettings
            }
        }
        syncFromAppState()
    }

    // MARK: - Theme Management

    /// Adds a new theme.
    func addTheme(_ theme: Theme) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.themes.append(theme)
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Edits an existing theme identified by `id`.  If no matching theme
    /// exists the update is a no-op.
    func editTheme(id: String, name: String? = nil, folderPaths: [String]? = nil,
                   lightWallpaper: String? = nil, darkWallpaper: String? = nil) {
        appState.updateSettings { settings in
            guard let index = settings.themes.firstIndex(where: { $0.id == id }) else { return }
            if let name { settings.themes[index].name = name }
            if let folderPaths { settings.themes[index].folderPaths = folderPaths }
            if let lightWallpaper { settings.themes[index].lightWallpaper = lightWallpaper }
            if let darkWallpaper { settings.themes[index].darkWallpaper = darkWallpaper }
        }
        syncFromAppState()
    }

    /// Removes a theme by its identifier.
    func removeTheme(id: String) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.themes.removeAll { $0.id == id }
            settings = newSettings
        }
        syncFromAppState()
    }

    // MARK: - Option Toggles

    /// Sets appearance matching. Kept separate from the view's local published
    /// value so every SwiftUI control writes through to persisted settings.
    func setMatchSystemAppearance(_ enabled: Bool) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.matchSystemAppearance = enabled
            settings = newSettings
        }
        syncFromAppState()
    }

    func toggleMatchSystemAppearance() {
        setMatchSystemAppearance(!matchSystemAppearance)
    }

    /// Sets All Spaces preference and persists it immediately.
    func setAllSpaces(_ enabled: Bool) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.allSpaces = enabled
            settings = newSettings
        }
        syncFromAppState()
    }

    func toggleAllSpaces() {
        setAllSpaces(!allSpaces)
    }

    // MARK: - Rotation Settings

    /// Updates the rotation interval.
    func setInterval(_ interval: RotationInterval) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.intervalMinutes = interval
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Updates the rotation action.
    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.rotationAction = action
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Updates the history limit and trims the existing history if it exceeds the new limit.
    func setHistoryLimit(_ limit: Int) {
        appState.updateSettings { settings in
            var newSettings = settings
            // Clamp to valid values (5, 10, or 20)
            let clamped = max(5, min(20, limit))
            newSettings.historyLimit = clamped
            if newSettings.wallpaperHistory.count > clamped {
                // History is newest-first. Keep newest entries, not oldest.
                newSettings.wallpaperHistory = Array(newSettings.wallpaperHistory.prefix(clamped))
            }
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Updates the keyboard shortcuts.
    func setShortcuts(_ shortcuts: Shortcuts) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.shortcuts = shortcuts
            settings = newSettings
        }
        syncFromAppState()
    }

    /// Sets the "Show Main Window" global shortcut.
    func setShowMainShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        newShortcuts.showMain = shortcut
        setShortcuts(newShortcuts)
    }

    /// Sets the "Show Preview" global shortcut.
    func setShowPreviewShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        newShortcuts.showPreview = shortcut
        setShortcuts(newShortcuts)
    }

    /// Sets the "Open Menu Bar Menu" global shortcut.
    func setShowMenuShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        newShortcuts.showMenu = shortcut
        setShortcuts(newShortcuts)
    }

    // MARK: - Appearance Settings

    /// Sets the active theme (nil means "All Folders")
    func setActiveTheme(_ themeID: String?) {
        appState.updateSettings { settings in
            settings.activeThemeID = themeID
        }
        syncFromAppState()
    }

    /// Persists appearance-specific theme and wallpaper pins together. `nil`
    /// intentionally clears a pin, so callers do not need sentinel values.
    func setAppearanceOverrides(
        lightThemeID: String?,
        darkThemeID: String?,
        lightWallpaper: String?,
        darkWallpaper: String?
    ) {
        appState.updateSettings { settings in
            settings.appearanceLightThemeID = lightThemeID
            settings.appearanceDarkThemeID = darkThemeID
            settings.allFoldersLightWallpaper = lightWallpaper
            settings.allFoldersDarkWallpaper = darkWallpaper
        }
        syncFromAppState()
    }

    /// Persist current Appearance controls after any one binding changes.
    func persistAppearanceOverrides() {
        setAppearanceOverrides(
            lightThemeID: appearanceLightThemeID,
            darkThemeID: appearanceDarkThemeID,
            lightWallpaper: allFoldersLightWallpaper,
            darkWallpaper: allFoldersDarkWallpaper
        )
    }

    func chooseSettingsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try appState.settingsManager.relocateSettings(to: url)
            settingsFolderPath = url.path
        } catch {
            print("[SettingsViewModel] Failed to move settings: \(error)")
        }
    }

    func useDefaultSettingsFolder() {
        do {
            try appState.settingsManager.useDefaultSettingsLocation()
            settingsFolderPath = nil
        } catch {
            print("[SettingsViewModel] Failed to restore default settings location: \(error)")
        }
    }

    /// Toggles launch-at-login.
    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchAtLogin)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginManager.isEnabled = enabled
        launchAtLogin = launchAtLoginManager.isEnabled
    }

    /// Forces the app's system appearance (nativeTheme.setThemeSource equivalent).
    func setThemeSource(_ source: ThemeSource) {
        guard source != themeSource else { return }
        themeSource = source
        switch source {
        case .auto:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Reads the current forced theme source from the app appearance.
    private var currentThemeSource: ThemeSource {
        guard let name = NSApplication.shared.appearance?.name else { return .auto }
        switch name {
        case .aqua, .vibrantLight:
            return .light
        default:
            return .dark
        }
    }

    // MARK: - Private Helpers

    private var cancellables = Set<AnyCancellable>()

    /// Copies the current settings values from `AppState` into the
    /// published properties so the UI stays in sync.
    private func syncFromAppState() {
        folderPaths = appState.settings.folderPaths
        themes = appState.settings.themes
        intervalMinutes = appState.settings.intervalMinutes
        rotationAction = appState.settings.rotationAction
        matchSystemAppearance = appState.settings.matchSystemAppearance
        allSpaces = appState.settings.allSpaces
        shortcuts = appState.settings.shortcuts
        historyLimit = appState.settings.historyLimit
        currentWallpaper = appState.settings.currentWallpaper

        // Appearance theme-specific settings
        appearanceLightThemeID = appState.settings.appearanceLightThemeID
        appearanceDarkThemeID = appState.settings.appearanceDarkThemeID
        allFoldersLightWallpaper = appState.settings.allFoldersLightWallpaper
        allFoldersDarkWallpaper = appState.settings.allFoldersDarkWallpaper
        activeThemeID = appState.settings.activeThemeID

        // Launch at login status
        launchAtLogin = launchAtLoginManager.isEnabled

        // Forced appearance (from NSApp.appearance, not persisted)
        themeSource = currentThemeSource
        settingsFolderPath = appState.settingsManager.settingsDirectory.path == SettingsManager.defaultSettingsDirectory.path
            ? nil
            : appState.settingsManager.settingsDirectory.path
    }
}
