import Foundation

/// The full settings model persisted to JSON.
public struct WallpaperSettings: Codable, Equatable {
    public var folderPaths: [String]
    public var currentWallpaper: String?
    public var intervalMinutes: RotationInterval
    public var rotationAction: RotationAction
    public var allSpaces: Bool
    public var shortcuts: Shortcuts
    public var themes: [Theme]
    public var activeThemeID: String?
    public var matchSystemAppearance: Bool
    public var allFoldersLightWallpaper: String?
    public var allFoldersDarkWallpaper: String?
    public var appearanceLightThemeID: String?
    public var appearanceDarkThemeID: String?
    public var historyLimit: Int
    public var wallpaperHistory: [String]

    public init(
        folderPaths: [String] = [],
        currentWallpaper: String? = nil,
        intervalMinutes: RotationInterval = .off,
        rotationAction: RotationAction = .shuffle,
        allSpaces: Bool = false,
        shortcuts: Shortcuts = .default,
        themes: [Theme] = [],
        activeThemeID: String? = nil,
        matchSystemAppearance: Bool = false,
        allFoldersLightWallpaper: String? = nil,
        allFoldersDarkWallpaper: String? = nil,
        appearanceLightThemeID: String? = nil,
        appearanceDarkThemeID: String? = nil,
        historyLimit: Int = 10,
        wallpaperHistory: [String] = []
    ) {
        self.folderPaths = folderPaths
        self.currentWallpaper = currentWallpaper
        self.intervalMinutes = intervalMinutes
        self.rotationAction = rotationAction
        self.allSpaces = allSpaces
        self.shortcuts = shortcuts
        self.themes = themes
        self.activeThemeID = activeThemeID
        self.matchSystemAppearance = matchSystemAppearance
        self.allFoldersLightWallpaper = allFoldersLightWallpaper
        self.allFoldersDarkWallpaper = allFoldersDarkWallpaper
        self.appearanceLightThemeID = appearanceLightThemeID
        self.appearanceDarkThemeID = appearanceDarkThemeID
        self.historyLimit = historyLimit
        self.wallpaperHistory = wallpaperHistory
    }

    // Keep disk schema byte-for-byte compatible with Electron settings. Swift
    // naming uses `ID`; Electron persisted `Id`, and synthesized Codable would
    // otherwise make existing users appear to have default settings.
    private enum CodingKeys: String, CodingKey {
        case folderPath // legacy single-folder schema
        case folderPaths, currentWallpaper, intervalMinutes, rotationAction, allSpaces
        case shortcuts, themes, activeThemeId, matchSystemAppearance
        case allFoldersLightWallpaper, allFoldersDarkWallpaper
        case appearanceLightThemeId, appearanceDarkThemeId
        case historyLimit, wallpaperHistory
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyFolder = try values.decodeIfPresent(String.self, forKey: .folderPath)
        folderPaths = try values.decodeIfPresent([String].self, forKey: .folderPaths)
            ?? legacyFolder.map { [$0] }
            ?? []

        let storedWallpaper = try values.decodeIfPresent(String.self, forKey: .currentWallpaper)
        if let storedWallpaper, !storedWallpaper.hasPrefix("/"), let legacyFolder {
            currentWallpaper = URL(fileURLWithPath: legacyFolder)
                .appendingPathComponent(storedWallpaper)
                .path
        } else {
            currentWallpaper = storedWallpaper
        }

        intervalMinutes = try values.decodeIfPresent(RotationInterval.self, forKey: .intervalMinutes) ?? .off
        rotationAction = try values.decodeIfPresent(RotationAction.self, forKey: .rotationAction) ?? .shuffle
        allSpaces = try values.decodeIfPresent(Bool.self, forKey: .allSpaces) ?? false
        shortcuts = try values.decodeIfPresent(Shortcuts.self, forKey: .shortcuts) ?? .default
        themes = try values.decodeIfPresent([Theme].self, forKey: .themes) ?? []
        activeThemeID = try values.decodeIfPresent(String.self, forKey: .activeThemeId)
        matchSystemAppearance = try values.decodeIfPresent(Bool.self, forKey: .matchSystemAppearance) ?? false
        allFoldersLightWallpaper = try values.decodeIfPresent(String.self, forKey: .allFoldersLightWallpaper)
        allFoldersDarkWallpaper = try values.decodeIfPresent(String.self, forKey: .allFoldersDarkWallpaper)
        appearanceLightThemeID = try values.decodeIfPresent(String.self, forKey: .appearanceLightThemeId)
        appearanceDarkThemeID = try values.decodeIfPresent(String.self, forKey: .appearanceDarkThemeId)
        historyLimit = try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 10
        if ![5, 10, 20].contains(historyLimit) { historyLimit = 10 }
        wallpaperHistory = try values.decodeIfPresent([String].self, forKey: .wallpaperHistory) ?? []
        if wallpaperHistory.count > historyLimit {
            wallpaperHistory = Array(wallpaperHistory.prefix(historyLimit))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(folderPaths, forKey: .folderPaths)
        try values.encodeIfPresent(currentWallpaper, forKey: .currentWallpaper)
        try values.encode(intervalMinutes, forKey: .intervalMinutes)
        try values.encode(rotationAction, forKey: .rotationAction)
        try values.encode(allSpaces, forKey: .allSpaces)
        try values.encode(shortcuts, forKey: .shortcuts)
        try values.encode(themes, forKey: .themes)
        try values.encodeIfPresent(activeThemeID, forKey: .activeThemeId)
        try values.encode(matchSystemAppearance, forKey: .matchSystemAppearance)
        try values.encodeIfPresent(allFoldersLightWallpaper, forKey: .allFoldersLightWallpaper)
        try values.encodeIfPresent(allFoldersDarkWallpaper, forKey: .allFoldersDarkWallpaper)
        try values.encodeIfPresent(appearanceLightThemeID, forKey: .appearanceLightThemeId)
        try values.encodeIfPresent(appearanceDarkThemeID, forKey: .appearanceDarkThemeId)
        try values.encode(historyLimit, forKey: .historyLimit)
        try values.encode(wallpaperHistory, forKey: .wallpaperHistory)
    }
}
