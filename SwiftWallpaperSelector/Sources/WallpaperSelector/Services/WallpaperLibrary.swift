import Foundation

actor WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private struct FolderFingerprint: Equatable {
        let path: String
        let modificationDate: Date?
    }

    private var cachedFingerprints: [FolderFingerprint] = []
    private var cachedURLs: [URL] = []

    /// Counts how often the image list was loaded. A test uses it to prove
    /// that the app does not ask for the same list twice.
    private(set) var loadCount = 0

    func imageURLs(in folders: [String]) -> [URL] {
        loadCount += 1
        let fingerprints = folders.map { path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return FolderFingerprint(
                path: path,
                modificationDate: attributes?[.modificationDate] as? Date
            )
        }

        if fingerprints == cachedFingerprints {
            return cachedURLs
        }

        let urls = ImageDiscoveryService.collectImageURLs(from: folders)
        cachedFingerprints = fingerprints
        cachedURLs = urls
        return urls
    }

    func invalidate() {
        cachedFingerprints = []
        cachedURLs = []
    }
}
