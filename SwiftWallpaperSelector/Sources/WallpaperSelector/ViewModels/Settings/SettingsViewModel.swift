import Foundation
import Combine
import SwiftUI
import AppKit

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

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var folderPaths: [String] = []

    @Published var themes: [Theme] = []

    @Published var intervalMinutes: RotationInterval = .off

    @Published var rotationAction: RotationAction = .shuffle

    @Published var matchSystemAppearance: Bool = false

    @Published var allSpaces: Bool = false

    @Published var shortcuts: Shortcuts = .default

    @Published var historyLimit: Int = 10

    @Published var currentWallpaper: String? = nil


    @Published var appearanceLightThemeID: String? = nil

    @Published var appearanceDarkThemeID: String? = nil

    @Published var allFoldersLightWallpaper: String? = nil

    @Published var allFoldersDarkWallpaper: String? = nil

    @Published var activeThemeID: String? = nil

    @Published var launchAtLogin: Bool = false

    @Published var themeSource: ThemeSource = .auto

    @Published var settingsFolderPath: String? = nil

    @Published private(set) var settingsErrorMessage: String? = nil

    @Published private(set) var currentThemeImages: [URL] = []


    private let appState: AppState
    private let launchAtLoginManager: LaunchAtLoginManager


    init(appState: AppState, launchAtLoginManager: LaunchAtLoginManager? = nil) {
        self.appState = appState
        self.launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        syncFromAppState()

        appState.$settings
            .sink { [weak self] _ in self?.syncFromAppState() }
            .store(in: &cancellables)

        appState.settingsManager.$lastError
            .sink { [weak self] error in
                self?.settingsErrorMessage = error?.localizedDescription
            }
            .store(in: &cancellables)

        appState.$currentThemeImages
            .sink { [weak self] images in
                self?.currentThemeImages = images
            }
            .store(in: &cancellables)
    }


    var hasFolders: Bool {
        !folderPaths.isEmpty
    }

    func save() {
        appState.updateSettings { _ in }
    }


    func addFolder(_ path: String) {
        guard !folderPaths.contains(path) else { return }
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.folderPaths.append(path)
            settings = newSettings
        }
        syncFromAppState()
    }

    func removeFolder(_ path: String) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.folderPaths.removeAll { $0 == path }
            for index in newSettings.themes.indices {
                newSettings.themes[index].folderPaths.removeAll { $0 == path }
            }
            settings = newSettings
        }
        syncFromAppState()
    }

    func replaceFolder(oldPath: String, with newPath: String) {
        appState.updateSettings { settings in
            guard let index = settings.folderPaths.firstIndex(of: oldPath) else { return }
            guard oldPath == newPath || !settings.folderPaths.contains(newPath) else { return }

            var newSettings = settings
            newSettings.folderPaths[index] = newPath
            for themeIndex in newSettings.themes.indices {
                newSettings.themes[themeIndex].folderPaths = newSettings.themes[themeIndex].folderPaths
                    .map { $0 == oldPath ? newPath : $0 }
                    .removingDuplicates()
            }
            settings = newSettings
        }
        syncFromAppState()
    }

    func editFolder(id: String, newPath: String) {
        replaceFolder(oldPath: id, with: newPath)
    }


    func addTheme(_ theme: Theme) {
        appState.updateSettings { settings in
            guard !settings.themes.contains(where: { $0.id == theme.id }) else { return }
            var newSettings = settings
            newSettings.themes.append(theme)
            settings = newSettings
        }
        syncFromAppState()
    }

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

    func replaceTheme(id: String, with replacement: Theme) {
        appState.updateSettings { settings in
            guard let index = settings.themes.firstIndex(where: { $0.id == id }) else { return }
            settings.themes[index] = Theme(
                id: id,
                name: replacement.name,
                folderPaths: replacement.folderPaths,
                lightWallpaper: replacement.lightWallpaper,
                darkWallpaper: replacement.darkWallpaper
            )
        }
        syncFromAppState()
    }

    func removeTheme(id: String) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.themes.removeAll { $0.id == id }
            if newSettings.activeThemeID == id {
                newSettings.activeThemeID = nil
            }
            if newSettings.appearanceLightThemeID == id {
                newSettings.appearanceLightThemeID = nil
            }
            if newSettings.appearanceDarkThemeID == id {
                newSettings.appearanceDarkThemeID = nil
            }
            settings = newSettings
        }
        syncFromAppState()
    }


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


    func setInterval(_ interval: RotationInterval) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.intervalMinutes = interval
            settings = newSettings
        }
        syncFromAppState()
    }

    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.rotationAction = action
            settings = newSettings
        }
        syncFromAppState()
    }

    func setHistoryLimit(_ limit: Int) {
        appState.updateSettings { settings in
            var newSettings = settings
            let clamped = max(5, min(20, limit))
            newSettings.historyLimit = clamped
            if newSettings.wallpaperHistory.count > clamped {
                newSettings.wallpaperHistory = Array(newSettings.wallpaperHistory.prefix(clamped))
            }
            settings = newSettings
        }
        syncFromAppState()
    }

    func setShortcuts(_ shortcuts: Shortcuts) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.shortcuts = shortcuts
            settings = newSettings
        }
        syncFromAppState()
    }

    func setShowMainShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        if let shortcut {
            if newShortcuts.showPreview == shortcut { newShortcuts.showPreview = nil }
            if newShortcuts.showMenu == shortcut { newShortcuts.showMenu = nil }
        }
        newShortcuts.showMain = shortcut
        setShortcuts(newShortcuts)
    }

    func setShowPreviewShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        if let shortcut {
            if newShortcuts.showMain == shortcut { newShortcuts.showMain = nil }
            if newShortcuts.showMenu == shortcut { newShortcuts.showMenu = nil }
        }
        newShortcuts.showPreview = shortcut
        setShortcuts(newShortcuts)
    }

    func setShowMenuShortcut(_ shortcut: String?) {
        var newShortcuts = shortcuts
        if let shortcut {
            if newShortcuts.showMain == shortcut { newShortcuts.showMain = nil }
            if newShortcuts.showPreview == shortcut { newShortcuts.showPreview = nil }
        }
        newShortcuts.showMenu = shortcut
        setShortcuts(newShortcuts)
    }


    func setActiveTheme(_ themeID: String?) {
        appState.updateSettings { settings in
            settings.activeThemeID = themeID.flatMap { candidate in
                settings.themes.contains(where: { $0.id == candidate }) ? candidate : nil
            }
        }
        syncFromAppState()
    }

    func setAppearanceOverrides(
        lightThemeID: String?,
        darkThemeID: String?,
        lightWallpaper: String?,
        darkWallpaper: String?
    ) {
        appState.updateSettings { settings in
            let themeIDs = Set(settings.themes.map(\.id))
            settings.appearanceLightThemeID = lightThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }
            settings.appearanceDarkThemeID = darkThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }
            settings.allFoldersLightWallpaper = lightWallpaper
            settings.allFoldersDarkWallpaper = darkWallpaper
        }
        syncFromAppState()
    }

    func setAppearanceThemeIDs(light: String?, dark: String?) {
        appState.updateSettings { settings in
            let themeIDs = Set(settings.themes.map(\.id))
            settings.appearanceLightThemeID = light.flatMap { themeIDs.contains($0) ? $0 : nil }
            settings.appearanceDarkThemeID = dark.flatMap { themeIDs.contains($0) ? $0 : nil }
        }
        syncFromAppState()
    }

    func setAppearanceWallpapers(light: String?, dark: String?, forThemeID themeID: String?) {
        appState.updateSettings { settings in
            if let themeID {
                guard let index = settings.themes.firstIndex(where: { $0.id == themeID }) else { return }
                let theme = settings.themes[index]
                settings.themes[index] = Theme(
                    id: theme.id,
                    name: theme.name,
                    folderPaths: theme.folderPaths,
                    lightWallpaper: light,
                    darkWallpaper: dark
                )
            } else {
                settings.allFoldersLightWallpaper = light
                settings.allFoldersDarkWallpaper = dark
            }
        }
        syncFromAppState()
    }

    func setAppearanceConfiguration(
        lightThemeID: String?,
        darkThemeID: String?,
        lightWallpaper: String?,
        darkWallpaper: String?,
        forThemeID themeID: String?
    ) {
        appState.updateSettings { settings in
            var newSettings = settings
            let themeIDs = Set(newSettings.themes.map(\.id))
            newSettings.appearanceLightThemeID = lightThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }
            newSettings.appearanceDarkThemeID = darkThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }

            if let themeID {
                guard let index = newSettings.themes.firstIndex(where: { $0.id == themeID }) else { return }
                let theme = newSettings.themes[index]
                newSettings.themes[index] = Theme(
                    id: theme.id,
                    name: theme.name,
                    folderPaths: theme.folderPaths,
                    lightWallpaper: lightWallpaper,
                    darkWallpaper: darkWallpaper
                )
            } else {
                newSettings.allFoldersLightWallpaper = lightWallpaper
                newSettings.allFoldersDarkWallpaper = darkWallpaper
            }
            settings = newSettings
        }
        syncFromAppState()
    }

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
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }

    func useDefaultSettingsFolder() {
        do {
            try appState.settingsManager.useDefaultSettingsLocation()
            settingsFolderPath = nil
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!launchAtLogin)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if case .failure(let error) = launchAtLoginManager.setEnabled(enabled) {
            settingsErrorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        launchAtLogin = launchAtLoginManager.isEnabled
    }

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

    private var currentThemeSource: ThemeSource {
        guard let name = NSApplication.shared.appearance?.name else { return .auto }
        switch name {
        case .aqua, .vibrantLight:
            return .light
        default:
            return .dark
        }
    }


    private var cancellables = Set<AnyCancellable>()

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

        appearanceLightThemeID = appState.settings.appearanceLightThemeID
        appearanceDarkThemeID = appState.settings.appearanceDarkThemeID
        allFoldersLightWallpaper = appState.settings.allFoldersLightWallpaper
        allFoldersDarkWallpaper = appState.settings.allFoldersDarkWallpaper
        activeThemeID = appState.settings.activeThemeID

        launchAtLogin = launchAtLoginManager.isEnabled

        themeSource = currentThemeSource
        settingsFolderPath = appState.settingsManager.isUsingDefaultSettingsDirectory
            ? nil
            : appState.settingsManager.settingsDirectory.path
        currentThemeImages = appState.currentThemeImages
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
