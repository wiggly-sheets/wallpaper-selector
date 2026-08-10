import Foundation

/// Provides computed values based on the current settings: which folders are in effect
/// and what the effective light/dark wallpaper pair is for the current appearance.
///
/// Holds a reference to `SettingsManager` so that `effectiveFolders()` and
/// `effectiveAppearanceWallpapers(isDarkAppearance:)` always reflect the latest
/// persisted settings, rather than a snapshot taken at init time.
final class ThemeProvider {
    // MARK: - Private

    private let settingsManager: SettingsManager

    // MARK: - Init

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    /// Returns the array of folder paths that are currently active.
    /// - If a theme is selected, returns that theme's folders (filtered to those still present in settings.folderPaths).
    /// - Otherwise returns all configured folders.
    func effectiveFolders() -> [String] {
        let all = settingsManager.settings.folderPaths
        guard let themeID = settingsManager.settings.activeThemeID, !themeID.isEmpty,
              let theme = settingsManager.settings.themes.first(where: { $0.id == themeID }) else {
            return all
        }
        // Keep only folders that are still configured (defensive against stale references)
        return theme.folderPaths.filter { all.contains($0) }
    }

    /// Returns the effective light and dark wallpaper paths for the current appearance.
    /// If `matchSystemAppearance` is true, we pick the wallpaper (or theme) based on the current
    /// system appearance; otherwise we always use the wallpapers associated with the active theme
    /// (or the "All Folders" fallbacks).
    func effectiveAppearanceWallpapers(isDarkAppearance: Bool) -> (light: String?, dark: String?) {
        let s = settingsManager.settings

        // Determine which theme ID to use for appearance-based switching
        let effectiveThemeID: String? =
            s.matchSystemAppearance
                ? (isDarkAppearance ? s.appearanceDarkThemeID : s.appearanceLightThemeID)
                : s.activeThemeID

        // Resolve the effective theme (may be nil)
        let theme: Theme? = effectiveThemeID.flatMap { id in
            s.themes.first { $0.id == id }
        }

        // Electron treats a selected theme as its own scope: an absent theme
        // pin means no pin, not a fallback from All Folders.
        guard let theme else {
            return (s.allFoldersLightWallpaper, s.allFoldersDarkWallpaper)
        }
        return (theme.lightWallpaper, theme.darkWallpaper)
    }
}
