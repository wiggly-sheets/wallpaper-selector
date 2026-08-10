import Foundation

/// A named subset of the configured folders.
public struct Theme: Codable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    /// Subset of `folderPaths` this theme pulls images from.
    public var folderPaths: [String]
    /// Absolute path applied automatically while this theme is active and macOS is in Light mode.
    public var lightWallpaper: String?
    /// Absolute path applied automatically while this theme is active and macOS is in Dark mode.
    public var darkWallpaper: String?

    public init(id: String = UUID().uuidString, name: String, folderPaths: [String],
                lightWallpaper: String? = nil, darkWallpaper: String? = nil) {
        self.id = id
        self.name = name
        self.folderPaths = folderPaths
        self.lightWallpaper = lightWallpaper
        self.darkWallpaper = darkWallpaper
    }

    /// Matches original Electron label fallback for unnamed themes.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        guard !folderPaths.isEmpty else { return "Untitled Theme" }
        if folderPaths.count <= 2 {
            return folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        }
        return "\((folderPaths[0] as NSString).lastPathComponent) +\(folderPaths.count - 1) more"
    }
}
