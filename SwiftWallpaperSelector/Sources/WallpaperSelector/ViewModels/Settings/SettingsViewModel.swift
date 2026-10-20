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

    /// Kept apart from `settingsErrorMessage`: a successful save clears the
    /// settings error, which would wipe the shortcut failure right away.
    @Published private(set) var hotKeyErrorMessage: String? = nil

    /// The last wallpaper failure. The menu bar shows it too, and the README
    /// promises it in the Settings window.
    @Published private(set) var wallpaperErrorMessage: String? = nil

    @Published private(set) var currentThemeImages: [URL] = []

    /// The images of every configured folder. The pins of all folders are
    /// chosen from this list, not from the images of the active theme.
    @Published private(set) var allFolderImages: [URL] = []


    private let appState: AppState
    private let launchAtLoginManager: LaunchAtLoginManager


    init(appState: AppState, launchAtLoginManager: LaunchAtLoginManager? = nil) {
        self.appState = appState
        self.launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        syncFromAppState(appState.settings)

        appState.settingsPublisher
            .sink { [weak self] settings in self?.syncFromAppState(settings) }
            .store(in: &cancellables)

        appState.settingsManager.$lastError
            .sink { [weak self] error in
                self?.settingsErrorMessage = error?.localizedDescription
            }
            .store(in: &cancellables)

        appState.$lastWallpaperError
            .sink { [weak self] error in
                self?.wallpaperErrorMessage = error
            }
            .store(in: &cancellables)

        appState.$currentThemeImages
            .sink { [weak self] images in
                self?.currentThemeImages = images
            }
            .store(in: &cancellables)

        appState.$allFolderImages
            .sink { [weak self] images in
                self?.allFolderImages = images
            }
            .store(in: &cancellables)
    }


    var hasFolders: Bool {
        !folderPaths.isEmpty
    }

    /// The rotation cannot run while the appearance is matched, so the
    /// interval and the action of the rotation would do nothing. The name
    /// states the effect, so a view binds it without negating it.
    var isRotationControlDisabled: Bool {
        matchSystemAppearance
    }

    /// The global light pin is only read while no theme is set for the light
    /// appearance: a theme owns the pin of its appearance, so the app reads
    /// the pin of that theme instead. The name states the effect, so a view
    /// binds it without negating it.
    var isGlobalLightPinDisabled: Bool {
        hasAppearanceTheme(appearanceLightThemeID)
    }

    /// The same rule for the dark appearance.
    var isGlobalDarkPinDisabled: Bool {
        hasAppearanceTheme(appearanceDarkThemeID)
    }

    /// A theme that is set for an appearance owns the wallpaper of that
    /// appearance, so the pin of all folders is not read.
    private func hasAppearanceTheme(_ themeID: String?) -> Bool {
        guard let themeID else { return false }
        return themes.contains { $0.id == themeID }
    }

    func save() {
        appState.updateSettings { _ in }
    }

    /// Shows why a keyboard shortcut could not be registered.
    func setHotKeyErrorMessage(_ message: String?) {
        hotKeyErrorMessage = message
    }


    func addFolder(_ path: String) {
        // The app reads the folders with an absolute path, so the path the
        // user typed is resolved the same way the settings file is.
        guard let absolutePath = WallpaperSettings.absoluteFolderPath(path) else { return }
        guard !folderPaths.contains(absolutePath) else { return }
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.folderPaths.append(absolutePath)
            settings = newSettings
        }
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
    }

    func replaceFolder(oldPath: String, with newPath: String) {
        // The path the user typed is stored absolute, so the app and the
        // settings file name the same folder.
        guard let absolutePath = WallpaperSettings.absoluteFolderPath(newPath) else { return }
        appState.updateSettings { settings in
            guard let index = settings.folderPaths.firstIndex(of: oldPath) else { return }
            guard oldPath == absolutePath || !settings.folderPaths.contains(absolutePath) else { return }

            var newSettings = settings
            newSettings.folderPaths[index] = absolutePath
            for themeIndex in newSettings.themes.indices {
                newSettings.themes[themeIndex].folderPaths = newSettings.themes[themeIndex].folderPaths
                    .map { $0 == oldPath ? absolutePath : $0 }
                    .removingDuplicates()
                // A pin only moves when the theme still covers the renamed
                // folder. A theme that is scoped to another folder keeps its
                // pins, so a pin cannot leave the scope of its theme.
                let coversRenamedFolder = newSettings.themes[themeIndex].folderPaths.contains(absolutePath)
                newSettings.themes[themeIndex].lightWallpaper = coversRenamedFolder
                    ? remappedPath(newSettings.themes[themeIndex].lightWallpaper, from: oldPath, to: absolutePath)
                    : newSettings.themes[themeIndex].lightWallpaper
                newSettings.themes[themeIndex].darkWallpaper = coversRenamedFolder
                    ? remappedPath(newSettings.themes[themeIndex].darkWallpaper, from: oldPath, to: absolutePath)
                    : newSettings.themes[themeIndex].darkWallpaper
            }
            // The pins of all folders, the current wallpaper and the history
            // point at files in the renamed folder too.
            newSettings.allFoldersLightWallpaper = remappedPath(
                newSettings.allFoldersLightWallpaper,
                from: oldPath,
                to: absolutePath
            )
            newSettings.allFoldersDarkWallpaper = remappedPath(
                newSettings.allFoldersDarkWallpaper,
                from: oldPath,
                to: absolutePath
            )
            newSettings.currentWallpaper = remappedPath(
                newSettings.currentWallpaper,
                from: oldPath,
                to: absolutePath
            )
            newSettings.wallpaperHistory = newSettings.wallpaperHistory.map { path in
                remappedPath(path, from: oldPath, to: absolutePath) ?? path
            }
            settings = newSettings
        }
        syncFromAppState(appState.settings)
    }

    /// Moves a wallpaper that lives under the renamed folder to the new
    /// folder. A wallpaper outside the folder keeps its path.
    private func remappedPath(_ path: String?, from oldPath: String, to newPath: String) -> String? {
        guard let path else { return nil }
        guard path.hasPrefix(oldPath + "/") else { return path }
        return newPath + String(path.dropFirst(oldPath.count))
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
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
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
            // A theme action without a theme cannot run, and the picker would
            // show no selection at all, so the stored action becomes a
            // wallpaper action.
            if newSettings.themes.isEmpty, newSettings.rotationAction.isThemeAction {
                newSettings.rotationAction = .shuffle
            }
            settings = newSettings
        }
        syncFromAppState(appState.settings)
    }


    func setMatchSystemAppearance(_ enabled: Bool) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.matchSystemAppearance = enabled
            settings = newSettings
        }
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
    }

    func setRotationAction(_ action: RotationAction) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.rotationAction = action
            settings = newSettings
        }
        syncFromAppState(appState.settings)
    }

    /// The actions the rotation picker offers. A theme action needs a theme,
    /// so it is not offered while there is none.
    var availableRotationActions: [RotationAction] {
        RotationAction.allCases.filter { !$0.isThemeAction || !themes.isEmpty }
    }

    func setHistoryLimit(_ limit: Int) {
        // Only the limits the settings file accepts are stored, so the picker
        // never shows a limit that the model would silently change.
        let clamped = WallpaperSettings.clampHistoryLimit(limit)
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.historyLimit = clamped
            if newSettings.wallpaperHistory.count > clamped {
                newSettings.wallpaperHistory = Array(newSettings.wallpaperHistory.prefix(clamped))
            }
            settings = newSettings
        }
        syncFromAppState(appState.settings)
    }

    func setShortcuts(_ shortcuts: Shortcuts) {
        appState.updateSettings { settings in
            var newSettings = settings
            newSettings.shortcuts = shortcuts
            settings = newSettings
        }
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
    }

    func setAppearanceThemeIDs(light: String?, dark: String?) {
        appState.updateSettings { settings in
            let themeIDs = Set(settings.themes.map(\.id))
            settings.appearanceLightThemeID = light.flatMap { themeIDs.contains($0) ? $0 : nil }
            settings.appearanceDarkThemeID = dark.flatMap { themeIDs.contains($0) ? $0 : nil }
        }
        syncFromAppState(appState.settings)
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
        syncFromAppState(appState.settings)
    }

    /// Stores the appearance configuration of the Appearance sheet.
    ///
    /// The light pin belongs to the light appearance theme and the dark pin
    /// to the dark appearance theme: that is where the app reads the pins
    /// from. Without such a theme the pin belongs to all folders.
    func setAppearanceConfiguration(
        lightThemeID: String?,
        darkThemeID: String?,
        lightWallpaper: String?,
        darkWallpaper: String?
    ) {
        appState.updateSettings { settings in
            var newSettings = settings
            let themeIDs = Set(newSettings.themes.map(\.id))
            let lightID = lightThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }
            let darkID = darkThemeID.flatMap { themeIDs.contains($0) ? $0 : nil }
            newSettings.appearanceLightThemeID = lightID
            newSettings.appearanceDarkThemeID = darkID

            if let lightID, let index = newSettings.themes.firstIndex(where: { $0.id == lightID }) {
                newSettings.themes[index].lightWallpaper = lightWallpaper
            } else {
                newSettings.allFoldersLightWallpaper = lightWallpaper
            }
            if let darkID, let index = newSettings.themes.firstIndex(where: { $0.id == darkID }) {
                newSettings.themes[index].darkWallpaper = darkWallpaper
            } else {
                newSettings.allFoldersDarkWallpaper = darkWallpaper
            }
            settings = newSettings
        }
        syncFromAppState(appState.settings)
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
        // The picker writes the value into `themeSource` before the change is
        // reported, so the value is already the new one here.
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

    /// The images of the "All Folders" light wallpaper picker.
    var allFoldersLightWallpaperImages: [URL] {
        pinPickerImages(allFolderImages, pinnedPath: allFoldersLightWallpaper)
    }

    /// The images of the "All Folders" dark wallpaper picker.
    var allFoldersDarkWallpaperImages: [URL] {
        pinPickerImages(allFolderImages, pinnedPath: allFoldersDarkWallpaper)
    }

    /// The pin of an appearance scope.
    ///
    /// The light pin belongs to the light appearance theme and the dark pin
    /// to the dark appearance theme. Without such a theme the pin belongs to
    /// all folders.
    func appearancePin(forThemeID themeID: String?, dark: Bool) -> String? {
        guard let themeID, let theme = themes.first(where: { $0.id == themeID }) else {
            return dark ? allFoldersDarkWallpaper : allFoldersLightWallpaper
        }
        return dark ? theme.darkWallpaper : theme.lightWallpaper
    }

    /// The images the pin of an appearance scope offers: the images the pin
    /// can be stored in. A theme without folders of its own uses the global
    /// list as its scope, so the other images are not offered.
    func appearancePinImages(forThemeID themeID: String?) -> [URL] {
        guard let themeID, let theme = themes.first(where: { $0.id == themeID }) else {
            return allFolderImages
        }
        let scope = theme.folderPaths.filter { folderPaths.contains($0) }
        // A theme without folders uses the global list as its scope.
        let scopeFolders = scope.isEmpty ? folderPaths : scope
        return WallpaperSettings.images(inScope: scopeFolders, from: allFolderImages)
    }

    /// A pin whose file is missing stays in the picker: the pin is set, so the
    /// user has to see it and be able to clear it.
    private func pinPickerImages(_ images: [URL], pinnedPath: String?) -> [URL] {
        guard let pinnedPath else { return images }
        guard !images.contains(where: { $0.path == pinnedPath }) else { return images }
        return images + [URL(fileURLWithPath: pinnedPath)]
    }


    private var cancellables = Set<AnyCancellable>()

    private func syncFromAppState(_ settings: WallpaperSettings) {
        folderPaths = settings.folderPaths
        themes = settings.themes
        intervalMinutes = settings.intervalMinutes
        rotationAction = settings.rotationAction
        matchSystemAppearance = settings.matchSystemAppearance
        allSpaces = settings.allSpaces
        shortcuts = settings.shortcuts
        historyLimit = settings.historyLimit
        currentWallpaper = settings.currentWallpaper

        appearanceLightThemeID = settings.appearanceLightThemeID
        appearanceDarkThemeID = settings.appearanceDarkThemeID
        allFoldersLightWallpaper = settings.allFoldersLightWallpaper
        allFoldersDarkWallpaper = settings.allFoldersDarkWallpaper
        activeThemeID = settings.activeThemeID

        launchAtLogin = launchAtLoginManager.isEnabled

        themeSource = currentThemeSource
        settingsFolderPath = appState.settingsManager.isUsingDefaultSettingsDirectory
            ? nil
            : appState.settingsManager.settingsDirectory.path
        currentThemeImages = appState.currentThemeImages
        allFolderImages = appState.allFolderImages
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
