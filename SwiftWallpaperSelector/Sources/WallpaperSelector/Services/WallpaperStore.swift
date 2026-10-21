import Foundation

enum WallpaperStoreError: Error, LocalizedError, Equatable {
    case storeNotFound(path: String)
    case notAPropertyList(path: String, reason: String)
    case unexpectedShape(reason: String)
    case nestedPropertyListFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case renameFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .storeNotFound(let path):
            return "The wallpaper store was not found at \(path)."
        case .notAPropertyList(let path, let reason):
            return "The wallpaper store at \(path) is not a property list: \(reason)"
        case .unexpectedShape(let reason):
            return "The wallpaper store has a shape that is not understood: \(reason)"
        case .nestedPropertyListFailed(let reason):
            return "The wallpaper store could not be built: \(reason)"
        case .writeFailed(let path, let reason):
            return "The wallpaper store at \(path) could not be written: \(reason)"
        case .renameFailed(let path, let reason):
            return "The wallpaper store at \(path) could not be replaced: \(reason)"
        }
    }
}

/// The store the wallpaper agent keeps the wallpaper in.
///
/// macOS 14 and newer keep the wallpaper of every Space and Display in an
/// Apple binary property list at
/// `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
/// The agent owns the file and rewrites it on every change, so the app writes
/// the file itself and restarts the agent afterwards.
struct WallpaperStore {

    /// The keys of the store root.
    enum Key {
        static let globalContainer = "AllSpacesAndDisplays"
        static let systemDefault = "SystemDefault"
        static let spaces = "Spaces"
        static let displays = "Displays"

        static let all: Set<String> = [globalContainer, systemDefault, spaces, displays]
    }

    /// The names of the wallpaper slots.
    ///
    /// The name of the slot and the `Type` of its container are two different
    /// axes: a container can hold the type `individual` and the slot
    /// `Desktop`. The slot is therefore found by the presence of its key and
    /// never by the type.
    enum Slot {
        static let desktop = "Desktop"
        static let defaultSlot = "Default"
        static let linked = "Linked"

        /// The idle slot holds the wallpaper of the idle screen. It is a
        /// different wallpaper and it is never touched.
        static let idle = "Idle"

        /// The slots that hold the desktop picture.
        static let desktopPicture = [desktop, defaultSlot, linked]

        /// The keys of a container that this app understands.
        static let known: Set<String> = Set(desktopPicture + [idle])
    }

    /// The provider of a wallpaper that is a single image file.
    static let imageChoiceProvider = "com.apple.wallpaper.choice.image"

