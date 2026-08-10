import Foundation

/// Discovers image file URLs within the configured wallpaper folders.
///
/// This is the single source of truth for image-discovery logic, consolidating the
/// duplicated ad-hoc collection that previously lived inline in `RotationService`,
/// `TrayPopoverViewModel`, `AppearanceMonitor`, and `PickerWindow`.
enum ImageDiscoveryService {
    /// The image file extensions that are recognized as wallpapers.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

    /// Scans each folder in `folders` (non-recursively) for files whose extension is
    /// in `imageExtensions`, and returns each folder's natural-sorted images in
    /// configured folder order. This matches Electron's `flatMap(listImages)`.
    /// - Parameter folders: The folder paths to scan.
    /// - Returns: A sorted array of image file URLs. Empty if no folders match or no images are found.
    ///
    /// The sorting uses natural sort order (localizedStandardCompare) to match Electron's
    /// localeCompare({ numeric: true, sensitivity: "base" }).
    static func collectImageURLs(from folders: [String]) -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        for folderPath in folders {
            let folderURL = URL(fileURLWithPath: folderPath)
            guard let contents = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            let images = contents.filter { url in
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    return true
                }
                return false
            }
            urls.append(contentsOf: images.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            })
        }

        return urls
    }
}
