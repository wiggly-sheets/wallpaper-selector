import Foundation

enum ImageDiscoveryService {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static func collectImageURLs(from folders: [String]) -> [URL] {
        var urls: [URL] = []
        var collectedPaths = Set<String>()
        let fm = FileManager.default

        for folderPath in folders {
            let folderURL = URL(fileURLWithPath: folderPath)
            guard let contents = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            let images = contents.filter { url in
                guard imageExtensions.contains(url.pathExtension.lowercased()) else {
                    return false
                }
                // A directory that is named like an image is not a wallpaper.
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    return false
                }
                return !isDirectory.boolValue
            }
            for url in images.sorted(by: { first, second in
                first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
            }) {
                // Overlapping folders can list the same file twice. The
                // resolved path is the key, so a folder that is reached
                // through a symlink does not list its files twice.
                guard collectedPaths.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                urls.append(url)
            }
        }

        return urls
    }
}
