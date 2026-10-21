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

    /// The store as it was measured on the Mac the feature was built on.
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

    /// Puts the wallpaper on every Space and waits for the work.
    ///
    /// The work runs off the main actor, so the test waits for the report
    /// instead of reading the state right away. The report is the failure
    /// message, or `nil` when the wallpaper reached every Space.
    @MainActor
    private func apply(
        _ applier: AllSpacesApplier,
        _ imageURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> String? {
        let finished = expectation(description: "the apply finished")
        var failure: String?
        applier.onError = { message in
            failure = message
            finished.fulfill()
        }
        applier.onApplied = { finished.fulfill() }

        applier.apply(imageURL)

        await fulfillment(of: [finished], timeout: 10)
        return failure
    }

    @MainActor
    func testTheWallpaperIsPutOnEverySpace() async throws {
        let storeURL = try writeStore()
        let imageURL = try writeWallpaper()
        var restartCount = 0

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )

        let failure = await apply(applier, imageURL)

        XCTAssertNil(failure)
        XCTAssertEqual(restartCount, 1)
        let store = try WallpaperStore().read(at: storeURL)
        XCTAssertEqual(
            WallpaperStore().wallpaperURL(in: store)?.standardizedFileURL.path,
            imageURL.standardizedFileURL.path
        )
    }

    @MainActor
    func testTheBackupIsTakenOnceAndIsNeverOverwritten() async throws {
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
        _ = await apply(applier, first)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)

        _ = await apply(applier, second)
        XCTAssertEqual(restartCount, 2)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
    }

    @MainActor
    func testAMissingStoreIsReportedAsAMacThatNeedsANewerMacOS() async throws {
        let imageURL = try writeWallpaper()
        var restartCount = 0

        let applier = AllSpacesApplier(
            storeURL: directory.appendingPathComponent("Store/Index.plist"),
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(restartCount, 0)
        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
        XCTAssertTrue(message.contains("macOS 14"), message)
    }

    @MainActor
    func testAMissingWallpaperIsReported() async throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        var restartCount = 0

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: { restartCount += 1 }
        )

        let failure = await apply(applier, directory.appendingPathComponent("Missing.jpg"))

        XCTAssertEqual(restartCount, 0)
        XCTAssertNotNil(failure)
        XCTAssertEqual(try Data(contentsOf: storeURL), before)
    }

    @MainActor
    func testTheStoreIsWrittenAgainWhenTheAgentOverwritesIt() async throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0

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

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(restartCount, 2)
        XCTAssertNil(failure)
        let store = try WallpaperStore().read(at: storeURL)
        XCTAssertEqual(
            WallpaperStore().wallpaperURL(in: store)?.standardizedFileURL.path,
            imageURL.standardizedFileURL.path
        )
    }

    @MainActor
    func testTheApplyFailsWhenTheAgentKeepsOverwritingTheStore() async throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            restartAgent: {
                restartCount += 1
                try? original.write(to: storeURL)
            }
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(restartCount, 3)
        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
    }

    @MainActor
    func testABackupThatCannotBeWrittenStopsTheWrite() async throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        var restartCount = 0

        // A file stands where the folder of the backup should be.
        let blocked = directory.appendingPathComponent("Blocked")
        try Data("blocked".utf8).write(to: blocked)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: blocked.appendingPathComponent("WallpaperIndex.plist.backup"),
            restartAgent: { restartCount += 1 }
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(restartCount, 0)
        XCTAssertNotNil(failure)
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
