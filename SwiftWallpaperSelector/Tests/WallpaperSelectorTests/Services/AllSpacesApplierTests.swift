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
    private func writeStore(space: [String: Any]? = nil) throws -> URL {
        let url = directory.appendingPathComponent("Store/Index.plist")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let container: [String: Any] = [
            "Type": "individual",
            "Desktop": try slot(),
        ]
        var spaces: [String: Any] = [String: Any]()
        if let space {
            spaces["space-uuid"] = space
        }
        let store: [String: Any] = [
            "AllSpacesAndDisplays": container,
            "SystemDefault": container,
            "Spaces": spaces,
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
        var message: String?
        applier.onResult = { result in
            if case .failure(let failure) = result {
                message = failure.errorDescription
            }
            finished.fulfill()
        }

        applier.apply(imageURL)

        await fulfillment(of: [finished], timeout: 10)
        return message
    }

    @MainActor
    func testTheWallpaperIsPutOnEverySpace() async throws {
        let storeURL = try writeStore()
        let imageURL = try writeWallpaper()
        let agent = FakeWallpaperAgent(storeURL: storeURL)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        XCTAssertNil(failure)
        XCTAssertEqual(agent.restartCount, 1)
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
        let agent = FakeWallpaperAgent(storeURL: storeURL)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )
        _ = await apply(applier, first)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)

        _ = await apply(applier, second)
        XCTAssertEqual(agent.restartCount, 2)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
    }

    @MainActor
    func testAMissingStoreIsReportedAsAMacThatNeedsANewerMacOS() async throws {
        let imageURL = try writeWallpaper()
        let agent = FakeWallpaperAgent(storeURL: directory)

        let applier = AllSpacesApplier(
            storeURL: directory.appendingPathComponent("Store/Index.plist"),
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(agent.restartCount, 0)
        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
        XCTAssertTrue(message.contains("macOS 14"), message)
    }

    @MainActor
    func testAMissingWallpaperIsReported() async throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        let agent = FakeWallpaperAgent(storeURL: storeURL)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, directory.appendingPathComponent("Missing.jpg"))

        XCTAssertEqual(agent.restartCount, 0)
        XCTAssertNotNil(failure)
        XCTAssertEqual(try Data(contentsOf: storeURL), before)
    }

    @MainActor
    func testTheStoreIsWrittenAgainWhenTheAgentOverwritesIt() async throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        let agent = FakeWallpaperAgent(storeURL: storeURL, staleContent: original)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(agent.restartCount, 2)
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
        let agent = FakeWallpaperAgent(storeURL: storeURL, staleContent: original, everyRestart: true)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(agent.restartCount, 3)
        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains(imageURL.lastPathComponent), message)
        XCTAssertTrue(message.contains("every Space"), message)
    }

    /// The agent of macOS writes the store from its own memory a moment
    /// after it was killed. The apply must not report success before the
    /// new agent came back, because the wallpaper would be gone a moment
    /// later.
    @MainActor
    func testTheApplyWaitsForTheAgentToComeBack() async throws {
        let storeURL = try writeStore()
        let original = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        let wroteStore = expectation(description: "the agent wrote the store")
        let agent = FakeWallpaperAgent(storeURL: storeURL, staleContent: original) {
            wroteStore.fulfill()
        }

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)
        await fulfillment(of: [wroteStore], timeout: 5)

        XCTAssertNil(failure)
        let store = try WallpaperStore().read(at: storeURL)
        XCTAssertEqual(
            WallpaperStore().wallpaperURL(in: store)?.standardizedFileURL.path,
            imageURL.standardizedFileURL.path,
            "The store must hold the wallpaper after the agent came back"
        )
    }

    /// Without a running agent there is nothing that could read the store the
    /// app wrote, so the apply cannot be proven. The app has to report that
    /// instead of reporting a success it cannot prove.
    @MainActor
    func testTheApplyFailsWhenNoAgentIsRunning() async throws {
        let storeURL = try writeStore()
        let imageURL = try writeWallpaper()
        let agent = WallpaperAgent(
            restart: {},
            identifiers: { [] },
            restartTimeout: 1,
            settleTime: 0.01
        )

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent
        )

        let failure = await apply(applier, imageURL)

        let message = try XCTUnwrap(
            failure,
            "The apply must not report a success when no agent could read the store"
        )
        XCTAssertTrue(message.contains("agent"), message)
        XCTAssertTrue(message.contains("not running"), message)
    }

    /// A Space whose wallpaper sits in a slot the app does not write keeps
    /// its old wallpaper. The apply has to say so instead of claiming that
    /// the wallpaper is on every Space.
    @MainActor
    func testASpaceThatKeepsItsWallpaperIsReported() async throws {
        let storeURL = try writeStore(space: [
            "Type": "individual",
            "Video": try slot(),
        ])
        let imageURL = try writeWallpaper()
        let agent = FakeWallpaperAgent(storeURL: storeURL)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains("every Space"), message)
        XCTAssertTrue(
            message.contains("Video"),
            "The Space that keeps its wallpaper has to be named: \(message)"
        )
    }

    /// The agent never comes back: the wait has to give up, or the work of
    /// the applier spins for ever.
    @MainActor
    func testTheApplyGivesUpWhenTheAgentNeverComesBack() async throws {
        let storeURL = try writeStore()
        let imageURL = try writeWallpaper()
        let agent = WallpaperAgent(
            restart: {},
            identifiers: { [42] },
            restartTimeout: 0.3,
            settleTime: 0.01
        )

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: backupURL,
            agent: agent
        )

        let started = Date()
        let failure = await apply(applier, imageURL)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 10, "The wait has to give up instead of spinning")
        let message = try XCTUnwrap(failure)
        XCTAssertTrue(message.contains("agent"), message)
    }

    @MainActor
    func testABackupThatCannotBeWrittenStopsTheWrite() async throws {
        let storeURL = try writeStore()
        let before = try Data(contentsOf: storeURL)
        let imageURL = try writeWallpaper()
        let agent = FakeWallpaperAgent(storeURL: storeURL)

        // A file stands where the folder of the backup should be.
        let blocked = directory.appendingPathComponent("Blocked")
        try Data("blocked".utf8).write(to: blocked)

        let applier = AllSpacesApplier(
            storeURL: storeURL,
            backupURL: blocked.appendingPathComponent("WallpaperIndex.plist.backup"),
            agent: agent.wallpaperAgent
        )

        let failure = await apply(applier, imageURL)

        XCTAssertEqual(agent.restartCount, 0)
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

/// The wallpaper agent of the tests.
///
/// The agent is not a real process. It has an identifier that changes when
/// it is restarted, so the applier sees that a new agent runs. The agent
/// can write the store from its own memory a moment after the restart, like
/// the agent of macOS does.
final class FakeWallpaperAgent: @unchecked Sendable {
    private let lock = NSLock()
    private var identifier = 1
    private var running = true
    private var wroteStore = false

    /// The number of times the agent was restarted.
    private(set) var restartCount = 0

    /// The store the agent writes when it comes back.
    private let storeURL: URL
    /// The content the agent writes when it comes back.
    private let staleContent: Data?
    /// Whether the agent writes the store on every restart or only on the
    /// first one.
    private let everyRestart: Bool
    /// Called when the agent wrote the store.
    private let onWrite: () -> Void

    init(
        storeURL: URL,
        staleContent: Data? = nil,
        everyRestart: Bool = false,
        onWrite: @escaping () -> Void = {}
    ) {
        self.storeURL = storeURL
        self.staleContent = staleContent
        self.everyRestart = everyRestart
        self.onWrite = onWrite
    }

    /// The agent as the applier uses it.
    var wallpaperAgent: WallpaperAgent {
        WallpaperAgent(
            restart: { [self] in restart() },
            identifiers: { [self] in currentIdentifiers() },
            restartTimeout: 2,
            settleTime: 0.02
        )
    }

    /// The identifiers of the agent processes that run.
    func currentIdentifiers() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return running ? [identifier] : []
    }

    /// The agent is killed and comes back a moment later.
    func restart() {
        lock.lock()
        running = false
        restartCount += 1
        let next = identifier + 1
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [self] in
            lock.lock()
            let writes = staleContent != nil && (everyRestart || !wroteStore)
            if writes { wroteStore = true }
            lock.unlock()

            if writes {
                try? staleContent?.write(to: storeURL)
                onWrite()
            }

            lock.lock()
            identifier = next
            running = true
            lock.unlock()
        }
    }
}
