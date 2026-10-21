import XCTest
@testable import WallpaperSelector

final class AllSpacesApplierTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AllSpacesApplierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The store as it was measured on the Mac the feature was built for.
    private func writeStore() throws -> URL {
        let url = directory.appendingPathComponent("Store/Index.plist")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let container: [String: Any] = [
            "Type": "individual",
            "Desktop": try slot(),
        ]
        let store: [String: Any] = [
            "AllSpacesAndDisplays": container,
            "SystemDefault": container,
            "Spaces": [String: Any](),
            "Displays": [String: Any](),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        try data.write(to: url)
        return url
    }

    /// The slot of the desktop picture.
    private func slot() throws -> [String: Any] {
        [
            "LastSet": Date(timeIntervalSince1970: 1_700_000_000),
            "LastUse": Date(timeIntervalSince1970: 1_700_000_000),
            "Content": [
                "Choices": [[
                    "Provider": "com.apple.wallpaper.choice.image",
                    "Files": [Any](),
                    "Configuration": try PropertyListSerialization.data(
                        fromPropertyList: [
                            "type": "imageFile",
                            "url": ["relative": "file:///Users/Zeb/Pictures/Wallpapers/7.jpg"],
                        ],
                        format: .binary,
                        options: 0
                    ),
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": try PropertyListSerialization.data(
                    fromPropertyList: [
                        "values": ["placement": ["picker": ["_0": ["id": "Crop"]]]],
                    ],
                    format: .binary,
                    options: 0
                ),
            ],
        ]
    }

    private func writeWallpaper(named name: String = "New.jpg") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("wallpaper".utf8).write(to: url)
        return url
    }

    private var backupURL: URL {
        directory.appendingPathComponent("Backup/WallpaperIndex.plist.backup")
    }

    @MainActor
    func testTheWallpaperIsPutOnEverySpace() throws {
        let storeURL = try writeStore()
        let imageURL = try writeWallpaper()
        var restartCount = 0
        var reportedError: String?
        var reportedSuccess = false

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )
        applier.onError = { reportedError = $0 }
        applier.onApplied = { reportedSuccess = true }

        applier.apply(imageURL)

        XCTAssertNil(reportedError)
        XCTAssertTrue(reportedSuccess)
        XCTAssertEqual(restartCount, 1)
        let store = try WallpaperStore().read(at: storeURL)
        XCTAssertEqual(
            WallpaperStore().wallpaperURL(in: store)?.standardizedFileURL.path,
            imageURL.standardizedFileURL.path
        )
    }

    @MainActor
    func testTheBackupIsTakenOnceAndIsNeverOverwritten() throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let first = try writeWallpaper(named: "First.jpg")
        let second = try writeWallpaper(named: "Second.jpg")
        var restartCount = 0

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )
        applier.apply(first)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)

        applier.apply(second)
        XCTAssertEqual(restartCount, 2)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
    }

    @MainActor
    func testAMissingStoreIsReportedAsAMacThatNeedsANewerMacOS() throws {
        let imageURL = try writeWallpaper()
        var restartCount = 0
        var reportedError: String?

        let applier = AllSpacesApplier(
            storeURL: directory.appendingPathComponent("Store/Index.plist"),
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )
        applier.onError = { reportedError = $0 }

        applier.apply(imageURL)

        XCTAssertEqual(restartCount, 0)
        let message = try XCTUnwrap(reportedError)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
        XCTAssertTrue(message.contains("macOS 14"), message)
    }

    @MainActor
    func testAMissingWallpaperIsReported() throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        var restartCount = 0
        var reportedError: String?

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )
        applier.onError = { reportedError = $0 }

        applier.apply(directory.appendingPathComponent("Missing.jpg"))

        XCTAssertEqual(restartCount, 0)
        XCTAssertNotNil(reportedError)
        XCTAssertEqual(try Data(contentsOf: storeURL), before)
    }

    @MainActor
    func testTheStoreIsWrittenAgainWhenTheAgentOverwritesIt() throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0
        var reportedError: String?

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: {
                restartCount += 1
                if restartCount == 1 {
                    // The agent writes the store from its own memory.
                    try? original.write(to: storeURL)
                }
            }
        )
        applier.onError = { reportedError = $0 }

        applier.apply(imageURL)

        XCTAssertEqual(restartCount, 2)
        XCTAssertNil(reportedError)
        let store = try WallpaperStore().read(at: storeURL)
        XCTAssertEqual(
            WallpaperStore().wallpaperURL(in: store)?.standardizedFileURL.path,
            imageURL.standardizedFileURL.path
        )
    }

    @MainActor
    func testTheApplyFailsWhenTheAgentKeepsOverwritingTheStore() throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0
        var reportedError: String?

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: {
                restartCount += 1
                try? original.write(to: storeURL)
            }
        )
        applier.onError = { reportedError = $0 }

        applier.apply(imageURL)

        XCTAssertEqual(restartCount, 3)
        let message = try XCTUnwrap(reportedError)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
    }

    @MainActor
    func testABackupThatCannotBeWrittenStopsTheWrite() throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0
        var reportedError: String?

        // A file stands where the folder of the backup should be.
        let blocked = directory.appendingPathComponent("Blocked")
        try Data("blocked".utf8).write(to: blocked)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: blocked.appendingPathComponent("WallpaperIndex.plist.backup"),
            restartAgent: { restartCount += 1 }
        )
        applier.onError = { reportedError = $0 }

        applier.apply(imageURL)

        XCTAssertEqual(restartCount, 0)
        XCTAssertNotNil(reportedError)
        XCTAssertEqual(try Data(contentsOf: storeURL), before)
    }

    @MainActor
    func testTheBackupLivesInTheFolderOfTheApp() {
        XCTAssertEqual(
            AllSpacesApplier.defaultBackupURL.path,
            NSHomeDirectory() + "/Library/Application Support/WallpaperSelector/WallpaperIndex.plist.backup"
        )
    }
}
