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

    private let cacheLimit: Int
    private var cache: [CacheKey: DecodedWallpaperThumbnail] = [:]
    private var cacheOrder: [CacheKey] = []

    init(cacheLimit: Int = 256) {
        self.cacheLimit = max(1, cacheLimit)
    }

    func thumbnail(for url: URL, maximumPixelSize: Int) -> DecodedWallpaperThumbnail? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = CacheKey(
            path: url.standardizedFileURL.path,
            modificationDate: attributes?[.modificationDate] as? Date,
            maximumPixelSize: maximumPixelSize
        )
        if let cached = cache[key] {
            touch(key)
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let thumbnail = DecodedWallpaperThumbnail(image: image)
        cache[key] = thumbnail
        touch(key)
        evictIfNeeded()
        return thumbnail
    }

    private func touch(_ key: CacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func evictIfNeeded() {
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }
}
