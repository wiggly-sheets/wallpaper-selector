import XCTest
@testable import WallpaperSelector

final class WallpaperDownloadServiceTests: XCTestCase {
    private func createTempFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func response(url: URL, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
    }

    /// The field of the response is not the field the file has: an item
    /// without a path is not a wallpaper, and the extension has to follow the
    /// reported type so the app can discover the file.
    func testWallhavenPayloadBecomesFilesWithTheReportedExtension() throws {
        let data = Data(#"""
        {"data":[
        {"id":"abc123","path":"https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg","file_type":"image/jpeg","thumbs":{"large":"https://th.wallhaven.cc/lg/ab/abc123.jpg"}},
        {"id":"def456","path":"https://w.wallhaven.cc/full/de/wallhaven-def456.png","file_type":"image/png"},
        {"id":"nopath","file_type":"image/jpeg"}
        ]}
        """#.utf8)

        let wallpapers = try WallpaperSourceAPI.wallhavenWallpapers(from: data)

        XCTAssertEqual(wallpapers.map { $0.fileName }, ["wallhaven-abc123.jpg", "wallhaven-def456.png"])
        XCTAssertEqual(wallpapers.first?.imageURL.absoluteString, "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg")
        XCTAssertEqual(wallpapers.first?.source, .wallhaven)
        // The browser grid shows the thumbnail: a full-size image would take
        // too long to load for a grid.
        XCTAssertEqual(wallpapers.first?.thumbnailURL?.absoluteString, "https://th.wallhaven.cc/lg/ab/abc123.jpg")
    }

    /// The archive returns a path without a host and a 1920x1080 image, so
    /// the app has to ask for the UHD variant and name the file by the day.
    func testBingPayloadAsksForTheUhdImageAndNamesTheFileByTheDay() throws {
        let data = Data(#"""
        {"images":[{"startdate":"20261123","urlbase":"/th?id=OHR.FallSweden"}]}
        """#.utf8)

        let wallpapers = try WallpaperSourceAPI.bingWallpapers(from: data)

        XCTAssertEqual(wallpapers.count, 1)
        XCTAssertEqual(wallpapers[0].fileName, "bing-20261123.jpg")
        XCTAssertEqual(wallpapers[0].imageURL.absoluteString, "https://www.bing.com/th?id=OHR.FallSweden_UHD.jpg")
    }

    /// The feed has one image per day, and the file name carries the day the
    /// feed was asked for so a second download of the same day finds the file.
    /// A portrait image is not a desktop wallpaper.
    func testWikimediaPayloadUsesTheDayAndSkipsAPortraitImage() throws {
        let landscape = Data(#"""
        {"image":{"image":{"source":"https://upload.wikimedia.org/wikipedia/commons/a/b/Landscape.jpg","width":3840,"height":2160},"thumbnail":{"source":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Landscape.jpg/640px-Landscape.jpg"}}}
        """#.utf8)
        let portrait = Data(#"""
        {"image":{"image":{"source":"https://upload.wikimedia.org/wikipedia/commons/c/d/Portrait.jpg","width":2160,"height":3840}}}
        """#.utf8)

        let wallpapers = try WallpaperSourceAPI.wikimediaWallpapers(from: landscape, dayLabel: "2026-11-22")

        XCTAssertEqual(wallpapers.map { $0.fileName }, ["wikimedia-2026-11-22.jpg"])
        XCTAssertEqual(wallpapers.first?.imageURL.path, "/wikipedia/commons/a/b/Landscape.jpg")
        XCTAssertEqual(wallpapers.first?.source, .wikimedia)
        XCTAssertEqual(
            wallpapers.first?.thumbnailURL?.absoluteString,
            "https://upload.wikimedia.org/wikipedia/commons/thumb/a/b/Landscape.jpg/640px-Landscape.jpg"
        )
        XCTAssertTrue(try WallpaperSourceAPI.wikimediaWallpapers(from: portrait, dayLabel: "2026-11-22").isEmpty)
    }

    /// The download is incremental: the second one must not fetch or
    /// overwrite a file that is already in the folder.
    func testDownloadWritesTheWallpapersAndKeepsTheExistingFiles() async throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let imageData = Data("image".utf8)
        let service = WallpaperDownloadService { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "wallhaven.cc" {
                let payload = #"""
                {"data":[{"id":"abc123","path":"https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg","file_type":"image/jpeg"}]}
                """#
                return (Data(payload.utf8), Self.response(url: url, contentType: "application/json"))
            }
            return (imageData, Self.response(url: url, contentType: "image/jpeg"))
        }

        let first = await service.downloadWallpapers(from: [.wallhaven], count: 1, into: folder)

        XCTAssertEqual(first, WallpaperDownloadSummary(saved: 1, failures: []))
        let file = folder.appendingPathComponent("wallhaven-abc123.jpg")
        XCTAssertEqual(try Data(contentsOf: file), imageData)

        let second = await service.downloadWallpapers(from: [.wallhaven], count: 1, into: folder)

        XCTAssertEqual(second.saved, 0)
        XCTAssertEqual(second.failures, [])
        XCTAssertEqual(try Data(contentsOf: file), imageData)
    }

    /// One source must not stop the other ones, and the failure has to name
    /// the source so the message means something to the user.
    func testAFailedSourceIsReportedAndTheOtherSourceIsStillDownloaded() async throws {
        let folder = try createTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let imageData = Data("image".utf8)
        let service = WallpaperDownloadService { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "wallhaven.cc" {
                throw URLError(.cannotConnectToHost)
            }
            let payload = #"""
            {"images":[{"startdate":"20261123","urlbase":"/th?id=OHR.FallSweden"}]}
            """#
            if url.query?.contains("format=js") == true {
                return (Data(payload.utf8), Self.response(url: url, contentType: "application/json"))
            }
            return (imageData, Self.response(url: url, contentType: "image/jpeg"))
        }

        let summary = await service.downloadWallpapers(from: [.wallhaven, .bingDaily], count: 1, into: folder)

        XCTAssertEqual(summary.saved, 1)
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertTrue(summary.failures[0].hasPrefix("Wallhaven: "))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("bing-20261123.jpg").path)
        )
    }
}
