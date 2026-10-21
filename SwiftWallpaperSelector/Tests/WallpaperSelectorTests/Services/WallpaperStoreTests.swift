import XCTest
@testable import WallpaperSelector

/// The store as it was measured on the Mac the feature was built for: a
/// global container with the type `individual` and the slots `Desktop` and
/// `Idle`, a `SystemDefault` that mirrors it and empty `Spaces` and
/// `Displays` containers.
private enum StoreFixture {
    static let imagePath = "/Users/Zeb/Pictures/Wallpapers/7.jpg"
    static let idlePath = "/Users/Zeb/Pictures/Wallpapers/apple_00_3840x2160.png"

    static func nestedData(_ payload: Any) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
    }

    static func configuration(path: String) -> Data {
        nestedData(["type": "imageFile", "url": ["relative": "file://\(path)"]])
    }

    /// The option values of a wallpaper that fills the screen.
    ///
    /// The idle wallpaper carries a colour block as well, which the desktop
    /// wallpaper does not have.
    static func optionValues(withColor: Bool = false) -> Data {
        var values: [String: Any] = ["placement": ["picker": ["_0": ["id": "Crop"]]]]
        if withColor {
            values["color"] = ["color": ["_0": ["color": [
                "components": [0.25, 0.41, 0.66, 1.0],
                "colorSpace": nestedData("kCGColorSpaceGenericRGB"),
            ]]]]
        }
        return nestedData(["values": values])
    }

    static func slot(path: String, withColor: Bool = false) -> [String: Any] {
        [
            "LastSet": Date(timeIntervalSince1970: 1_700_000_000),
            "LastUse": Date(timeIntervalSince1970: 1_700_000_000),
            "Content": [
                "Choices": [[
                    "Provider": "com.apple.wallpaper.choice.image",
                    "Files": [Any](),
                    "Configuration": configuration(path: path),
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": optionValues(withColor: withColor),
            ],
        ]
    }

    static func container() -> [String: Any] {
        [
            "Type": "individual",
            "Desktop": slot(path: imagePath),
            "Idle": slot(path: idlePath, withColor: true),
        ]
    }

    static func store(spaces: [String: Any] = [:], displays: [String: Any] = [:]) -> [String: Any] {
        [
            "AllSpacesAndDisplays": container(),
            "SystemDefault": container(),
            "Spaces": spaces,
            "Displays": displays,
        ]
    }
}

final class WallpaperStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WallpaperStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeFixture(_ store: [String: Any]) throws -> URL {
        let url = directory.appendingPathComponent("Index.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        try data.write(to: url)
        return url
    }

    private func configuration(of container: [String: Any], slotName: String = "Desktop") throws -> [String: Any] {
        let slot = try XCTUnwrap(container[slotName] as? [String: Any])
        let content = try XCTUnwrap(slot["Content"] as? [String: Any])
        let choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        let choice = try XCTUnwrap(choices.first)
        let data = try XCTUnwrap(choice["Configuration"] as? Data)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func optionValues(of container: [String: Any], slotName: String = "Desktop") throws -> [String: Any] {
        let slot = try XCTUnwrap(container[slotName] as? [String: Any])
        let content = try XCTUnwrap(slot["Content"] as? [String: Any])
        let data = try XCTUnwrap(content["EncodedOptionValues"] as? Data)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func testTheGlobalContainerAndTheSystemDefaultHoldTheWallpaper() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        for key in ["AllSpacesAndDisplays", "SystemDefault"] {
            let container = try XCTUnwrap(store[key] as? [String: Any])
            let configuration = try configuration(of: container)
            XCTAssertEqual(configuration["type"] as? String, "imageFile")
            XCTAssertEqual(
                (configuration["url"] as? [String: String])?["relative"],
                imageURL.absoluteString
            )
        }
    }

    func testTheChoiceOfTheWallpaperIsAnImageFile() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let container = try XCTUnwrap(store["AllSpacesAndDisplays"] as? [String: Any])
        let slot = try XCTUnwrap(container["Desktop"] as? [String: Any])
        let content = try XCTUnwrap(slot["Content"] as? [String: Any])
        let choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        let choice = try XCTUnwrap(choices.first)
        XCTAssertEqual(choice["Provider"] as? String, "com.apple.wallpaper.choice.image")
        XCTAssertEqual((choice["Files"] as? [Any])?.count, 0)
    }

    func testTheWallpaperFillsTheScreen() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let container = try XCTUnwrap(store["AllSpacesAndDisplays"] as? [String: Any])
        let optionValues = try optionValues(of: container)
        let values = try XCTUnwrap(optionValues["values"] as? [String: Any])
        let placement = try XCTUnwrap(values["placement"] as? [String: Any])
        let picker = try XCTUnwrap(placement["picker"] as? [String: Any])
        let first = try XCTUnwrap(picker["_0"] as? [String: Any])
        XCTAssertEqual(first["id"] as? String, "Crop")
    }

    func testTheIdleSlotIsLeftAlone() throws {
        let url = try writeFixture(StoreFixture.store())
        let before = try WallpaperStore().read(at: url)
        let idleBefore = try XCTUnwrap(before["AllSpacesAndDisplays"] as? [String: Any])["Idle"] as? [String: Any]
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let idleAfter = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])["Idle"] as? [String: Any]
        XCTAssertEqual(idleBefore?["Content"] as? NSDictionary, idleAfter?["Content"] as? NSDictionary)
    }

    func testTheSlotSaysThatTheWallpaperWasSetNow() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")
        let before = Date()

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let container = try XCTUnwrap(store["AllSpacesAndDisplays"] as? [String: Any])
        let slot = try XCTUnwrap(container["Desktop"] as? [String: Any])
        let lastSet = try XCTUnwrap(slot["LastSet"] as? Date)
        XCTAssertGreaterThanOrEqual(lastSet, before)
    }

    func testTheFileStaysABinaryPropertyList() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        XCTAssertEqual(format, .binary)
        XCTAssertNotNil(plist as? [String: Any])
    }

    func testTheWallpaperOfASpaceIsUpdated() throws {
        let space: [String: Any] = ["Default": StoreFixture.slot(path: StoreFixture.imagePath)]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let spaces = try XCTUnwrap(store["Spaces"] as? [String: Any])
        let container = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        let configuration = try configuration(of: container, slotName: "Default")
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    func testTheWallpaperOfADisplayOfASpaceIsUpdated() throws {
        let display: [String: Any] = ["Desktop": StoreFixture.slot(path: StoreFixture.imagePath)]
        let space: [String: Any] = ["Displays": ["display-uuid": display]]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let spaces = try XCTUnwrap(store["Spaces"] as? [String: Any])
        let spaceContainer = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        let displays = try XCTUnwrap(spaceContainer["Displays"] as? [String: Any])
        let container = try XCTUnwrap(displays["display-uuid"] as? [String: Any])
        let configuration = try configuration(of: container)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    func testTheWallpaperOfADisplayIsUpdated() throws {
        let display: [String: Any] = ["Desktop": StoreFixture.slot(path: StoreFixture.imagePath)]
        let url = try writeFixture(StoreFixture.store(displays: ["display-uuid": display]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let displays = try XCTUnwrap(store["Displays"] as? [String: Any])
        let container = try XCTUnwrap(displays["display-uuid"] as? [String: Any])
        let configuration = try configuration(of: container)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    /// A container whose keys make no sense stops the write.
    func testAContainerThatIsNotUnderstoodStopsTheWrite() throws {
        let space: [String: Any] = ["Something": "else"]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("The write should stop on a shape that is not understood: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// A container that holds no wallpaper is skipped, so a Space without a
    /// wallpaper does not stop the write.
    func testAContainerThatHoldsNoWallpaperIsSkipped() throws {
        let space: [String: Any] = ["Type": "individual"]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let spaces = try XCTUnwrap(store["Spaces"] as? [String: Any])
        let container = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        XCTAssertEqual(container["Type"] as? String, "individual")
        XCTAssertNil(container["Desktop"], "The container without a wallpaper is not written")
        let global = try XCTUnwrap(store["AllSpacesAndDisplays"] as? [String: Any])
        let configuration = try configuration(of: global)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    /// The store must survive a crash: the file is flushed before the
    /// rename and the folder after it.
    func testTheStoreIsFlushedBeforeAndAfterTheRename() throws {
        var flushedFiles: [String] = []
        var flushedFolders: [String] = []
        var store = WallpaperStore()
        store.flushFile = { url in flushedFiles.append(url.lastPathComponent) }
        store.flushFolder = { url in flushedFolders.append(url.lastPathComponent) }
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try store.setWallpaper(imageURL, inStoreAt: url)

        XCTAssertEqual(flushedFiles.count, 1, "The file must be flushed before the rename")
        XCTAssertTrue(
            (flushedFiles.first ?? "").hasSuffix(".tmp"),
            "The file that is flushed is the temporary file: \(flushedFiles)"
        )
        XCTAssertEqual(
            flushedFolders,
            [url.deletingLastPathComponent().lastPathComponent],
            "The folder must be flushed after the rename"
        )
    }

    /// The store is written to a temporary file and renamed over the old
    /// one, so no temporary file is left behind.
    func testTheWriteLeavesNoTemporaryFileBehind() throws {
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let files = try FileManager.default.contentsOfDirectory(
            atPath: url.deletingLastPathComponent().path
        )
        XCTAssertEqual(files, ["Index.plist"])
    }

    /// A rename that fails must not leave the temporary file behind.
    func testAFailedRenameLeavesNoTemporaryFileBehind() throws {
        // A folder stands where the store should be, so the rename fails.
        let url = directory.appendingPathComponent("Index.plist")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        XCTAssertThrowsError(try WallpaperStore().write(StoreFixture.store(), to: url))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["Index.plist"])
    }

    func testAnUnknownKeyOfTheStoreStopsTheWrite() throws {
        var store = StoreFixture.store()
        store["SomethingNew"] = ["Type": "individual"]
        let url = try writeFixture(store)
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("The write should stop on a shape that is not understood: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testTheSlotIsFoundByItsPresenceAndNotByTheType() throws {
        // The container holds the type `individual` and the slot `Linked`.
        // The slot that is there is the one that is written.
        var container = StoreFixture.container()
        container["Linked"] = container.removeValue(forKey: "Desktop")
        var store = StoreFixture.store()
        store["AllSpacesAndDisplays"] = container
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let patched = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertNil(patched["Desktop"])
        let configuration = try configuration(of: patched, slotName: "Linked")
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    func testAMissingStoreIsReported() {
        let url = directory.appendingPathComponent("DoesNotExist.plist")

        XCTAssertThrowsError(try WallpaperStore().read(at: url)) { error in
            guard case WallpaperStoreError.storeNotFound = error else {
                return XCTFail("A missing store should be reported: \(error)")
            }
        }
    }

    func testAFileThatIsNoPropertyListIsReported() throws {
        let url = directory.appendingPathComponent("Index.plist")
        try Data("not a property list".utf8).write(to: url)

        XCTAssertThrowsError(try WallpaperStore().read(at: url)) { error in
            guard case WallpaperStoreError.notAPropertyList = error else {
                return XCTFail("A file that is no property list should be reported: \(error)")
            }
        }
    }

    func testTheStoreOfTheAgentIsTheKnownPath() {
        XCTAssertEqual(
            WallpaperStore.defaultStoreURL.path,
            NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        )
    }
}
