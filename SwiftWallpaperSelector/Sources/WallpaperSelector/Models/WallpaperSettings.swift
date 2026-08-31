import Foundation

public struct WallpaperSettings: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case folderPath
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

extension WallpaperSettings {
    func normalized() -> WallpaperSettings {
        var normalized = self

        func orderedUnique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { seen.insert($0).inserted }
        }

        normalized.folderPaths = orderedUnique(folderPaths)
        let configuredFolders = Set(normalized.folderPaths)

        var seenThemeIDs = Set<String>()
        normalized.themes = themes.compactMap { theme in
            guard seenThemeIDs.insert(theme.id).inserted else { return nil }
            var theme = theme
            theme.folderPaths = orderedUnique(theme.folderPaths.filter { configuredFolders.contains($0) })
            theme.lightWallpaper = validWallpaper(theme.lightWallpaper, in: theme.folderPaths)
            theme.darkWallpaper = validWallpaper(theme.darkWallpaper, in: theme.folderPaths)
            return theme
        }

        let themeIDs = Set(normalized.themes.map(\.id))
        if let activeThemeID, !themeIDs.contains(activeThemeID) {
            normalized.activeThemeID = nil
        }
        if let appearanceLightThemeID, !themeIDs.contains(appearanceLightThemeID) {
            normalized.appearanceLightThemeID = nil
        }
        if let appearanceDarkThemeID, !themeIDs.contains(appearanceDarkThemeID) {
            normalized.appearanceDarkThemeID = nil
        }

        normalized.allFoldersLightWallpaper = validWallpaper(
            allFoldersLightWallpaper,
            in: normalized.folderPaths
        )
        normalized.allFoldersDarkWallpaper = validWallpaper(
            allFoldersDarkWallpaper,
            in: normalized.folderPaths
        )

        if normalized.shortcuts.showPreview == normalized.shortcuts.showMain,
           normalized.shortcuts.showPreview != nil {
            normalized.shortcuts.showPreview = nil
        }
        if let menuShortcut = normalized.shortcuts.showMenu,
           menuShortcut == normalized.shortcuts.showMain || menuShortcut == normalized.shortcuts.showPreview {
            normalized.shortcuts.showMenu = nil
        }

        if ![5, 10, 20].contains(normalized.historyLimit) {
            normalized.historyLimit = 10
        }
        normalized.wallpaperHistory = Array(
            orderedUnique(wallpaperHistory).prefix(normalized.historyLimit)
        )
        return normalized
    }

    private func validWallpaper(_ wallpaper: String?, in folders: [String]) -> String? {
        guard let wallpaper else { return nil }
        let parent = URL(fileURLWithPath: wallpaper)
            .deletingLastPathComponent()
            .standardizedFileURL.path
        let belongsToScope = folders.contains { folder in
            URL(fileURLWithPath: folder).standardizedFileURL.path == parent
        }
        return belongsToScope ? wallpaper : nil
    }
}
