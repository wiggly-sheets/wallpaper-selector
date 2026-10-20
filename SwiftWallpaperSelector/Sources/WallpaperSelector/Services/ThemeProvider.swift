import Foundation

@MainActor
final class ThemeProvider {

    private let settingsManager: SettingsManager
    private let appearanceProvider: SystemAppearanceProviding


    init(
        settingsManager: SettingsManager,
        appearanceProvider: SystemAppearanceProviding = SystemAppearanceProvider()
    ) {
        self.settingsManager = settingsManager
        self.appearanceProvider = appearanceProvider
    }

    /// The theme that is in effect: the appearance theme while matching is on,
    /// otherwise the theme the user picked.
    func effectiveThemeID(isDarkAppearance: Bool) -> String? {
        let settings = settingsManager.settings
        guard settings.matchSystemAppearance else { return settings.activeThemeID }
        return isDarkAppearance ? settings.appearanceDarkThemeID : settings.appearanceLightThemeID
    }

    func effectiveFolders(isDarkAppearance: Bool? = nil) -> [String] {
        let all = settingsManager.settings.folderPaths
        let isDark = isDarkAppearance ?? appearanceProvider.isDarkAppearance
        guard let themeID = effectiveThemeID(isDarkAppearance: isDark), !themeID.isEmpty,
              let theme = settingsManager.settings.themes.first(where: { $0.id == themeID }) else {
            return all
        }
        let scope = theme.folderPaths.filter { all.contains($0) }
        // A theme without folders must not empty the rotation scope: the
        // folders are configured, so the global list is the right scope.
        return scope.isEmpty ? all : scope
    }

    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        let s = settingsManager.settings

        let theme: Theme? = effectiveThemeID(isDarkAppearance: isDarkAppearance).flatMap { id in
            s.themes.first { $0.id == id }
        }

        guard let theme else {
            return (s.allFoldersLightWallpaper, s.allFoldersDarkWallpaper)
        }
        return (theme.lightWallpaper, theme.darkWallpaper)
    }
}
