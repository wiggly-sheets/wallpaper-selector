import Foundation

enum ImageDiscoveryService {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

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