    /// The file the agent keeps the wallpaper in.
    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist", isDirectory: false)
    }

    // MARK: - The file

    /// Flushes the file to the disk.
    ///
    /// The file is opened and synchronized, so its content is on the disk
    /// when it is renamed over the old one.
    var flushFile: (URL) throws -> Void = WallpaperStore.flushFileToDisk

    /// Flushes the folder of the file to the disk.
    ///
    /// The rename is only durable when the folder is flushed, too.
    var flushFolder: (URL) -> Void = WallpaperStore.flushFolderToDisk

    /// Renames the file over the old one.
    ///
    /// The closure is the seam a test uses to see when the rename happens.
    var renameFile: (String, String) -> Int32 = { rename($0, $1) }

    /// Reads the store.
    func read(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WallpaperStoreError.storeNotFound(path: url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WallpaperStoreError.notAPropertyList(path: url.path, reason: error.localizedDescription)
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        } catch {
            throw WallpaperStoreError.notAPropertyList(path: url.path, reason: error.localizedDescription)
        }
        guard let store = plist as? [String: Any] else {
            throw WallpaperStoreError.notAPropertyList(path: url.path, reason: "the store is not a dictionary")
        }
        return store
    }

    /// Writes the store as a binary property list.
    ///
    /// The file is written to a temporary file in the same folder and then
    /// renamed over the old one, so the agent never reads a half written
    /// file. The rename drops the quarantine flag of the file, which is what
    /// the agent does as well.
    ///
    /// The temporary file is flushed before the rename and the folder is
    /// flushed after it, so a crash cannot leave a store without content.
    func write(_ store: [String: Any], to url: URL) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        } catch {
            throw WallpaperStoreError.writeFailed(path: url.path, reason: error.localizedDescription)
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try flushFile(temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw WallpaperStoreError.writeFailed(path: url.path, reason: error.localizedDescription)
        }

        guard renameFile(temporary.path, url.path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw WallpaperStoreError.renameFailed(path: url.path, reason: reason)
        }

        flushFolder(url.deletingLastPathComponent())
    }

    /// Flushes the file to the disk.
    ///
    /// The file is opened and synchronized, so its content is on the disk
    /// when it is renamed over the old one.
    private static func flushFileToDisk(_ url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        handle.synchronizeFile()
    }

    /// Flushes the folder to the disk.
    ///
    /// shortcut: the data is already written, so a folder that cannot be
    /// flushed is not reported as a failed write. Upgrade this when the
    /// store has to survive a power cut of the file system.
    private static func flushFolderToDisk(_ url: URL) {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        _ = fsync(descriptor)
        close(descriptor)
    }

    // MARK: - The wallpaper

    /// Writes the wallpaper into the store file.
    ///
    /// The result names the containers that hold a wallpaper the app cannot
    /// write. The wallpaper of such a container stays the old one, so the
    /// wallpaper does not reach that Space.
    @discardableResult
    func setWallpaper(_ imageURL: URL, inStoreAt url: URL) throws -> [String] {
        var store = try read(at: url)
        try setWallpaper(imageURL, in: &store)
        let unwritable = unwritableWallpaperPaths(in: store)
        try write(store, to: url)
        return unwritable
    }

    /// Writes the wallpaper into the store.
    ///
    /// The wallpaper is written into the global container, into the
    /// `SystemDefault` and into every Space and Display container that holds
    /// one, because a wallpaper of a single Space wins over the global one.
    /// A container that holds no wallpaper is skipped, so a Space without a
    /// wallpaper does not stop the write.
    ///
    /// The idle slot is left alone: it holds the wallpaper of the idle
    /// screen, which is a different wallpaper.
    ///
    /// A container that is not understood stops the whole write, so the file
    /// is never changed halfway.
    func setWallpaper(_ imageURL: URL, in store: inout [String: Any]) throws {
        let configuration = try Self.configurationData(for: imageURL)
        let optionValues = try Self.optionValuesData()
        let now = Date()

        // shortcut: a key of the root that this app does not know stops the
        // write. A new macOS version can add one, and a half understood
        // store is worse than no change at all.
        for key in store.keys where !Key.all.contains(key) {
            throw WallpaperStoreError.unexpectedShape(reason: "the store has an unknown key \(key)")
        }

        if let patched = try patched(
            container: store[Key.globalContainer],
            at: Key.globalContainer,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        ) {
            store[Key.globalContainer] = patched
        }
        if let patched = try patched(
            container: store[Key.systemDefault],
            at: Key.systemDefault,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        ) {
            store[Key.systemDefault] = patched
        }
        store[Key.spaces] = try patched(
            containerMap: store[Key.spaces],
            at: Key.spaces,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        )
        store[Key.displays] = try patched(
            containerMap: store[Key.displays],
            at: Key.displays,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        )
    }

    /// The wallpaper of the global container, as it is written in the store.
    func wallpaperURL(in store: [String: Any]) -> URL? {
        guard let container = store[Key.globalContainer] as? [String: Any] else { return nil }
        return Self.wallpaperURL(inContainer: container)
    }

    /// The wallpaper of a container.
    private static func wallpaperURL(inContainer container: [String: Any]) -> URL? {
        for name in Slot.desktopPicture {
            guard let slot = container[name] as? [String: Any] else { continue }
            if let url = wallpaperURL(inSlot: slot) { return url }
        }
        return nil
    }

    /// Whether every container of the store holds the wallpaper.
    ///
    /// The global container has to hold the wallpaper and every container
    /// that has a slot of the desktop picture has to hold it too: a Space
    /// that keeps its old wallpaper is a Space the wallpaper did not reach.
    func holdsWallpaper(_ imageURL: URL, in store: [String: Any]) -> Bool {
        let expected = imageURL.standardizedFileURL.path
        guard let global = store[Key.globalContainer] as? [String: Any],
              let globalURL = Self.wallpaperURL(inContainer: global),
              globalURL.standardizedFileURL.path == expected
        else { return false }
        for entry in containers(in: store) {
            for name in Slot.desktopPicture {
                guard let slot = entry.container[name] as? [String: Any] else { continue }
                guard let url = Self.wallpaperURL(inSlot: slot),
                      url.standardizedFileURL.path == expected else { return false }
            }
        }
        return true
    }

    /// Whether the store file holds the wallpaper in every container.
    func holdsWallpaper(_ imageURL: URL, inStoreAt url: URL) -> Bool {
        guard let store = try? read(at: url) else { return false }
        return holdsWallpaper(imageURL, in: store)
    }

    /// The paths of the containers that hold a wallpaper the app cannot write.
    ///
    /// The app writes the slots of the desktop picture. The wallpaper of a
    /// container that holds its wallpaper in another slot stays the old one,
    /// so the wallpaper does not reach that Space. The app says so instead
    /// of claiming that the wallpaper is on every Space.
    func unwritableWallpaperPaths(in store: [String: Any]) -> [String] {
        containers(in: store).compactMap { entry in
            guard let name = Self.unwritableSlot(in: entry.container) else { return nil }
            return "\(entry.path).\(name)"
        }
    }

    /// Every container of the store with its path.
    ///
    /// The containers are the ones the patch writes: the global one, the
    /// system default, every Space and every Display.
    private func containers(in store: [String: Any]) -> [(path: String, container: [String: Any])] {
        var result: [(path: String, container: [String: Any])] = []
        for key in [Key.globalContainer, Key.systemDefault] {
            guard let container = store[key] as? [String: Any] else { continue }
            result.append((path: key, container: container))
        }
        for key in [Key.spaces, Key.displays] {
            guard let map = store[key] as? [String: Any] else { continue }
            for (id, value) in map {
                guard let container = value as? [String: Any] else { continue }
                result.append((path: "\(key).\(id)", container: container))
                guard let displays = container[Key.displays] as? [String: Any] else { continue }
                for (displayID, display) in displays {
                    guard let displayContainer = display as? [String: Any] else { continue }
                    result.append((
                        path: "\(key).\(id).\(Key.displays).\(displayID)",
                        container: displayContainer
                    ))
                }
            }
        }
        return result
    }

    /// The slot of a container that holds a wallpaper the app does not write.
    ///
    /// The idle slot holds the wallpaper of the idle screen, so it is left
    /// alone and never counts.
    private static func unwritableSlot(in container: [String: Any]) -> String? {
        for name in container.keys.sorted() {
            guard name != Slot.idle, !Slot.desktopPicture.contains(name) else { continue }
            guard let slot = container[name] as? [String: Any] else { continue }
            if wallpaperURL(inSlot: slot) != nil { return name }
        }
        return nil
    }

    // MARK: - The shape of the store

    /// A container holds the wallpaper in one of its slots and can hold a
    /// container per display.
    ///
    /// The result is `nil` when the container holds no wallpaper, so it is
    /// skipped.
    private func patched(
        container: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any]? {
        guard let container = container as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a container")
        }

        var result = container
        var holdsWallpaper = false

        for name in Slot.desktopPicture {
            guard let value = result[name] else { continue }
            guard let slot = value as? [String: Any] else {
                throw WallpaperStoreError.unexpectedShape(reason: "\(path).\(name) is not a wallpaper slot")
            }
            result[name] = try patched(slot: slot, configuration: configuration, optionValues: optionValues, now: now)
            holdsWallpaper = true
        }

        // shortcut: the idle slot holds the wallpaper of the idle screen, so
        // it is never touched. Its option values carry a colour block that
        // the wallpaper of the desktop picture does not have.
        if let value = result[Slot.idle], !(value is [String: Any]) {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path).\(Slot.idle) is not a wallpaper slot")
        }

        if let value = result[Key.displays] {
            result[Key.displays] = try patched(
                containerMap: value,
                at: "\(path).\(Key.displays)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
            holdsWallpaper = true
        }

        guard holdsWallpaper else {
            // A container that carries a type is understood. When it holds
            // no wallpaper slot, it holds no wallpaper, so it is skipped. A
            // container with neither a type nor a known key is not
            // understood, so the write stops.
            let understood = result["Type"] is String || Slot.known.contains { result[$0] != nil }
            guard understood else {
                throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a container that is understood")
            }
            return nil
        }
        return result
    }

    /// A map of containers, keyed by the id of the Space or the Display.
    private func patched(
        containerMap: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        guard let containerMap = containerMap as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a map of containers")
        }

        var result = containerMap
        for (id, value) in containerMap {
            guard let patched = try patched(
                container: value,
                at: "\(path).\(id)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            ) else { continue }
            result[id] = patched
        }
        return result
    }

    /// The wallpaper of a slot.
    private func patched(
        slot: [String: Any],
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        guard let content = slot["Content"] as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "a wallpaper slot has no content")
        }

        var newContent = content
        newContent["Choices"] = [[
            "Provider": Self.imageChoiceProvider,
            "Files": [Any](),
            "Configuration": configuration,
        ]]
        newContent["EncodedOptionValues"] = optionValues

        var result = slot
        result["Content"] = newContent
        // The wallpaper was set now, so the agent applies it again.
        result["LastSet"] = now
        result["LastUse"] = now
        return result
    }

    private static func wallpaperURL(inSlot slot: [String: Any]) -> URL? {
        guard let content = slot["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let choice = choices.first,
              let configurationData = choice["Configuration"] as? Data,
              let configuration = try? PropertyListSerialization.propertyList(
                  from: configurationData,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let url = configuration["url"] as? [String: Any],
              let relative = url["relative"] as? String
        else { return nil }
        return URL(string: relative)
    }

    // MARK: - The nested property lists

    /// The configuration of a wallpaper that is a single image file.
    static func configurationData(for imageURL: URL) throws -> Data {
        try nestedData([
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString],
        ])
    }

    /// The option values of a wallpaper that fills the screen.
    static func optionValuesData() throws -> Data {
        // "Crop" is Fill Screen.
        try nestedData([
            "values": [
                "placement": [
                    "picker": ["_0": ["id": "Crop"]],
                ],
            ],
        ])
    }

    private static func nestedData(_ payload: [String: Any]) throws -> Data {
        do {
            return try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        } catch {
            throw WallpaperStoreError.nestedPropertyListFailed(reason: error.localizedDescription)
        }
    }
}
