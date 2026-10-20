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

        // Every field decodes leniently: one bad value must never reject the
        // whole settings file, because the next save would overwrite it.
        func decodeValue<T: Decodable>(_ type: T.Type, _ key: CodingKeys, default defaultValue: T) -> T {
            let decoded = try? values.decodeIfPresent(type, forKey: key)
            return decoded.flatMap { $0 } ?? defaultValue
        }

        func decodeOptional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            let decoded = try? values.decodeIfPresent(type, forKey: key)
            return decoded.flatMap { $0 }
        }

        let legacyFolder = decodeOptional(String.self, .folderPath).flatMap(Self.absoluteFolderPath)
        // The legacy folder is only used when the file has no folder list: a
        // file that has a usable list wins, even with an empty list. A value
        // that is not a list of strings, or a list without a usable string in
        // it, cannot be used, so the legacy folder is the scope then. A
        // relative wallpaper and a relative history entry belong to the
        // legacy folder only in that case, because a file that has the list
        // does not say which of the configured folders they are in.
        let storedFolderPaths = LenientDecoding.optionalStringArray(from: values, forKey: .folderPaths)
        if let storedFolderPaths {
            // A relative folder would be resolved against the working
            // directory of the process, so it is stored absolute.
            folderPaths = storedFolderPaths.compactMap(Self.absoluteFolderPath)
        } else {
            folderPaths = legacyFolder.map { [$0] } ?? []
        }
        // The legacy folder is the scope of the file: every wallpaper it
        // names belongs to that folder.
        let legacyScope = storedFolderPaths == nil ? legacyFolder : nil

        let storedWallpaper = decodeOptional(String.self, .currentWallpaper)
        if let storedWallpaper, !storedWallpaper.hasPrefix("/") {
            if let legacyScope {
                currentWallpaper = URL(fileURLWithPath: legacyScope)
                    .appendingPathComponent(storedWallpaper)
                    .path
            } else {
                // The wallpaper stays unknown: a relative path would be
                // resolved against the working directory.
                currentWallpaper = nil
            }
        } else {
            currentWallpaper = storedWallpaper
        }

        let storedInterval = decodeValue(Int.self, .intervalMinutes, default: RotationInterval.off.rawValue)
        intervalMinutes = RotationInterval(rawValue: storedInterval) ?? .off

        let storedAction = decodeOptional(String.self, .rotationAction)
        rotationAction = RotationAction(rawValue: storedAction ?? "") ?? .shuffle

        allSpaces = decodeValue(Bool.self, .allSpaces, default: false)
        shortcuts = decodeValue(Shortcuts.self, .shortcuts, default: .default)
        themes = Self.decodeThemes(from: values).map { theme in
            var theme = theme
            theme.lightWallpaper = Self.resolveWallpaper(theme.lightWallpaper, in: legacyScope)
            theme.darkWallpaper = Self.resolveWallpaper(theme.darkWallpaper, in: legacyScope)
            return theme
        }
        activeThemeID = decodeOptional(String.self, .activeThemeId)
        matchSystemAppearance = decodeValue(Bool.self, .matchSystemAppearance, default: false)
        allFoldersLightWallpaper = Self.resolveWallpaper(
            decodeOptional(String.self, .allFoldersLightWallpaper),
            in: legacyScope
        )
        allFoldersDarkWallpaper = Self.resolveWallpaper(
            decodeOptional(String.self, .allFoldersDarkWallpaper),
            in: legacyScope
        )
        appearanceLightThemeID = decodeOptional(String.self, .appearanceLightThemeId)
        appearanceDarkThemeID = decodeOptional(String.self, .appearanceDarkThemeId)
        historyLimit = Self.clampHistoryLimit(decodeValue(Int.self, .historyLimit, default: 10))
        var history = LenientDecoding.stringArray(from: values, forKey: .wallpaperHistory)
        if let legacyScope {
            history = history.map { entry in
                entry.hasPrefix("/")
                    ? entry
                    : URL(fileURLWithPath: legacyScope).appendingPathComponent(entry).path
            }
        } else {
            // A relative entry that cannot be resolved never matches an
            // absolute path, so it is dropped.
            history = history.filter { $0.hasPrefix("/") }
        }
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
        wallpaperHistory = history
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

    /// The history limits the settings file accepts.
    public static let historyLimitOptions = [5, 10, 20]

    /// The one clamp for the history limit: every other value becomes the
    /// closest limit the settings file accepts.
    public static func clampHistoryLimit(_ limit: Int) -> Int {
        let lowest = historyLimitOptions.min() ?? 10
        let highest = historyLimitOptions.max() ?? 10
        // The distance is measured on a bounded value: an extreme limit would
        // overflow the subtraction and trap while the file is decoded.
        let bounded = min(max(limit, lowest), highest)
        return historyLimitOptions.min { abs($0 - bounded) < abs($1 - bounded) } ?? 10
    }

    /// Resolves a folder to an absolute path.
    ///
    /// A `~` is expanded, an absolute path is kept as it is, and a relative
    /// path is resolved against the home directory: the settings file lives
    /// there, so that is the base a relative path was written against. The
    /// absolute path is needed, because the app reads the folders with
    /// `URL(fileURLWithPath:)`, and that resolves a relative path against
    /// the working directory of the process - the root for an app that is
    /// started from the Finder.
    ///
    /// A tilde that cannot be expanded is not a path: the user has no such
    /// home directory, so the folder is not usable. A path that is empty is
    /// not a folder either: it would be the home directory. `.` and `..`
    /// name the working directory and its parent, so they are not folders
    /// either.
    static func absoluteFolderPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != ".", trimmed != ".." else { return nil }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        if trimmed.hasPrefix("~") {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            guard expanded.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        let resolved = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
        return resolved.hasPrefix("/") ? resolved : nil
    }

    /// Resolves a relative wallpaper against the legacy folder.
    ///
    /// The legacy folder is the scope of a file that has no folder list, so
    /// every wallpaper the file names belongs to that folder. A theme's
    /// folders are scope definitions and stay as they are.
    private static func resolveWallpaper(_ wallpaper: String?, in folder: String?) -> String? {
        guard let wallpaper, let folder, !wallpaper.hasPrefix("/") else { return wallpaper }
        return URL(fileURLWithPath: folder).appendingPathComponent(wallpaper).path
    }

    /// Decodes the themes and gives every theme without a usable id a stable
    /// one, so the same file always produces the same theme ids.
    ///
    /// The scope folders of a theme are folder paths like every other folder
    /// path in the file, so they are resolved here: a relative scope would be
    /// resolved against the working directory of the process.
    private static func decodeThemes(from values: KeyedDecodingContainer<CodingKeys>) -> [Theme] {
        let decoded = Theme.decodeArray(from: values, forKey: .themes)
        var usedIDs = Set(decoded.filter { !$0.id.isEmpty }.map(\.id))

        return decoded.enumerated().map { index, theme in
            var theme = theme
            theme.folderPaths = theme.folderPaths.compactMap(Self.absoluteFolderPath)
            guard theme.id.isEmpty else { return theme }
            var id = "theme-\(index)"
            var suffix = 1
            while usedIDs.contains(id) {
                id = "theme-\(index)-\(suffix)"
                suffix += 1
            }
            usedIDs.insert(id)
            return Theme(
                id: id,
                name: theme.name,
                folderPaths: theme.folderPaths,
                lightWallpaper: theme.lightWallpaper,
                darkWallpaper: theme.darkWallpaper
            )
        }
    }
}

