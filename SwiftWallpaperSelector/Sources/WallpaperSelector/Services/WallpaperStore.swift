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
        let image = try Self.preparedImage(for: imageURL)
        let now = Date()

        var result = store
        result[Key.globalContainer] = try patchedContainer(
            store[Key.globalContainer],
            at: Key.globalContainer,
            image: image,
            now: now
        )
        if store[Key.systemDefault] != nil {
            result[Key.systemDefault] = try patchedContainer(
                store[Key.systemDefault],
                at: Key.systemDefault,
                image: image,
                now: now
            )
        }
        if store[Key.spaces] != nil {
            result[Key.spaces] = try patchedSpaceMap(
                store[Key.spaces],
                at: Key.spaces,
                image: image,
                now: now
            )
        }
        if store[Key.displays] != nil {
            result[Key.displays] = try patchedContainerMap(
                store[Key.displays],
                at: Key.displays,
                image: image,
                now: now
            )
        }
        store = result
    }

    /// Writes a wallpaper for every Space, with a pin for a Space that keeps
    /// its own wallpaper.
    ///
    /// The global container is set to the idle type, because a desktop
    /// wallpaper in the global container wins over the record of a Space.
    /// Without the global wallpaper every Space reads its own record: a
    /// pinned Space keeps its image, and an unpinned Space gets the default.
    /// A Space that has no record yet gets one, so a Space the user has never
    /// visited can be given a wallpaper too.
    ///
    /// A Space that macOS creates later has no record. The caller writes a
    /// record for it when it appears, through `spaceIDs`.
    func setWallpapers(
        default defaultImage: URL,
        pins: [String: URL],
        spaceIDs: [String],
        in store: inout [String: Any]
    ) throws {
        let defaultPrepared = try Self.preparedImage(for: defaultImage)
        var pinnedImages: [String: PreparedImage] = [:]
        for (id, url) in pins {
            pinnedImages[id] = try Self.preparedImage(for: url)
        }
        let now = Date()

        var result = store
        // macOS keeps the global container as an idle container without a
        // desktop. A global desktop wallpaper wins over the record of every
        // Space, so it has to go. The idle wallpaper stays.
        let global = store[Key.globalContainer] as? [String: Any]
        if var converted = global {
            converted[Key.type] = "idle"
            converted.removeValue(forKey: Slot.desktop)
            converted.removeValue(forKey: Slot.linked)
            result[Key.globalContainer] = converted
        }
        let idleSlot = global?[Slot.idle] as? [String: Any]
            ?? (store[Key.systemDefault] as? [String: Any])?[Slot.idle] as? [String: Any]
        let displayIDs = (store[Key.displays] as? [String: Any]).map { Array($0.keys) } ?? []
        if store[Key.systemDefault] != nil {
            result[Key.systemDefault] = try patchedContainer(
                store[Key.systemDefault],
                at: Key.systemDefault,
                image: defaultPrepared,
                now: now
            )
        }

        var spaces: [String: Any]
        if let stored = store[Key.spaces] {
            guard let map = stored as? [String: Any] else {
                throw WallpaperStoreError.unexpectedShape(reason: "\(Key.spaces) is not a map of Spaces")
            }
            spaces = map
        } else {
            spaces = [:]
        }
        for id in Set(spaceIDs).union(pins.keys) {
            let image = pinnedImages[id] ?? defaultPrepared
            let path = "\(Key.spaces).\(id)"
            if let stored = spaces[id] {
                guard let record = stored as? [String: Any] else {
                    throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a Space")
                }
                var patched = try patchedSpace(record, at: path, image: image, now: now)
                if !displayIDs.isEmpty {
                    var displays = patched[Key.displays] as? [String: Any] ?? [:]
                    for displayID in displayIDs where displays[displayID] == nil {
                        displays[displayID] = Self.freshContainer(
                            image: image,
                            idleSlot: idleSlot,
                            now: now
                        )
                    }
                    patched[Key.displays] = displays
                }
                spaces[id] = patched
            } else {
                spaces[id] = Self.freshSpace(
                    image: image,
                    displayIDs: displayIDs,
                    idleSlot: idleSlot,
                    now: now
                )
            }
        }
        result[Key.spaces] = spaces

        if store[Key.displays] != nil {
            result[Key.displays] = try patchedContainerMap(
                store[Key.displays],
                at: Key.displays,
                image: defaultPrepared,
                now: now
            )
        }
        store = result
    }

    /// Writes a wallpaper for every Space into the store file.
    func setWallpapers(
        default defaultImage: URL,
        pins: [String: URL],
        spaceIDs: [String],
        inStoreAt url: URL
    ) throws {
        var store = try read(at: url)
        try setWallpapers(default: defaultImage, pins: pins, spaceIDs: spaceIDs, in: &store)
        try write(store, to: url)
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

    /// Whether every Space record that exists holds the wallpaper.
    ///
    /// macOS keeps the global container idle once the store has a record for
    /// every Space, and the records win. This check answers the old question
    /// for that store: every Space shows the wallpaper even though the global
    /// container is empty.
    func holdsWallpaperInEverySpace(_ imageURL: URL, in store: [String: Any]) -> Bool {
        let expected = imageURL.standardizedFileURL.path
        guard let spaces = store[Key.spaces] as? [String: Any], !spaces.isEmpty else {
            return false
        }
        for value in spaces.values {
            guard let record = value as? [String: Any],
                  let containers = Self.containers(inSpace: record),
                  !containers.isEmpty
            else { return false }
            for container in containers {
                guard Self.containerHolds(container, wallpaperPath: expected) else { return false }
            }
        }
        return true
    }

    func holdsWallpaperInEverySpace(_ imageURL: URL, inStoreAt url: URL) -> Bool {
        guard let store = try? read(at: url) else { return false }
        return holdsWallpaperInEverySpace(imageURL, in: store)
    }

    /// Whether every Space holds its own wallpaper.
    ///
    /// The global container has to be empty, because macOS lets it win over
    /// the record of a Space. A pinned Space has to hold its pin, every other
    /// Space the default. A Space without a record is a Space the wallpaper
    /// did not reach.
    ///
    /// The `SystemDefault` and the top-level Displays are not checked: the
    /// wallpaper agent rewrites them from the Space that is current, so they
    /// say nothing about the Space that is not current.
    func holdsWallpapers(
        default defaultImage: URL,
        pins: [String: URL],
        spaceIDs: [String],
        in store: [String: Any]
    ) -> Bool {
        // A global desktop wallpaper wins over the record of every Space.
        // macOS keeps the global container as an idle container then.
        if let global = store[Key.globalContainer] as? [String: Any],
           global[Slot.desktop] != nil || global[Slot.linked] != nil {
            return false
        }
        guard let spaces = store[Key.spaces] as? [String: Any] else {
            return Set(spaceIDs).union(pins.keys).isEmpty
        }
        for id in Set(spaceIDs).union(pins.keys) {
            guard let record = spaces[id] as? [String: Any],
                  let containers = Self.containers(inSpace: record),
                  !containers.isEmpty
            else { return false }
            let expected = (pins[id] ?? defaultImage).standardizedFileURL.path
            for container in containers {
                guard Self.containerHolds(container, wallpaperPath: expected) else { return false }
            }
        }
        return true
    }

    /// Whether the store file holds every Space wallpaper.
    func holdsWallpapers(
        default defaultImage: URL,
        pins: [String: URL],
        spaceIDs: [String],
        inStoreAt url: URL
    ) -> Bool {
        guard let store = try? read(at: url) else { return false }
        return holdsWallpapers(default: defaultImage, pins: pins, spaceIDs: spaceIDs, in: store)
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
                guard let record = value as? [String: Any],
                      let recordContainers = Self.containers(inSpace: record)
                else { return nil }
                result.append(contentsOf: recordContainers)
            }
        }
        return result
    }

    /// The containers of one Space record, or `nil` when the record is not
    /// understood.
    private static func containers(inSpace record: [String: Any]) -> [[String: Any]]? {
        var result: [[String: Any]] = []
        if let container = record[Key.spaceDefault] as? [String: Any] {
            result.append(container)
        }
        if let displays = record[Key.displays] as? [String: Any] {
            result.append(contentsOf: Self.containers(inMap: displays))
        }
        if Self.desktopSlotName(in: record) != nil {
            result.append(record)
        }
        return result.isEmpty ? nil : result
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
        image: PreparedImage,
        now: Date
    ) throws -> [String: Any] {
        guard let container = value as? [String: Any] else {
            throw WallpaperStoreError.unexpectedShape(reason: "\(path) is not a container")
        }

        var result = container
        let slot = Self.slot(image: image, now: now)
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
        image: PreparedImage,
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
                image: image,
                now: now
            )
        }
        return result
    }

    /// A map of Space records, keyed by the id of the Space.
    private func patchedSpaceMap(
        _ value: Any?,
        at path: String,
        image: PreparedImage,
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
                image: image,
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
        image: PreparedImage,
        now: Date
    ) throws -> [String: Any] {
        var result = record
        var holdsContainer = false
        if let value = record[Key.spaceDefault] {
            result[Key.spaceDefault] = try patchedContainer(
                value,
                at: "\(path).\(Key.spaceDefault)",
                image: image,
                now: now
            )
            holdsContainer = true
        }
        if let value = record[Key.displays] {
            result[Key.displays] = try patchedContainerMap(
                value,
                at: "\(path).\(Key.displays)",
                image: image,
                now: now
            )
            holdsContainer = true
        }
        if Self.desktopSlotName(in: record) != nil {
            result = try patchedContainer(
                result,
                at: path,
                image: image,
                now: now
            )
        } else if !holdsContainer {
            throw WallpaperStoreError.unexpectedShape(
                reason: "\(path) has no Default container, no Displays and no wallpaper slot"
            )
        }
        return result
    }

    /// A wallpaper that is ready to be written into a container.
    private struct PreparedImage {
        let configuration: Data
        let optionValues: Data
    }

    private static func preparedImage(for imageURL: URL) throws -> PreparedImage {
        PreparedImage(
            configuration: try configurationData(for: imageURL),
            optionValues: try optionValuesData()
        )
    }

    /// A container for a Space that has no record yet.
    /// A container for a Space that has no record yet.
    ///
    /// macOS writes the desktop and the idle wallpaper, and a Display keeps
    /// its own container. The idle wallpaper is copied from the store, so the
    /// fresh container looks like the one macOS writes.
    private static func freshContainer(
        image: PreparedImage,
        idleSlot: [String: Any]? = nil,
        now: Date
    ) -> [String: Any] {
        var container: [String: Any] = [
            Key.type: "individual",
            Slot.desktop: slot(image: image, now: now),
        ]
        if let idleSlot {
            container[Slot.idle] = idleSlot
        }
        return container
    }

    private static func freshSpace(
        image: PreparedImage,
        displayIDs: [String],
        idleSlot: [String: Any]?,
        now: Date
    ) -> [String: Any] {
        var record: [String: Any] = [
            Key.spaceDefault: freshContainer(image: image, idleSlot: idleSlot, now: now),
        ]
        if !displayIDs.isEmpty {
            record[Key.displays] = Dictionary(
                uniqueKeysWithValues: displayIDs.map { id in
                    (id, freshContainer(image: image, idleSlot: idleSlot, now: now))
                }
            )
        }
        return record
    }

    /// A fresh wallpaper slot.
    ///
    /// The slot is built from scratch instead of copying an old one, so a
    /// stale key of the old content is dropped and the shuffle of macOS is
    /// reset.
    private static func slot(image: PreparedImage, now: Date) -> [String: Any] {
        [
            "Content": [
                "Choices": [[
                    "Provider": imageChoiceProvider,
                    "Files": [Any](),
                    "Configuration": image.configuration,
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": image.optionValues,
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
