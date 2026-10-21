import Foundation
import Combine

enum SettingsManagerError: LocalizedError, Equatable {
    case createDirectoryFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case renameFailed(path: String, reason: String)
    case legacySettingsNotImported(path: String)
    case legacySettingsNotMoved(path: String)

    var errorDescription: String? {
        switch self {
        case let .createDirectoryFailed(path, reason):
            return "Could not create the settings folder at \(path): \(reason)"
        case let .readFailed(path, reason):
            return "Could not read settings from \(path): \(reason)"
        case let .decodeFailed(path, reason):
            return "The settings file at \(path) is not valid: \(reason)"
        case let .encodeFailed(reason):
            return "Could not encode settings: \(reason)"
        case let .writeFailed(path, reason):
            return "Could not save settings to \(path): \(reason)"
        case let .renameFailed(path, reason):
            return "Could not move the settings file at \(path) aside: \(reason)"
        case let .legacySettingsNotImported(path):
            return "A legacy settings file was found at \(path) and was not imported, "
                + "because a newer settings file already exists. The legacy file was left "
                + "in place, so you can import it by hand."
        case let .legacySettingsNotMoved(path):
            return "The legacy settings were imported, but the legacy file could not be "
                + "moved aside: \(path)"
        }
    }
}

@MainActor
final class SettingsManager: ObservableObject {

