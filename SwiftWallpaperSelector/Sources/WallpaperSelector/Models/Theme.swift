import Foundation

public struct Theme: Codable, Equatable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var folderPaths: [String]
    public var lightWallpaper: String?
    public var darkWallpaper: String?

    public init(id: String = UUID().uuidString, name: String, folderPaths: [String],
                lightWallpaper: String? = nil, darkWallpaper: String? = nil) {
        self.id = id
        self.name = name
        self.folderPaths = folderPaths
        self.lightWallpaper = lightWallpaper
        self.darkWallpaper = darkWallpaper
    }

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
