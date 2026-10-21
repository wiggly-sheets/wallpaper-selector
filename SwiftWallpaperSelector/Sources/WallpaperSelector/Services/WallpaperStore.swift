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
        } catch {
            throw WallpaperStoreError.writeFailed(path: url.path, reason: error.localizedDescription)
        }

        guard rename(temporary.path, url.path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw WallpaperStoreError.renameFailed(path: url.path, reason: reason)
        }
    }

    // MARK: - The wallpaper

    /// Writes the wallpaper into the store file.
    func setWallpaper(_ imageURL: URL, inStoreAt url: URL) throws {
        var store = try read(at: url)
        try setWallpaper(imageURL, in: &store)
        try write(store, to: url)
    }

    /// Writes the wallpaper into the store.
    ///
    /// The wallpaper is written into the global container, into the
    /// `SystemDefault` and into every Space and Display container that holds
    /// one, because a wallpaper of a single Space wins over the global one.
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

        store[Key.globalContainer] = try patched(
            container: store[Key.globalContainer],
            at: Key.globalContainer,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        )
        store[Key.systemDefault] = try patched(
            container: store[Key.systemDefault],
            at: Key.systemDefault,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        )
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
        for name in Slot.desktopPicture {
            guard let slot = container[name] as? [String: Any] else { continue }
            if let url = Self.wallpaperURL(inSlot: slot) { return url }
        }
        return nil
    }

    /// Whether the store file holds the wallpaper in the global container.
    func holdsWallpaper(_ imageURL: URL, inStoreAt url: URL) -> Bool {
        guard let store = try? read(at: url),
              let stored = wallpaperURL(in: store)
        else { return false }
        return stored.standardizedFileURL.path == imageURL.standardizedFileURL.path
    }

    // MARK: - The shape of the store

    /// A container holds the wallpaper in one of its slots and can hold a
    /// container per display.
    private func patched(
        container: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
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
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) holds no wallpaper")
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
            result[id] = try patched(
                container: value,
                at: "\(path).\(id)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
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