    nonisolated static let defaultSettingsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WallpaperSelector", isDirectory: true)
    }()

    nonisolated static let bundleID = "com.wallpaper-selector.macos"
    nonisolated static let customDirectoryDefaultsKey = "WallpaperSelector.settingsDirectory"

    /// The settings file of the Electron version the app replaces.
    nonisolated static let defaultLegacySettingsURL: URL? = {
        guard let home = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first else {
            return nil
        }
        return home.appendingPathComponent(".wallpaper-selector/settings.json")
    }()

    private(set) var settingsDirectory: URL
    private(set) var settingsURL: URL

    @Published private(set) var lastError: SettingsManagerError?

    /// Holds the current settings.
    ///
    /// A subject is used instead of `@Published` because `@Published` publishes
    /// in `willSet`: subscribers would receive the new value while the
    /// `settings` property still holds the old one.
    private let settingsSubject = CurrentValueSubject<WallpaperSettings, Never>(WallpaperSettings())

    /// The current settings.
    ///
    /// The box is the single source of truth: the write queue reads it, so
    /// every write writes the settings that are current when it runs.
    private let currentSettings: SettingsBox<WallpaperSettings>

    /// The content the settings file holds on the disk.
    ///
    /// The box holds the value, so the IO path can read it without a hop to
    /// the main actor. The value is `nil` while the file was not read or
    /// written yet.
    ///
    /// The content tells the reload whether the file carries something the
    /// app does not know: a file that holds the content the app last knew
    /// carries nothing new, so it must not overwrite the settings in memory.
    /// That is the case after a failed write: the file still holds the older
    /// content.
    private let lastKnownOnDisk = SettingsBox<WallpaperSettings?>(nil)

    /// Publishes every settings change. The new value is stored before it is
    /// published, so `settings` already holds it while subscribers run.
    var settingsPublisher: AnyPublisher<WallpaperSettings, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    var onError: ((SettingsManagerError) -> Void)?


    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var pendingExternalChangeTask: Task<Void, Never>?
    private let fileManager: FileManager
    /// Checks whether a file exists.
    ///
    /// The check is a closure and not the file manager, because the IO path
    /// runs outside the main actor: a file manager must not cross that
    /// boundary. The closure is also the seam a test uses to pause the check
    /// for a file that was deleted externally.
    private let fileExists: @Sendable (URL) -> Bool
    private let queue = DispatchQueue(label: "com.wallpaper-selector.settings", qos: .utility)
    /// The queue that writes the settings file.
    ///
    /// The writes run here, so the main actor is never blocked by a file
    /// write, and the queue is serial, so two writes cannot interleave into a
    /// corrupt file.
    private let writeQueue = DispatchQueue(label: "com.wallpaper-selector.settings.write", qos: .utility)
    /// Counts the writes of the settings file.
    ///
    /// The reload has to know whether a change of the app is still on its way
    /// to the disk: a file that is older than the settings in memory must
    /// not overwrite them. The write queue fills the counters and the reload
    /// reads them, so a lock guards them.
    private let writeQueueCounters = WriteQueueCounters()
    /// Called before the settings file is written.
    ///
    /// The closure runs on the write queue. It is the seam a test uses to
    /// pause a write, so it can change the settings while the write waits.
    private let beforeWrite: (@Sendable () -> Void)?
    /// Called before the settings file is read during an external reload.
    ///
    /// The closure runs off the main actor. It is the seam a test uses to
    /// pause the read, so it can change the settings while the file is read.
    private let beforeRead: (@Sendable () -> Void)?
    /// Called before the result of an external reload is published.
    ///
    /// The closure runs on the main actor. It is the seam a test uses to
    /// land a change in the window between the decision of the reload and
    /// the publish of its result.
    private let beforePublish: (@MainActor () -> Void)?
    private let userDefaults: UserDefaults
    private let configuredDefaultSettingsDirectory: URL
    private let migrateLegacySettings: Bool
    private let legacySettingsURL: URL?

    /// Counts the external reloads. A reload that finishes after a newer one
    /// started is stale and must not overwrite the newer settings.
    private(set) var externalChangeGeneration: UInt = 0

    /// The legacy settings file is still on disk and was not imported. The
    /// message stays visible, so the user knows the file is there.
    private var legacySettingsNotice: SettingsManagerError?

    var isLegacyMigrationPending: Bool {
        legacySettingsNotice != nil
    }


    private enum ExternalChangeOutcome: Sendable {
        case unchanged
        case reloaded(WallpaperSettings, snapshot: ExternalChangeSnapshot)
        case recreated
    }


    init(
        settingsDirectory requestedDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        defaultSettingsDirectory: URL = SettingsManager.defaultSettingsDirectory,
        fileManager: FileManager = .default,
        fileExists: (@Sendable (URL) -> Bool)? = nil,
        migrateLegacySettings: Bool = true,
        legacySettingsURL: URL? = SettingsManager.defaultLegacySettingsURL,
        beforeWrite: (@Sendable () -> Void)? = nil,
        beforeRead: (@Sendable () -> Void)? = nil,
        beforePublish: (@MainActor () -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.fileExists = fileExists ?? { url in FileManager.default.fileExists(atPath: url.path) }
        self.userDefaults = userDefaults
        self.configuredDefaultSettingsDirectory = defaultSettingsDirectory.standardizedFileURL
        self.migrateLegacySettings = migrateLegacySettings
        self.legacySettingsURL = legacySettingsURL
        self.beforeWrite = beforeWrite
        self.beforeRead = beforeRead
        self.beforePublish = beforePublish
        self.currentSettings = SettingsBox(WallpaperSettings())

        let storedDirectory = userDefaults
            .string(forKey: Self.customDirectoryDefaultsKey)
            .map(URL.init(fileURLWithPath:))
        settingsDirectory = (requestedDirectory ?? storedDirectory ?? defaultSettingsDirectory).standardizedFileURL
        settingsURL = settingsDirectory.appendingPathComponent("settings.json")

        prepareInitialSettings(shouldMigrateLegacy: requestedDirectory == nil)
        startFileWatcher()
    }

    deinit {
        pendingExternalChangeTask?.cancel()
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }


    var isUsingDefaultSettingsDirectory: Bool {
        settingsDirectory.resolvingSymlinksInPath().path
            == configuredDefaultSettingsDirectory.resolvingSymlinksInPath().path
    }

    /// The current settings.
    var settings: WallpaperSettings {
        currentSettings.value
    }

    func update(_ mutation: (inout WallpaperSettings) -> Void) {
        var newValue = settings
        mutation(&newValue)
        replace(newValue)
    }

    /// Stores the new settings.
    ///
    /// The settings in memory change right away and the file catches up on
    /// the write queue, so the user interface is never blocked by the write.
    /// A failed write is reported through `lastError`.
    func replace(_ newSettings: WallpaperSettings) {
        let normalizedSettings = newSettings.normalized()
        publish(normalizedSettings)
        clearError()
        enqueueWrite(to: settingsURL)
    }

    /// Waits until the queued writes have landed on disk.
    ///
    /// The app calls this before it quits, so a change that was made a moment
    /// before the quit is not lost.
    func flushPendingWrites() {
        writeQueue.sync {}
    }

    /// Waits until the queued writes have landed and their failures are
    /// reported.
    func waitForPendingWrites() async {
        await withCheckedContinuation { continuation in
            writeQueue.async { continuation.resume() }
        }
    }

    func relocateSettings(to directory: URL) throws {
        try switchSettingsLocation(to: directory, customDirectoryPath: directory.standardizedFileURL.path)
    }

    func useDefaultSettingsLocation() throws {
        try switchSettingsLocation(to: configuredDefaultSettingsDirectory, customDirectoryPath: nil)
    }


    private func prepareInitialSettings(shouldMigrateLegacy: Bool) {
        do {
            try Self.createDirectoryIfNeeded(at: settingsDirectory)

            var legacyURL: URL?
            if shouldMigrateLegacy, migrateLegacySettings,
               let candidate = legacySettingsURL, fileExists(candidate) {
                legacyURL = candidate
            }

            if fileExists(settingsURL) {
                do {
                    let loaded = try Self.loadSettings(from: settingsURL)
                    publish(loaded)
                    // The file holds the settings that were loaded.
                    lastKnownOnDisk.value = loaded
                    if let legacyURL {
                        // A settings file exists: the legacy file is never
                        // imported over it. The content tells whether the
                        // import already happened.
                        reportLegacyFileBesideTheSettingsFile(legacyURL, loadedSettings: loaded)
                    }
                } catch let error as SettingsManagerError {
                    if let legacyURL {
                        // The settings file cannot be read, so the app cannot
                        // tell whether the legacy file was imported.
                        reportLegacyFileBesideTheSettingsFile(legacyURL, loadedSettings: nil)
                    }
                    // The unreadable file is the only copy of the user's folders,
                    // themes and history: keep it before anything can overwrite it.
                    let quarantined = quarantineUnreadableFile(at: settingsURL)
                    report(error)
                    // A fresh default file takes its place, so the watcher can run.
                    // Without a safe copy the unreadable file has to stay.
                    if quarantined {
                        // A failed write must be reported: the app would run
                        // without any settings file at all.
                        report(writeNow(to: settingsURL))
                    }
                }
            } else if let legacyURL {
                switch loadLegacySettingsIfAvailable(at: legacyURL) {
                case .migrated(let migrated):
                    publish(migrated)
                    // The import is done when the write lands: then the legacy
                    // file is renamed, so the next launch does not import it
                    // again.
                    let settings = currentSettings
                    let beforeWrite = self.beforeWrite
                    let fileManager = self.fileManager
                    let onDisk = lastKnownOnDisk
                    report(writeQueue.sync {
                        Self.importLegacySettings(
                            settings,
                            from: legacyURL,
                            to: settingsURL,
                            fileManager: fileManager,
                            beforeWrite: beforeWrite,
                            onDisk: onDisk
                        )
                    })
                    return
                case .unreadable:
                    // The legacy file is the only copy of the settings: the
                    // location stays empty, so the next launch retries the
                    // migration.
                    return
                case .none:
                    break
                }
            } else {
                report(writeNow(to: settingsURL))
            }
        } catch let error as SettingsManagerError {
            report(error)
        } catch {
            report(.readFailed(path: settingsURL.path, reason: error.localizedDescription))
        }
    }

    /// The result of the legacy migration.
    private enum LegacySettings {
        /// There is no legacy settings file.
        case none
        /// The legacy settings file was read.
        case migrated(WallpaperSettings)
        /// The legacy settings file exists but could not be read.
        case unreadable
    }

    private func loadLegacySettingsIfAvailable(at url: URL) -> LegacySettings {
        guard fileExists(url) else { return .none }

        do {
            let settings = try Self.loadSettings(from: url)
            print("[SettingsManager] Migrated settings from legacy Electron location")
            return .migrated(settings)
        } catch {
            // The app starts with the default settings, so the reason has to be
            // visible. The legacy file stays on disk, so the user can recover
            // it by hand.
            let error = SettingsManagerError.decodeFailed(
                path: url.path,
                reason: "the legacy settings could not be read, so the app is using the default settings. "
                    + "The file was kept so you can recover it by hand."
            )
            legacySettingsNotice = error
            report(error)
            return .unreadable
        }
    }

    /// Reports a legacy file that is next to a settings file.
    ///
    /// The legacy file is only imported when no settings file exists, so a
    /// legacy file that is still there was either never imported, or it was
    /// imported and could not be moved aside. The content tells the two
    /// apart: a legacy file that holds the settings of the app was already
    /// imported.
    private func reportLegacyFileBesideTheSettingsFile(
        _ legacyURL: URL,
        loadedSettings: WallpaperSettings?
    ) {
        if let loadedSettings,
           let legacySettings = try? Self.loadSettings(from: legacyURL),
           legacySettings == loadedSettings {
            // The import already happened. The file is moved aside now, so
            // the next launch does not see it again.
            moveLegacyFileAside(legacyURL)
            return
        }
        // The legacy file was not imported: it holds other settings or it
        // cannot be read at all. The file stays, so the user can import it
        // by hand, and the message stays visible.
        let notice = SettingsManagerError.legacySettingsNotImported(path: legacyURL.path)
        legacySettingsNotice = notice
        report(notice)
    }

    /// Moves the legacy file aside, so the next launch does not import it again.
    ///
    /// The file is renamed, not deleted, so its bytes survive.
    private func moveLegacyFileAside(_ legacyURL: URL) {
        switch Self.renameLegacyFile(legacyURL, fileManager: fileManager) {
        case .success:
            break
        case .failure(let error):
            report(error)
        }
    }

    /// Renames the legacy file, so the next launch does not import it again.
    ///
    /// The file is renamed, not deleted, so its bytes survive.
    nonisolated private static func renameLegacyFile(
        _ legacyURL: URL,
        fileManager: FileManager
    ) -> Result<Void, SettingsManagerError> {
        let migratedURL = legacyURL
            .deletingLastPathComponent()
            .appendingPathComponent(legacyURL.lastPathComponent + ".migrated")
        do {
            if fileManager.fileExists(atPath: migratedURL.path) {
                // An older migrated file is replaced by the one of this move.
                try? fileManager.removeItem(at: migratedURL)
            }
            try fileManager.moveItem(at: legacyURL, to: migratedURL)
            return .success(())
        } catch {
            // The settings were imported, only the move aside failed.
            return .failure(.legacySettingsNotMoved(path: legacyURL.path))
        }
    }

    /// Imports the legacy settings file.
    ///
    /// The write and the rename run on the write queue, so the import cannot
    /// interleave with another write. The legacy file is renamed, not
    /// deleted, so its bytes survive and the next launch does not import it
    /// again.
    nonisolated private static func importLegacySettings(
        _ settings: SettingsBox<WallpaperSettings>,
        from legacyURL: URL,
        to settingsURL: URL,
        fileManager: FileManager,
        beforeWrite: (@Sendable () -> Void)?,
        onDisk: SettingsBox<WallpaperSettings?>
    ) -> Result<WallpaperSettings, SettingsManagerError> {
        let written: WallpaperSettings
        switch performWrite(settings, to: settingsURL, beforeWrite: beforeWrite) {
        case .success(let value):
            written = value
            // The settings file holds the imported settings now.
            onDisk.value = value
        case .failure(let error):
            return .failure(error)
        }

        switch renameLegacyFile(legacyURL, fileManager: fileManager) {
        case .success:
            return .success(written)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func switchSettingsLocation(to directory: URL, customDirectoryPath: String?) throws {
        let normalized = directory.standardizedFileURL
        let destinationURL = normalized.appendingPathComponent("settings.json")
        let previousURL = settingsURL

        do {
            try Self.createDirectoryIfNeeded(at: normalized)

            // The pending writes have to land before the old file is moved
            // aside: a write that lands later would put the file back.
            writeQueue.sync {}

            let destinationSettings: WallpaperSettings
            if fileExists(destinationURL) {
                // Adopting a synchronized folder must never overwrite its existing settings.
                destinationSettings = try Self.loadSettings(from: destinationURL)
            } else {
                destinationSettings = settings
                _ = try writeNow(to: destinationURL).get()
            }

            stopFileWatcher()
            settingsDirectory = normalized
            settingsURL = destinationURL
            publish(destinationSettings)
            // The file in the new location holds the settings that were
            // adopted.
            lastKnownOnDisk.value = destinationSettings

            if let customDirectoryPath {
                userDefaults.set(customDirectoryPath, forKey: Self.customDirectoryDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: Self.customDirectoryDefaultsKey)
            }

            clearError()
            startFileWatcher()

            movePreviousSettingsFileAside(from: previousURL)
        } catch let error as SettingsManagerError {
            report(error)
            throw error
        } catch {
            let wrapped = SettingsManagerError.readFailed(path: destinationURL.path, reason: error.localizedDescription)
            report(wrapped)
            throw wrapped
        }
    }

    /// Moves the settings file of the old folder aside.
    ///
    /// The file is renamed, not deleted, so its bytes survive. A file that is
    /// left behind would be adopted silently when the old folder is chosen
    /// again, and the settings made in between would be lost.
    private func movePreviousSettingsFileAside(from url: URL) {
        guard url != settingsURL, fileExists(url) else { return }
        let migratedURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".migrated")
        if fileExists(migratedURL) {
            // An older migrated file is replaced by the one of this move.
            try? fileManager.removeItem(at: migratedURL)
        }
        do {
            try fileManager.moveItem(at: url, to: migratedURL)
        } catch {
            report(.renameFailed(path: url.path, reason: error.localizedDescription))
        }
    }

    /// Stores the new settings and publishes them.
    ///
    /// The box is filled before the change is published, so a subscriber
    /// reads the new value while it handles the change.
    private func publish(_ settings: WallpaperSettings) {
        currentSettings.value = settings
        settingsSubject.send(settings)
    }

    /// Writes the settings file on the write queue.
    ///
    /// The write runs the settings that are current when it runs, so a change
    /// that lands while a write waits is never overwritten by an older
    /// snapshot. The writes run one after the other, so they cannot interleave
    /// into a corrupt file.
    private func enqueueWrite(to url: URL, createsDirectory: Bool = false) {
        let settings = currentSettings
        let beforeWrite = self.beforeWrite
        let counters = writeQueueCounters
        let onDisk = lastKnownOnDisk
        counters.writeEnqueued()
        writeQueue.async { [weak self] in
            let result = Self.performWrite(
                settings,
                to: url,
                createsDirectory: createsDirectory,
                beforeWrite: beforeWrite
            )
            if case .success(let written) = result {
                // The write landed, so the file holds the written settings.
                onDisk.value = written
            }
            // The write has landed, so the file holds the settings that were
            // current when it ran.
            counters.writeLanded()
            Task { @MainActor [weak self] in
                self?.finishWrite(result)
            }
        }
    }

    /// Writes the settings file and waits for the result.
    ///
    /// The startup and the switch of the settings location need the file
    /// before they continue, so they wait for the write.
    private func writeNow(to url: URL) -> Result<WallpaperSettings, SettingsManagerError> {
        let settings = currentSettings
        let beforeWrite = self.beforeWrite
        let onDisk = lastKnownOnDisk
        return writeQueue.sync {
            let result = Self.performWrite(settings, to: url, beforeWrite: beforeWrite)
            if case .success(let written) = result {
                // The write landed, so the file holds the written settings.
                onDisk.value = written
            }
            return result
        }
    }

    /// Writes the settings to the file. The function runs on the write queue.
    ///
    /// The settings are read right before the write, so a change that landed
    /// while the write waited is in the file.
    nonisolated private static func performWrite(
        _ settings: SettingsBox<WallpaperSettings>,
        to url: URL,
        createsDirectory: Bool = false,
        beforeWrite: (@Sendable () -> Void)?
    ) -> Result<WallpaperSettings, SettingsManagerError> {
        beforeWrite?()
        do {
            if createsDirectory {
                try createDirectoryIfNeeded(at: url.deletingLastPathComponent())
            }
            let written = settings.value.normalized()
            try persist(written, to: url)
            return .success(written)
        } catch let error as SettingsManagerError {
            return .failure(error)
        } catch {
            return .failure(.writeFailed(path: url.path, reason: error.localizedDescription))
        }
    }

    /// Reports the result of a write that ran on the write queue.
    private func finishWrite(_ result: Result<WallpaperSettings, SettingsManagerError>) {
        switch result {
        case .success:
            // The file is up to date now, so the watcher can watch it.
            startFileWatcher()
            clearError()
        case .failure(let error):
            report(error)
        }
    }

    private nonisolated static func createDirectoryIfNeeded(at directory: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw SettingsManagerError.createDirectoryFailed(
                path: directory.path,
                reason: error.localizedDescription
            )
        }
    }

    /// Moves an unreadable settings file next to it, so the next save cannot
    /// destroy the only copy of the user's settings.
    ///
    /// Returns `true` when the unreadable content is stored at the `.corrupt`
    /// path. The caller must not overwrite the unreadable file when it is
    /// `false`.
    private func quarantineUnreadableFile(at url: URL) -> Bool {
        let corruptURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".corrupt")
        if fileManager.fileExists(atPath: corruptURL.path) {
            try? fileManager.removeItem(at: corruptURL)
        }
        do {
            try fileManager.moveItem(at: url, to: corruptURL)
            return true
        } catch {
            // The copy stays in place: the content survives even when the move fails.
            do {
                try fileManager.copyItem(at: url, to: corruptURL)
                return true
            } catch {
                return false
            }
        }
    }

    private nonisolated static func loadSettings(from url: URL) throws -> WallpaperSettings {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsManagerError.readFailed(path: url.path, reason: error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(WallpaperSettings.self, from: data).normalized()
        } catch {
            throw SettingsManagerError.decodeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    private nonisolated static func persist(_ settings: WallpaperSettings, to url: URL) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(settings.normalized())
        } catch {
            throw SettingsManagerError.encodeFailed(reason: error.localizedDescription)
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw SettingsManagerError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }


    private func startFileWatcher() {
        guard fileWatcherSource == nil else { return }

        let fd = open(settingsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalChangeHandling()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcherSource = source
    }

    private func stopFileWatcher() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    private func scheduleExternalChangeHandling() {
        pendingExternalChangeTask?.cancel()
        pendingExternalChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            self?.handleExternalChange()
        }
    }

    private func handleExternalChange() {
        pendingExternalChangeTask = nil
        // shortcut: the watcher is stopped while the reload reads the file, a write in that window is only caught by the modification-date re-read, upgrade when the watcher can stay live during the read
        stopFileWatcher()

        let url = settingsURL
        let modificationDateBeforeIO = modificationDate(of: url)
        externalChangeGeneration &+= 1
        let generation = externalChangeGeneration
        let counters = writeQueueCounters
        let onDisk = lastKnownOnDisk

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Self.performExternalChangeIO(
                url: url,
                currentSettings: { @MainActor in self.settings },
                fileExists: self.fileExists,
                beforeRead: self.beforeRead,
                writeQueueState: { counters.snapshot },
                onDisk: onDisk
            )
            guard self.settingsURL == url else { self.startFileWatcher(); return }
            let isCurrent = generation == self.externalChangeGeneration
            if isCurrent {
                self.applyExternalChangeOutcome(outcome)
            }
            self.startFileWatcher()

            // A write that landed while the watcher was stopped is never
            // delivered, so the file is read once more. The watcher stays on
            // this time, so no write can be missed.
            if isCurrent, self.modificationDate(of: url) != modificationDateBeforeIO {
                self.reloadChangedFile(url: url, generation: generation)
            }
        }
    }

    /// Reads the file again after a change that landed while the watcher was
    /// stopped. The watcher keeps running, so a write can no longer be lost.
    private func reloadChangedFile(url: URL, generation: UInt) {
        let counters = writeQueueCounters
        let onDisk = lastKnownOnDisk
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Self.performExternalChangeIO(
                url: url,
                currentSettings: { @MainActor in self.settings },
                fileExists: self.fileExists,
                beforeRead: self.beforeRead,
                writeQueueState: { counters.snapshot },
                onDisk: onDisk
            )
            guard self.settingsURL == url, generation == self.externalChangeGeneration else { return }
            self.applyExternalChangeOutcome(outcome)
        }
    }

    private func applyExternalChangeOutcome(_ outcome: Result<ExternalChangeOutcome, SettingsManagerError>) {
        switch outcome {
        case .success(.unchanged):
            keepTheSettingsInMemory()
        case .success(.reloaded(let reloaded, let snapshot)):
            // The decision was made off the main actor, so a change of the
            // app can land while the result waits to be published. The
            // settings in memory are the truth and the file follows, so the
            // file must not overwrite a change that is newer than the one
            // the reload saw.
            beforePublish?()
            guard isStillCurrent(snapshot) else {
                keepTheSettingsInMemory()
                break
            }
            // The file holds the newest settings, so the app adopts them.
            lastKnownOnDisk.value = reloaded
            publish(reloaded)
            clearError()
        case .success(.recreated):
            // The file is written from the settings that are current when the
            // write runs, so a change that lands in the meantime is not lost.
            // The file was deleted outside the app, so there is no content on
            // the disk to remember until the write lands.
            enqueueWrite(to: settingsURL, createsDirectory: true)
            clearError()
        case .failure(let error):
            report(error)
        }
    }

    /// Keeps the settings in memory and the rules of the error message.
    ///
    /// A failed write is still true: the file on the disk is older than the
    /// settings in memory, so the message must stay visible.
    private func keepTheSettingsInMemory() {
        if case .writeFailed? = lastError { return }
        clearError()
    }

    /// Whether the settings in memory are still the ones the reload saw.
    ///
    /// A change that landed after the decision of the reload is newer than
    /// the file, so the file must not overwrite it. A write that landed
    /// since the decision means the file is older than the settings in
    /// memory, and a write that is still pending means the file is about to
    /// be older.
    private func isStillCurrent(_ snapshot: ExternalChangeSnapshot) -> Bool {
        if currentSettings.value != snapshot.settings { return false }
        let counters = writeQueueCounters.snapshot
        if counters.completedWrites != snapshot.writeQueue.completedWrites { return false }
        if counters.pendingWrites > 0 { return false }
        return true
    }

    private func modificationDate(of url: URL) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    private nonisolated static func performExternalChangeIO(
        url: URL,
        currentSettings: @MainActor @Sendable () async -> WallpaperSettings,
        fileExists: @Sendable (URL) -> Bool,
        beforeRead: (@Sendable () -> Void)?,
        writeQueueState: @Sendable () -> WriteQueueSnapshot,
        onDisk: SettingsBox<WallpaperSettings?>
    ) async -> Result<ExternalChangeOutcome, SettingsManagerError> {
        if fileExists(url) {
            do {
                // The file is not authoritative over the settings in memory:
                // a change that lands while the file is read is newer than
                // the snapshot, so the snapshot must not overwrite it. The
                // settings in memory are read before and after the read of
                // the file, so the change is noticed. The writes of the app
                // count too: a change that is not on the disk yet is newer
                // than the file, so the file must not overwrite it either.
                // The content the app last knew on the disk counts too: a
                // file that holds it carries nothing the app does not know,
                // so the settings in memory stay. That is the case after a
                // failed write, where the file still holds the older content.
                let before = await currentSettings()
                let writesBefore = writeQueueState()
                beforeRead?()
                let reloaded = try Self.loadSettings(from: url)
                let after = await currentSettings()
                let writesAfter = writeQueueState()
                if reloaded == before {
                    // The file still holds the settings we last knew.
                    return .success(.unchanged)
                }
                if let known = onDisk.value, known == reloaded {
                    // The file holds the content the app last knew on the
                    // disk, so it carries nothing the app does not know.
                    return .success(.unchanged)
                }
                if after != before {
                    // A change landed while the file was read: the settings in
                    // memory are the newer ones, so the file must not
                    // overwrite them. The queued write persists the change.
                    return .success(.unchanged)
                }
                if writesAfter.pendingWrites > 0 {
                    // A change of the app is not on the disk yet, so the file
                    // is older than the settings in memory. The queued write
                    // puts the change on the disk.
                    return .success(.unchanged)
                }
                if writesAfter.completedWrites != writesBefore.completedWrites {
                    // A write landed while the file was read: the file can
                    // hold a value that is older than the settings in memory.
                    return .success(.unchanged)
                }
                // The file holds something else, the settings in memory did
                // not move while it was read and no write of the app is on
                // its way, so the file was changed outside the app.
                //
                // The snapshot travels with the result: the decision is made
                // off the main actor, so the settings in memory can move on
                // before the result is published. The publish compares the
                // settings in memory with the snapshot and drops the result
                // when they differ.
                let snapshot = ExternalChangeSnapshot(settings: after, writeQueue: writesAfter)
                return .success(.reloaded(reloaded, snapshot: snapshot))
            } catch let error as SettingsManagerError {
                return .failure(error)
            } catch {
                return .failure(.readFailed(path: url.path, reason: error.localizedDescription))
            }
        } else {
            // An atomic writer temporarily replaces the watched inode. If no replacement
            // arrives, the deleted file is recreated from the last known-good in-memory
            // state. The write runs on the write queue, so it cannot overwrite a change
            // that landed in the meantime.
            return .success(.recreated)
        }
    }


    private func report(_ error: SettingsManagerError) {
        if case .legacySettingsNotMoved = error {
            // The legacy file is still on the disk, so the message has to stay
            // visible: the user has to know the file is there.
            legacySettingsNotice = error
        }
        lastError = error
        onError?(error)
        print("[SettingsManager] \(error.localizedDescription)")
    }

    /// Reports a failed write.
    private func report(_ result: Result<WallpaperSettings, SettingsManagerError>) {
        if case .failure(let error) = result {
            report(error)
        }
    }

    private func clearError() {
        // The pending legacy migration keeps its message: it explains why the
        // app starts with the default settings.
        if let legacySettingsNotice {
            lastError = legacySettingsNotice
            return
        }
        lastError = nil
    }
}

