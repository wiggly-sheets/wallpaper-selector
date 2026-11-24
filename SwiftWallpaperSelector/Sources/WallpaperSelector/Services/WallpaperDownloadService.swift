import Foundation

enum WallpaperDownloadError: LocalizedError {
    case requestFailed(url: String, reason: String)
    case invalidResponse(WallpaperSource)
    case notAnImage(URL)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(url, reason):
            return "Request to \(url) failed: \(reason)"
        case let .invalidResponse(source):
            return "\(source.label) returned a response the app does not understand."
        case let .notAnImage(url):
            return "\(url.absoluteString) did not return an image."
        }
    }
}

struct WallpaperDownloadSummary: Equatable, Sendable {
    let saved: Int
    /// One line per source that failed, so a partial success stays visible.
    let failures: [String]
}

/// A request of a source, and the day its file name carries.
struct WallpaperSourceRequest: Sendable {
    let request: URLRequest
    let dayLabel: String?
}

/// The requests and the parsing of the sources.
///
/// The functions are pure, so a test can feed a recorded payload.
enum WallpaperSourceAPI {
    static let userAgent =
        "WallpaperSelector/1.2 (macOS; https://github.com/wiggly-sheets/wallpaper-selector)"

    static func requests(
        for source: WallpaperSource,
        count: Int,
        now: Date = Date()
    ) -> [WallpaperSourceRequest] {
        switch source {
        case .wallhaven:
            [WallpaperSourceRequest(request: request(url: wallhavenURL()), dayLabel: nil)]
        case .bingDaily:
            [WallpaperSourceRequest(request: request(url: bingURL(count: count)), dayLabel: nil)]
        case .wikimedia:
            wikimediaRequests(count: count, now: now)
        }
    }

    // MARK: - Wallhaven

    static func wallhavenURL() -> URL {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "sorting", value: "random"),
            URLQueryItem(name: "atleast", value: "1920x1080"),
            URLQueryItem(name: "ratios", value: "16x9"),
            URLQueryItem(name: "categories", value: "100"),
            URLQueryItem(name: "purity", value: "100")
        ]
        return components.url!
    }

    static func wallhavenWallpapers(from data: Data) throws -> [RemoteWallpaper] {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Thumbs: Decodable {
                    let large: String?
                }

                let id: String?
                let path: String?
                let fileType: String?
                let thumbs: Thumbs?

                enum CodingKeys: String, CodingKey {
                    case id, path, thumbs
                    case fileType = "file_type"
                }
            }

            let data: [Item]?
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WallpaperDownloadError.invalidResponse(.wallhaven)
        }

        return (response.data ?? []).compactMap { item in
            guard let id = item.id, let url = item.path.flatMap(URL.init(string:)) else { return nil }
            let fileExtension = imageExtension(forFileType: item.fileType, fallbackURL: url)
            return RemoteWallpaper(
                source: .wallhaven,
                fileName: "wallhaven-\(safeFileName(id)).\(fileExtension)",
                imageURL: url,
                thumbnailURL: item.thumbs?.large.flatMap(URL.init(string:))
            )
        }
    }

    // MARK: - Bing

    /// The archive holds eight days at most.
    private static let bingDayCount = 8

    static func bingURL(count: Int) -> URL {
        var components = URLComponents(string: "https://www.bing.com/HPImageArchive.aspx")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "n", value: String(min(max(count, 1), bingDayCount))),
            URLQueryItem(name: "mkt", value: "en-US")
        ]
        return components.url!
    }

    static func bingWallpapers(from data: Data) throws -> [RemoteWallpaper] {
        struct Response: Decodable {
            struct Image: Decodable {
                let startdate: String?
                let urlbase: String?
            }

            let images: [Image]?
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WallpaperDownloadError.invalidResponse(.bingDaily)
        }

        return (response.images ?? []).compactMap { image in
            guard let startdate = image.startdate, let urlbase = image.urlbase else { return nil }
            // The archive reports 1920x1080; the UHD variant is 3840x2160.
            guard let url = URL(string: "https://www.bing.com\(urlbase)_UHD.jpg") else { return nil }
            return RemoteWallpaper(
                source: .bingDaily,
                fileName: "bing-\(safeFileName(startdate)).jpg",
                imageURL: url,
                thumbnailURL: URL(string: "https://www.bing.com\(urlbase)_400x240.jpg")
            )
        }
    }

    // MARK: - Wikimedia

    static func wikimediaRequests(count: Int, now: Date = Date()) -> [WallpaperSourceRequest] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let pathFormatter = DateFormatter()
        pathFormatter.locale = Locale(identifier: "en_US_POSIX")
        pathFormatter.timeZone = calendar.timeZone
        pathFormatter.dateFormat = "yyyy/MM/dd"

        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "yyyy-MM-dd"

        return (0..<max(count, 1)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now),
                  let url = URL(string: "https://api.wikimedia.org/feed/v1/wikipedia/en/featured/"
                                + pathFormatter.string(from: day))
            else { return nil }
            return WallpaperSourceRequest(
                request: request(url: url),
                dayLabel: labelFormatter.string(from: day)
            )
        }
    }

    static func wikimediaWallpapers(from data: Data, dayLabel: String) throws -> [RemoteWallpaper] {
        struct Response: Decodable {
            struct SizedSource: Decodable {
                let source: String?
                let width: Int?
                let height: Int?
            }

            struct Image: Decodable {
                let image: SizedSource?
                let thumbnail: SizedSource?
            }

            let image: Image?
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WallpaperDownloadError.invalidResponse(.wikimedia)
        }

        guard let sized = response.image?.image,
              let source = sized.source,
              let url = URL(string: source)
        else { return [] }

        // A portrait image makes a poor desktop wallpaper.
        if let width = sized.width, let height = sized.height, width <= height { return [] }

        return [RemoteWallpaper(
            source: .wikimedia,
            fileName: "wikimedia-\(safeFileName(dayLabel)).\(imageExtension(fallbackURL: url))",
            imageURL: url,
            thumbnailURL: response.image?.thumbnail?.source.flatMap(URL.init(string:))
        )]
    }

    // MARK: - Shared

    static func wallpapers(
        for source: WallpaperSource,
        from data: Data,
        dayLabel: String?
    ) throws -> [RemoteWallpaper] {
        switch source {
        case .wallhaven:
            return try wallhavenWallpapers(from: data)
        case .bingDaily:
            return try bingWallpapers(from: data)
        case .wikimedia:
            guard let dayLabel else { return [] }
            return try wikimediaWallpapers(from: data, dayLabel: dayLabel)
        }
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func imageExtension(forFileType fileType: String?, fallbackURL: URL) -> String {
        switch fileType?.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/webp":
            return "webp"
        default:
            return imageExtension(fallbackURL: fallbackURL)
        }
    }

    private static func imageExtension(fallbackURL: URL) -> String {
        let candidate = fallbackURL.pathExtension.lowercased()
        return candidate.isEmpty ? "jpg" : candidate
    }

    /// Keeps the file name inside the download folder: a value of a source
    /// never names a path of its own.
    private static func safeFileName(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

/// The folder that downloads are written into.
///
/// The folder is not a setting: it belongs to the app, and the app adds it to
/// the folder list so the wallpapers join the rotation.
enum WallpaperDownloadFolder {
    static var url: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? SettingsManager.defaultSettingsDirectory
        return pictures.appendingPathComponent("Wallpaper Selector", isDirectory: true)
    }
}

