import Foundation

final class ThemeProvider {

    private let settingsManager: SettingsManager


    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    func effectiveFolders() -> [String] {
        let all = settingsManager.settings.folderPaths
        guard let themeID = settingsManager.settings.activeThemeID, !themeID.isEmpty,
              let theme = settingsManager.settings.themes.first(where: { $0.id == themeID }) else {
            return all
        }
        return theme.folderPaths.filter { all.contains($0) }
    }

    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        let s = settingsManager.settings

        let effectiveThemeID: String? =
            s.matchSystemAppearance
                ? (isDarkAppearance ? s.appearanceDarkThemeID : s.appearanceLightThemeID)
                : s.activeThemeID

        let theme: Theme? = effectiveThemeID.flatMap { id in
            s.themes.first { $0.id == id }
        }

        guard let theme else {
            return (s.allFoldersLightWallpaper, s.allFoldersDarkWallpaper)
        }
        return (theme.lightWallpaper, theme.darkWallpaper)
    }
}
