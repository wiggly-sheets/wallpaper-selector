import Foundation

/// Where a wallpaper can be downloaded from.
///
/// The raw value is the value the settings file stores, so it must not change.
public enum WallpaperSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case wallhaven
    case bingDaily
    case wikimedia

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .wallhaven: return "Wallhaven"
        case .bingDaily: return "Bing Daily"
        case .wikimedia: return "Wikimedia Commons"
        }
    }

    var detail: String {
        switch self {
        case .wallhaven: return "Community wallpapers, safe for work."
        case .bingDaily: return "The daily Bing home page image of the last days."
        case .wikimedia: return "The featured image of the day of the last days."
        }
    }
}

/// One wallpaper that a source offers for download.
struct RemoteWallpaper: Equatable, Identifiable, Sendable {
    let source: WallpaperSource
    /// The name of the file in the download folder.
    let fileName: String
    let imageURL: URL
    /// A smaller image for the browser grid, when the source offers one.
    let thumbnailURL: URL?

    var id: String { fileName }

    init(source: WallpaperSource, fileName: String, imageURL: URL, thumbnailURL: URL? = nil) {
        self.source = source
        self.fileName = fileName
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
    }
}