extension WallpaperSettings {
    func normalized() -> WallpaperSettings {
        var normalized = self

        func orderedUnique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { seen.insert($0).inserted }
        }

        // An empty folder is the working directory, so it is not a folder. A
        // relative folder would be resolved against the working directory of
        // the process, so it is made absolute here. A path that stays
        // relative is dropped: it never names a folder.
        normalized.folderPaths = orderedUnique(
            folderPaths.compactMap(Self.absoluteFolderPath)
        )
        let configuredFolders = Set(normalized.folderPaths)

        var seenThemeIDs = Set<String>()
        normalized.themes = themes.compactMap { theme in
            guard seenThemeIDs.insert(theme.id).inserted else { return nil }
            var theme = theme
            // The scope folders of a theme are folder paths like every other
            // folder path, so they are made absolute here. A scope that does
            // not name a configured folder is dropped, so a theme cannot
            // cover a folder the app does not rotate.
            theme.folderPaths = orderedUnique(
                theme.folderPaths
                    .compactMap(Self.absoluteFolderPath)
                    .filter { configuredFolders.contains($0) }
            )
            // A theme without folders uses the global list as its scope, so its
            // pin is validated against the global list too. Otherwise the pin
            // would be dropped on every save.
            let scope = theme.folderPaths.isEmpty ? normalized.folderPaths : theme.folderPaths
            theme.lightWallpaper = validWallpaper(theme.lightWallpaper, in: scope)
            theme.darkWallpaper = validWallpaper(theme.darkWallpaper, in: scope)
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
        // A theme action needs a theme: without one the rotation picker
        // would show no selection at all and the rotation could only report
        // that there is no theme, so the stored action becomes a wallpaper
        // action.
        if normalized.themes.isEmpty, normalized.rotationAction.isThemeAction {
            normalized.rotationAction = .shuffle
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

        normalized.historyLimit = Self.clampHistoryLimit(normalized.historyLimit)
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
            let folderPath = URL(fileURLWithPath: folder).standardizedFileURL.path
            // A wallpaper in a subfolder of a configured folder belongs to it too.
            return parent == folderPath || parent.hasPrefix(folderPath + "/")
        }
        return belongsToScope ? wallpaper : nil
    }

    /// The images that are inside the scope. An image belongs to a folder when
    /// it is in the folder or in one of its subfolders, the same rule the
    /// wallpaper pins are checked with.
    static func images(inScope folders: [String], from images: [URL]) -> [URL] {
        images.filter { image in
            let parent = image
                .deletingLastPathComponent()
                .standardizedFileURL.path
            return folders.contains { folder in
                let folderPath = URL(fileURLWithPath: folder).standardizedFileURL.path
                return parent == folderPath || parent.hasPrefix(folderPath + "/")
            }
        }
    }
}