/// Downloads wallpapers of the configured sources into one folder.
actor WallpaperDownloadService {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Loader

    init(load: Loader? = nil) {
        self.load = load ?? { request in try await URLSession.shared.data(for: request) }
    }

    /// Downloads at most `count` new wallpapers of every source.
    ///
    /// A file that is already in the folder is kept: a second download adds
    /// the new wallpapers and leaves the old ones alone.
    func downloadWallpapers(
        from sources: [WallpaperSource],
        count: Int,
        into directory: URL,
        now: Date = Date()
    ) async -> WallpaperDownloadSummary {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return WallpaperDownloadSummary(
                saved: 0,
                failures: ["Could not create \(directory.path): \(error.localizedDescription)"]
            )
        }

        var saved = 0
        var failures: [String] = []
        for source in sources {
            do {
                let wallpapers = try await remoteWallpapers(for: source, count: count, now: now)
                var sourceSaved = 0
                for wallpaper in wallpapers where sourceSaved < count {
                    let destination = directory.appendingPathComponent(wallpaper.fileName)
                    if FileManager.default.fileExists(atPath: destination.path) { continue }
                    try await downloadImage(wallpaper.imageURL, to: destination)
                    sourceSaved += 1
                }
                saved += sourceSaved
            } catch {
                failures.append("\(source.label): \(error.localizedDescription)")
            }
        }
        return WallpaperDownloadSummary(saved: saved, failures: failures)
    }

    /// The wallpapers the source offers right now, for the browser.
    func remoteWallpapers(
        for source: WallpaperSource,
        count: Int,
        now: Date = Date()
    ) async throws -> [RemoteWallpaper] {
        var seen = Set<String>()
        var wallpapers: [RemoteWallpaper] = []
        for candidate in WallpaperSourceAPI.requests(for: source, count: count, now: now) {
            guard wallpapers.count < count else { break }
            let (data, response) = try await load(candidate.request)
            try Self.check(response, url: candidate.request.url)
            let parsed = try WallpaperSourceAPI.wallpapers(
                for: source,
                from: data,
                dayLabel: candidate.dayLabel
            )
            for wallpaper in parsed where wallpapers.count < count {
                guard seen.insert(wallpaper.fileName).inserted else { continue }
                wallpapers.append(wallpaper)
            }
        }
        return wallpapers
    }

    /// Saves one wallpaper into the folder and returns its path.
    ///
    /// A file that is already there is not downloaded again.
    func save(_ wallpaper: RemoteWallpaper, into directory: URL) async throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw WallpaperDownloadError.requestFailed(
                url: directory.path,
                reason: error.localizedDescription
            )
        }
        let destination = directory.appendingPathComponent(wallpaper.fileName)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try await downloadImage(wallpaper.imageURL, to: destination)
        return destination
    }

    private func downloadImage(_ url: URL, to destination: URL) async throws {
        let (data, response) = try await load(URLRequest(url: url))
        try Self.check(response, url: url)
        guard let http = response as? HTTPURLResponse,
              let contentType = http.value(forHTTPHeaderField: "Content-Type"),
              contentType.hasPrefix("image/"),
              !data.isEmpty
        else {
            throw WallpaperDownloadError.notAnImage(url)
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func check(_ response: URLResponse?, url: URL?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WallpaperDownloadError.requestFailed(
                url: url?.absoluteString ?? "",
                reason: "no HTTP response"
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WallpaperDownloadError.requestFailed(
                url: url?.absoluteString ?? "",
                reason: "HTTP \(http.statusCode)"
            )
        }
    }
}