/// What the reload saw when it made its decision.
///
/// The decision is made off the main actor, so the settings in memory can
/// move on before the result is published. The snapshot is what the publish
/// compares the settings in memory against.
private struct ExternalChangeSnapshot: Sendable, Equatable {
    /// The settings in memory at the end of the read of the file.
    let settings: WallpaperSettings
    /// The state of the write queue at the end of the read of the file.
    let writeQueue: WriteQueueSnapshot
}

/// The state of the write queue at a moment in time.
private struct WriteQueueSnapshot: Sendable, Equatable {
    /// The writes that are enqueued but have not landed yet.
    let pendingWrites: Int
    /// The writes that landed since the app started.
    let completedWrites: Int
}

/// Counts the writes of the settings file.
///
/// The write queue fills the counters and the reload reads them, so a lock
/// guards them.
private final class WriteQueueCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var completed = 0

    /// A write was enqueued and has not landed yet.
    func writeEnqueued() {
        lock.lock()
        pending += 1
        lock.unlock()
    }

    /// The write landed, so the file holds the settings of that moment.
    func writeLanded() {
        lock.lock()
        pending -= 1
        completed += 1
        lock.unlock()
    }

    /// The counters at this moment.
    var snapshot: WriteQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return WriteQueueSnapshot(pendingWrites: pending, completedWrites: completed)
    }
}

/// Holds the settings that the write queue writes.
///
/// The main actor fills the box and the write queue reads it, so a lock
/// guards it.
private final class SettingsBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}
