import CoreGraphics
import Foundation
import ImageIO

struct DecodedWallpaperThumbnail: @unchecked Sendable {
    let image: CGImage
}

actor WallpaperThumbnailRepository {
    static let shared = WallpaperThumbnailRepository()

    private struct CacheKey: Hashable {
        let path: String
        let modificationDate: Date?
        let maximumPixelSize: Int
    }

    /// A decoded image or the knowledge that the file cannot be decoded.
    ///
    /// The failure is cached too, so a corrupt or unsupported image is not
    /// decoded again on every scroll. A failure expires after
    /// `failureLifetime`, because a file that is being written can look
    /// corrupt for a moment and must be decoded again later. The file is
    /// decoded again when its modification date changes or the cache is
    /// purged too.
    private enum CacheEntry {
        case image(DecodedWallpaperThumbnail)
        case failure(Date)
    }

    private let cacheLimit: Int
    private let failureLifetime: TimeInterval
    private var cache: [CacheKey: CacheEntry] = [:]
    private var cacheOrder: [CacheKey] = []

    init(cacheLimit: Int = 64, failureLifetime: TimeInterval = 60) {
        self.cacheLimit = max(1, cacheLimit)
        self.failureLifetime = failureLifetime
    }

    func thumbnail(for url: URL, maximumPixelSize: Int) -> DecodedWallpaperThumbnail? {
        guard !Task.isCancelled else { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = CacheKey(
            path: url.standardizedFileURL.path,
            modificationDate: attributes?[.modificationDate] as? Date,
            maximumPixelSize: maximumPixelSize
        )
        if let cached = cache[key] {
            switch cached {
            case .image(let thumbnail):
                touch(key)
                return thumbnail
            case .failure(let date):
                if Date().timeIntervalSince(date) < failureLifetime {
                    touch(key)
                    return nil
                }
                // The failure expired: drop it and decode the file again.
                cache.removeValue(forKey: key)
                cacheOrder.removeAll { $0 == key }
            }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            guard !Task.isCancelled else { return nil }
            store(.failure(Date()), for: key)
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            guard !Task.isCancelled else { return nil }
            store(.failure(Date()), for: key)
            return nil
        }
        // The task may have been cancelled while the image was decoded. The
        // result is not needed then, so it is not cached either.
        guard !Task.isCancelled else { return nil }

        let thumbnail = DecodedWallpaperThumbnail(image: image)
        store(.image(thumbnail), for: key)
        return thumbnail
    }

    private func store(_ entry: CacheEntry, for key: CacheKey) {
        cache[key] = entry
        touch(key)
        evictIfNeeded()
    }

    private func touch(_ key: CacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    /// Drops the decoded thumbnails. Used when a window that shows them closes.
    func purge() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    private func evictIfNeeded() {
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }
}
