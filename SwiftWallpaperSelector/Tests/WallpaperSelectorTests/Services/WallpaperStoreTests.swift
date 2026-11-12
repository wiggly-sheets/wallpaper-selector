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

    static func container(wallpaperPath: String = imagePath) -> [String: Any] {
        [
            "Type": "individual",
            "Desktop": slot(path: wallpaperPath),
            "Idle": slot(path: idlePath, withColor: true),
        ]
    }

    /// A `linked` container, with a stale `Desktop` slot that macOS does not
    /// read.
    static func linkedContainer(wallpaperPath: String = imagePath) -> [String: Any] {
        [
            "Type": "linked",
            "Desktop": slot(path: wallpaperPath),
            "Linked": slot(path: wallpaperPath),
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
        let space: [String: Any] = ["Default": StoreFixture.container()]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let spaces = try XCTUnwrap(store["Spaces"] as? [String: Any])
        let spaceRecord = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        let container = try XCTUnwrap(spaceRecord["Default"] as? [String: Any])
        let configuration = try configuration(of: container)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    /// A Space record that carries a wallpaper slot of its own is patched as
    /// a container as well, without dropping the containers it already has.
    func testASpaceRecordWithItsOwnSlotAlsoPatchesItsDefaultContainer() throws {
        let space: [String: Any] = [
            "Type": "individual",
            "Desktop": StoreFixture.slot(path: StoreFixture.imagePath),
            "Default": StoreFixture.container(),
        ]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let store = try WallpaperStore().read(at: url)
        let spaces = try XCTUnwrap(store["Spaces"] as? [String: Any])
        let record = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        for container in [
            record,
            try XCTUnwrap(record["Default"] as? [String: Any]),
        ] {
            let configuration = try configuration(of: container)
            XCTAssertEqual(
                (configuration["url"] as? [String: String])?["relative"],
                imageURL.absoluteString
            )
        }
    }

    func testTheWallpaperOfADisplayOfASpaceIsUpdated() throws {
        let display: [String: Any] = StoreFixture.container()
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
        let display: [String: Any] = StoreFixture.container()
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
        let display: [String: Any] = ["Something": "else"]
        let url = try writeFixture(StoreFixture.store(displays: ["display-uuid": display]))
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("The write should stop on a shape that is not understood: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// A Space record that this app does not understand stops the write, so
    /// the file keeps the content it had.
    func testAnUnknownSpaceRecordStopsTheWrite() throws {
        let space: [String: Any] = ["Something": "else"]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("The write should stop on a Space that is not understood: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// A Space record with an `Idle` slot of its own has no wallpaper slot
    /// that macOS reads, so it is not understood either.
    func testASpaceRecordWithOnlyAnIdleSlotStopsTheWrite() throws {
        let space: [String: Any] = ["Idle": StoreFixture.slot(path: StoreFixture.idlePath)]
        let url = try writeFixture(StoreFixture.store(spaces: ["space-uuid": space]))
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("An idle-only Space has no wallpaper slot: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// The global container is the one macOS always reads, so a store
    /// without it is not understood.
    func testAStoreWithoutTheGlobalContainerStopsTheWrite() throws {
        var store = StoreFixture.store()
        store.removeValue(forKey: "AllSpacesAndDisplays")
        let url = try writeFixture(store)
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("The global container is required: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// The other root containers are optional, and a key that is absent stays
    /// absent.
    func testAStoreWithoutTheOptionalRootContainersIsWrittenAndVerified() throws {
        let store: [String: Any] = ["AllSpacesAndDisplays": StoreFixture.container()]
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        XCTAssertEqual(Set(after.keys), ["AllSpacesAndDisplays"])
        let global = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        let configuration = try configuration(of: global)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
        XCTAssertTrue(WallpaperStore().holdsWallpaper(imageURL, inStoreAt: url))
    }

    /// A root container that is there but is not a map stops the write.
    func testANonDictionaryDisplayRootStopsTheWrite() throws {
        var store = StoreFixture.store()
        store["Displays"] = "not a map"
        let url = try writeFixture(store)
        let before = try Data(contentsOf: url)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)) { error in
            guard case WallpaperStoreError.unexpectedShape = error else {
                return XCTFail("A Displays root that is no map is not understood: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// A throw must not leave the dictionary of the caller half patched.
    func testAFailedWriteLeavesTheStoreInMemoryUnchanged() throws {
        var store = StoreFixture.store(spaces: ["space-uuid": ["Something": "else"]])
        let before = store as NSDictionary
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        XCTAssertThrowsError(try WallpaperStore().setWallpaper(imageURL, in: &store))

        XCTAssertEqual(store as NSDictionary, before)
    }

    /// The verification has to cover every container of the store and not
    /// only the global one: a Space that keeps its old wallpaper is a Space
    /// the wallpaper did not reach.
    func testTheVerificationChecksEveryContainerAndNotOnlyTheGlobalOne() throws {
        let space: [String: Any] = ["Default": StoreFixture.container()]
        var store = StoreFixture.store(spaces: ["space-uuid": space])
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")
        // The global container holds the new wallpaper, the Space holds the
        // old one.
        store["AllSpacesAndDisplays"] = StoreFixture.container(wallpaperPath: imageURL.path)
        let url = try writeFixture(store)

        XCTAssertFalse(
            WallpaperStore().holdsWallpaper(imageURL, inStoreAt: url),
            "A Space that keeps its old wallpaper is a Space the wallpaper did not reach"
        )
    }

    /// The display of a Space is checked as well: a display that keeps the
    /// old wallpaper is a container the wallpaper did not reach.
    func testTheVerificationChecksTheDisplayOfASpace() throws {
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")
        let space: [String: Any] = [
            "Displays": ["display-uuid": StoreFixture.container()],
        ]
        var store = StoreFixture.store(spaces: ["space-uuid": space])
        // Every other container holds the new wallpaper.
        store["AllSpacesAndDisplays"] = StoreFixture.container(wallpaperPath: imageURL.path)
        store["SystemDefault"] = StoreFixture.container(wallpaperPath: imageURL.path)
        let url = try writeFixture(store)

        XCTAssertFalse(
            WallpaperStore().holdsWallpaper(imageURL, inStoreAt: url),
            "A display of a Space that keeps its old wallpaper is a container the wallpaper did not reach"
        )
    }

    /// The store must survive a crash: the file is flushed before the
    /// rename and the folder after it.
    func testTheStoreIsFlushedBeforeAndAfterTheRename() throws {
        var events: [String] = []
        var store = WallpaperStore()
        store.flushFile = { url in events.append("file:\(url.lastPathComponent)") }
        store.renameFile = { source, target in
            events.append("rename")
            return rename(source, target)
        }
        store.flushFolder = { url in events.append("folder:\(url.lastPathComponent)") }
        let url = try writeFixture(StoreFixture.store())
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try store.setWallpaper(imageURL, inStoreAt: url)

        XCTAssertEqual(events.count, 3, "The file is flushed once and the folder once: \(events)")
        XCTAssertTrue(
            (events.first ?? "").hasSuffix(".tmp"),
            "The file that is flushed is the temporary file: \(events)"
        )
        XCTAssertEqual(events[1], "rename", "The rename must come after the flush of the file: \(events)")
        XCTAssertEqual(
            events[2],
            "folder:\(url.deletingLastPathComponent().lastPathComponent)",
            "The folder must be flushed after the rename: \(events)"
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

    /// A root key that this app does not know is preserved, so a store of a
    /// newer macOS version is not changed beyond the wallpaper.
    func testAnUnknownKeyOfTheStoreIsPreserved() throws {
        let unknown: [String: Any] = ["Type": "individual"]
        var store = StoreFixture.store()
        store["SomethingNew"] = unknown
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        XCTAssertEqual(after["SomethingNew"] as? NSDictionary, unknown as NSDictionary)
        let global = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        let configuration = try configuration(of: global)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    /// A linked container writes the `Linked` slot that macOS reads and drops
    /// the `Desktop` slot that was left over.
    func testALinkedContainerGetsALinkedSlotAndLosesItsStaleDesktop() throws {
        var container = StoreFixture.container()
        container["Type"] = "linked"
        container["Linked"] = container["Desktop"]
        var store = StoreFixture.store()
        store["AllSpacesAndDisplays"] = container
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let patched = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertNil(patched["Desktop"], "The stale desktop slot has to be removed")
        let configuration = try configuration(of: patched, slotName: "Linked")
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
    }

    /// Every container that is linked writes `Linked` and loses its stale
    /// `Desktop`, also when it sits in `SystemDefault`, in the `Default` of a
    /// Space or in a Display of a Space.
    func testALinkedSystemDefaultSpaceDefaultAndSpaceDisplayGetALinkedSlot() throws {
        let space: [String: Any] = [
            "Default": StoreFixture.linkedContainer(),
            "Displays": ["display-uuid": StoreFixture.linkedContainer()],
        ]
        var store = StoreFixture.store(spaces: ["space-uuid": space])
        store["SystemDefault"] = StoreFixture.linkedContainer()
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let systemDefault = try XCTUnwrap(after["SystemDefault"] as? [String: Any])
        let spaces = try XCTUnwrap(after["Spaces"] as? [String: Any])
        let record = try XCTUnwrap(spaces["space-uuid"] as? [String: Any])
        let spaceDefault = try XCTUnwrap(record["Default"] as? [String: Any])
        let displays = try XCTUnwrap(record["Displays"] as? [String: Any])
        let display = try XCTUnwrap(displays["display-uuid"] as? [String: Any])
        for container in [systemDefault, spaceDefault, display] {
            XCTAssertNil(container["Desktop"], "The stale desktop slot has to be removed")
            let configuration = try configuration(of: container, slotName: "Linked")
            XCTAssertEqual(
                (configuration["url"] as? [String: String])?["relative"],
                imageURL.absoluteString
            )
        }
    }

    /// An individual container writes the `Desktop` slot and leaves a stray
    /// `Linked` slot alone, because macOS does not read it.
    func testAnIndividualContainerKeepsAStrayLinkedSlot() throws {
        var container = StoreFixture.container()
        container["Linked"] = StoreFixture.slot(path: StoreFixture.imagePath)
        let linkedBefore = container["Linked"] as? NSDictionary
        var store = StoreFixture.store()
        store["AllSpacesAndDisplays"] = container
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let patched = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        let configuration = try configuration(of: patched)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
        XCTAssertEqual(patched["Linked"] as? NSDictionary, linkedBefore)
    }

    /// A container whose type is not `linked` still uses the `Desktop` slot.
    /// A container with no wallpaper yet is not skipped.
    func testAContainerWithTheTypeIdleAndNoDesktopSlotGetsADesktopSlot() throws {
        var store = StoreFixture.store()
        store["AllSpacesAndDisplays"] = ["Type": "idle"] as [String: Any]
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let patched = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        XCTAssertEqual(patched["Type"] as? String, "idle")
        let configuration = try configuration(of: patched)
        XCTAssertEqual(
            (configuration["url"] as? [String: String])?["relative"],
            imageURL.absoluteString
        )
        XCTAssertTrue(WallpaperStore().holdsWallpaper(imageURL, inStoreAt: url))
    }

    /// The slot is written from scratch, so the shuffle of macOS is reset.
    func testASlotWithAShuffleIsWrittenWithNoShuffle() throws {
        var container = StoreFixture.container()
        var slot = try XCTUnwrap(container["Desktop"] as? [String: Any])
        var content = try XCTUnwrap(slot["Content"] as? [String: Any])
        content["Shuffle"] = "some-shuffle"
        slot["Content"] = content
        container["Desktop"] = slot
        var store = StoreFixture.store()
        store["AllSpacesAndDisplays"] = container
        let url = try writeFixture(store)
        let imageURL = URL(fileURLWithPath: "/Users/Zeb/Pictures/Wallpapers/New.jpg")

        try WallpaperStore().setWallpaper(imageURL, inStoreAt: url)

        let after = try WallpaperStore().read(at: url)
        let patched = try XCTUnwrap(after["AllSpacesAndDisplays"] as? [String: Any])
        let patchedSlot = try XCTUnwrap(patched["Desktop"] as? [String: Any])
        let patchedContent = try XCTUnwrap(patchedSlot["Content"] as? [String: Any])
        XCTAssertEqual(patchedContent["Shuffle"] as? String, "$null")
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
