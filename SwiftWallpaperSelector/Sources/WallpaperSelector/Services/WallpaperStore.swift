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

    /// The keys of the store root and of a Space record.
    enum Key {
        static let globalContainer = "AllSpacesAndDisplays"
        static let systemDefault = "SystemDefault"
        static let spaces = "Spaces"
        static let displays = "Displays"

        /// The container of a Space record that holds the wallpaper of the
        /// Space itself.
        static let spaceDefault = "Default"

        /// The kind of a container. It names the slot that macOS reads.
        static let type = "Type"
    }

    /// The names of the wallpaper slots.
    ///
    /// The `Type` of a container decides which slot macOS uses: `linked`
    /// containers use `Linked`, every other container uses `Desktop`. The
    /// idle slot holds the wallpaper of the idle screen, which is a different
    /// wallpaper, so it is never touched.
    enum Slot {
        static let desktop = "Desktop"
        static let linked = "Linked"
        static let idle = "Idle"
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
    /// file. The rename replaces the inode, so the replacement loses the
    /// metadata the agent keeps on its file and the agent sets that metadata
    /// again when it rewrites the store.
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
    func setWallpaper(_ imageURL: URL, inStoreAt url: URL) throws {
        var store = try read(at: url)
        try setWallpaper(imageURL, in: &store)
        try write(store, to: url)
    }

    /// Writes the wallpaper into the store.
    ///
    /// The wallpaper is written into the global container, into the
    /// `SystemDefault`, into the `Default` container of every Space, into
    /// every Display of a Space and into every top-level Display. A
    /// wallpaper of a single Space wins over the global one, so every
    /// container that exists has to be written. The global container is
    /// required, because macOS always reads it; the other root containers
    /// are written only when they exist, and an absent key stays absent.
    ///
    /// A root key that this app does not know is left untouched, so a store
    /// of a newer macOS version is preserved. A container that is not
    /// understood stops the whole write, so the file is never changed
    /// halfway.
    ///
    /// The store is patched into a local copy and assigned back only when
    /// every container was written, so a throw cannot leave the caller with
    /// a half-patched dictionary.
    func setWallpaper(_ imageURL: URL, in store: inout [String: Any]) throws {
        let configuration = try Self.configurationData(for: imageURL)
        let optionValues = try Self.optionValuesData()
        let now = Date()

        var result = store
        result[Key.globalContainer] = try patchedContainer(
            store[Key.globalContainer],
            at: Key.globalContainer,
            configuration: configuration,
            optionValues: optionValues,
            now: now
        )
        if store[Key.systemDefault] != nil {
            result[Key.systemDefault] = try patchedContainer(
                store[Key.systemDefault],
                at: Key.systemDefault,
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        }
        if store[Key.spaces] != nil {
            result[Key.spaces] = try patchedSpaceMap(
                store[Key.spaces],
                at: Key.spaces,
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        }
        if store[Key.displays] != nil {
            result[Key.displays] = try patchedContainerMap(
                store[Key.displays],
                at: Key.displays,
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        }
        store = result
    }

    /// The wallpaper of the global container, as it is written in the store.
    func wallpaperURL(in store: [String: Any]) -> URL? {
        guard let container = store[Key.globalContainer] as? [String: Any] else { return nil }
        return Self.wallpaperURL(inContainer: container)
    }

    /// The wallpaper of the slot that macOS uses for a container.
    private static func wallpaperURL(inContainer container: [String: Any]) -> URL? {
        guard let name = desktopSlotName(in: container),
              let slot = container[name] as? [String: Any]
        else { return nil }
        return wallpaperURL(inSlot: slot)
    }

    /// Whether every container of the store holds the wallpaper.
    ///
    /// The global container has to hold the wallpaper and every other
    /// container has to hold it in the slot that macOS uses for it: a Space
    /// that keeps its old wallpaper is a Space the wallpaper did not reach.
    func holdsWallpaper(_ imageURL: URL, in store: [String: Any]) -> Bool {
        let expected = imageURL.standardizedFileURL.path
        guard let global = store[Key.globalContainer] as? [String: Any],
              Self.containerHolds(global, wallpaperPath: expected),
              let containers = containers(in: store)
        else { return false }
        for container in containers {
            guard Self.containerHolds(container, wallpaperPath: expected) else { return false }
        }
        return true
    }

    /// Whether the store file holds the wallpaper in every container.
    func holdsWallpaper(_ imageURL: URL, inStoreAt url: URL) -> Bool {
        guard let store = try? read(at: url) else { return false }
        return holdsWallpaper(imageURL, in: store)
    }

    /// Whether a container holds the wallpaper in the slot macOS uses.
    private static func containerHolds(_ container: [String: Any], wallpaperPath: String) -> Bool {
        guard let name = desktopSlotName(in: container),
              let slot = container[name] as? [String: Any],
              let url = wallpaperURL(inSlot: slot)
        else { return false }
        return url.standardizedFileURL.path == wallpaperPath
    }

    /// The slot that macOS uses for the desktop picture of a container.
    ///
    /// A `linked` container uses `Linked`; every other container uses
    /// `Desktop`. The presence of `Desktop` is enough when the type is
    /// missing, because a store of an older macOS version can lack it.
    private static func desktopSlotName(in container: [String: Any]) -> String? {
        if container[Key.type] as? String == "linked" { return Slot.linked }
        if container[Key.type] != nil || container[Slot.desktop] != nil { return Slot.desktop }
        return nil
    }

    /// Every container of the store except the global one.
    ///
    /// The containers are the ones the patch writes: the system default, the
    /// `Default` container of every Space, every Display of a Space and every
    /// top-level Display. A result of `nil` means that a Space record is not
    /// understood, so the store cannot be verified.
    private func containers(in store: [String: Any]) -> [[String: Any]]? {
        var result: [[String: Any]] = []
        if let systemDefault = store[Key.systemDefault] as? [String: Any] {
            result.append(systemDefault)
        }
        if let displays = store[Key.displays] as? [String: Any] {
            result.append(contentsOf: Self.containers(inMap: displays))
        }
        if let spaces = store[Key.spaces] as? [String: Any] {
            for value in spaces.values {
                guard let record = value as? [String: Any] else { return nil }
                var holdsContainer = false
                if let container = record[Key.spaceDefault] as? [String: Any] {
                    result.append(container)
                    holdsContainer = true
                }
                if let displays = record[Key.displays] as? [String: Any] {
                    result.append(contentsOf: Self.containers(inMap: displays))
                    holdsContainer = true
                }
                if Self.desktopSlotName(in: record) != nil {
                    result.append(record)
                    holdsContainer = true
                }
                guard holdsContainer else { return nil }
            }
        }
        return result
    }

    private static func containers(inMap map: [String: Any]) -> [[String: Any]] {
        map.values.compactMap { $0 as? [String: Any] }
    }

    // MARK: - The shape of the store

    /// A container holds the wallpaper in the slot that its `Type` names.
    ///
    /// The slot is written from scratch, so stale keys of its content and the
    /// shuffle of macOS are reset.
    private func patchedContainer(
        _ value: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        guard let container = value as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a container")
        }

        var result = container
        let slot = Self.slot(configuration: configuration, optionValues: optionValues, now: now)
        if container[Key.type] as? String == "linked" {
            // A linked container uses `Linked`. A `Desktop` slot that is left
            // over is stale and would win over the new slot.
            result[Slot.linked] = slot
            result.removeValue(forKey: Slot.desktop)
        } else if container[Key.type] != nil || container[Slot.desktop] != nil {
            // An individual container uses `Desktop`. A stray `Linked` slot
            // is left alone, because macOS does not read it.
            result[Slot.desktop] = slot
        } else {
            throw WallpaperStoreError.unexpectedShape(
                reason: "\(path) has neither a type nor a desktop slot"
            )
        }
        return result
    }

    /// A map of containers, keyed by the id of a Space or a Display.
    private func patchedContainerMap(
        _ value: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        guard let map = value as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a map of containers")
        }

        var result = map
        for (id, value) in map {
            result[id] = try patchedContainer(
                value,
                at: "\(path).\(id)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        }
        return result
    }

    /// A map of Space records, keyed by the id of the Space.
    private func patchedSpaceMap(
        _ value: Any?,
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        guard let map = value as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a map of Spaces")
        }

        var result = map
        for (id, value) in map {
            guard let record = value as? [String: Any] else {
                throw WallpaperStoreError.unexpectedShape(reason: "\(path).\(id) is not a Space")
            }
            result[id] = try patchedSpace(
                record,
                at: "\(path).\(id)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        }
        return result
    }

    /// A Space record.
    ///
    /// The wallpaper of the Space sits in its `Default` container and in the
    /// container of every Display of the Space. A record that names a
    /// wallpaper slot of its own is patched as a container as well. A record
    /// that has neither stops the write, because its wallpaper would not be
    /// reached.
    private func patchedSpace(
        _ record: [String: Any],
        at path: String,
        configuration: Data,
        optionValues: Data,
        now: Date
    ) throws -> [String: Any] {
        var result = record
        var holdsContainer = false
        if let value = record[Key.spaceDefault] {
            result[Key.spaceDefault] = try patchedContainer(
                value,
                at: "\(path).\(Key.spaceDefault)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
            holdsContainer = true
        }
        if let value = record[Key.displays] {
            result[Key.displays] = try patchedContainerMap(
                value,
                at: "\(path).\(Key.displays)",
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
            holdsContainer = true
        }
        if Self.desktopSlotName(in: record) != nil {
            result = try patchedContainer(
                result,
                at: path,
                configuration: configuration,
                optionValues: optionValues,
                now: now
            )
        } else if !holdsContainer {
            throw WallpaperStoreError.unexpectedShape(
                reason: "\(path) has no Default container, no Displays and no wallpaper slot"
            )
        }
        return result
    }

    /// A fresh wallpaper slot.
    ///
    /// The slot is built from scratch instead of copying an old one, so a
    /// stale key of the old content is dropped and the shuffle of macOS is
    /// reset.
    private static func slot(
        configuration: Data,
        optionValues: Data,
        now: Date
    ) -> [String: Any] {
        [
            "Content": [
                "Choices": [[
                    "Provider": imageChoiceProvider,
                    "Files": [Any](),
                    "Configuration": configuration,
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": optionValues,
            ],
            "LastSet": now,
            "LastUse": now,
        ]
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
