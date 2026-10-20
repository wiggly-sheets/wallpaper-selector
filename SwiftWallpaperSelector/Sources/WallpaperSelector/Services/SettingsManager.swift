import Foundation
import Combine

enum SettingsManagerError: LocalizedError, Equatable {
    case createDirectoryFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)
    case renameFailed(path: String, reason: String)

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
    var settings: WallpaperSettings {
        settingsSubject.value
    }

    /// Publishes every settings change. The new value is stored before it is
    /// published, so `settings` already holds it while subscribers run.
    var settingsPublisher: AnyPublisher<WallpaperSettings, Never> {
        settingsSubject.eraseToAnyPublisher()
    }

    var onSettingsChanged: (() -> Void)?
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
    private let userDefaults: UserDefaults
    private let configuredDefaultSettingsDirectory: URL
    private let migrateLegacySettings: Bool
    private let legacySettingsURL: URL?

    /// Counts the external reloads. A reload that finishes after a newer one
    /// started is stale and must not overwrite the newer settings.
    private(set) var externalChangeGeneration: UInt = 0

    /// The legacy settings file exists but could not be read. The migration
    /// is still pending, so the legacy file stays on disk and the reason for
    /// the default settings is kept visible.
    private var legacyMigrationError: SettingsManagerError?

    var isLegacyMigrationPending: Bool {
        legacyMigrationError != nil
    }


    private enum ExternalChangeOutcome: Sendable {
        case unchanged
        case reloaded(WallpaperSettings)
        case recreated
    }


    init(
        settingsDirectory requestedDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        defaultSettingsDirectory: URL = SettingsManager.defaultSettingsDirectory,
        fileManager: FileManager = .default,
        fileExists: (@Sendable (URL) -> Bool)? = nil,
        migrateLegacySettings: Bool = true,
        legacySettingsURL: URL? = SettingsManager.defaultLegacySettingsURL
    ) {
        self.fileManager = fileManager
        self.fileExists = fileExists ?? { url in FileManager.default.fileExists(atPath: url.path) }
        self.userDefaults = userDefaults
        self.configuredDefaultSettingsDirectory = defaultSettingsDirectory.standardizedFileURL
        self.migrateLegacySettings = migrateLegacySettings
        self.legacySettingsURL = legacySettingsURL

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

    @discardableResult
    func update(_ mutation: (inout WallpaperSettings) -> Void) -> Result<Void, SettingsManagerError> {
        var newValue = settings
        mutation(&newValue)
        return replace(newValue)
    }

    @discardableResult
    func replace(_ newSettings: WallpaperSettings) -> Result<Void, SettingsManagerError> {
        let normalizedSettings = newSettings.normalized()
        do {
            // shortcut: the write blocks the main actor, upgrade when the persistence API can write off the main actor
            try Self.persist(normalizedSettings, to: settingsURL)
            settingsSubject.send(normalizedSettings)
            // The settings file can be missing, for example when the legacy
            // migration is still pending. The watcher can only watch a file
            // that exists, so it starts with the first write.
            startFileWatcher()
            clearError()
            onSettingsChanged?()
            return .success(())
        } catch let error as SettingsManagerError {
            report(error)
            return .failure(error)
        } catch {
            let wrapped = SettingsManagerError.writeFailed(path: settingsURL.path, reason: error.localizedDescription)
            report(wrapped)
            return .failure(wrapped)
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

            if shouldMigrateLegacy,
               migrateLegacySettings,
               !fileExists(settingsURL) {
                switch loadLegacySettingsIfAvailable() {
                case .migrated(let migrated):
                    try Self.persist(migrated, to: settingsURL)
                    settingsSubject.send(migrated)
                    return
                case .unreadable:
                    // The legacy file is the only copy of the settings: the
                    // location stays empty, so the next launch retries the
                    // migration.
                    return
                case .none:
                    break
                }
            }

            if fileExists(settingsURL) {
                do {
                    settingsSubject.send(try Self.loadSettings(from: settingsURL))
                } catch let error as SettingsManagerError {
                    // The unreadable file is the only copy of the user's folders,
                    // themes and history: keep it before anything can overwrite it.
                    let quarantined = quarantineUnreadableFile(at: settingsURL)
                    report(error)
                    // A fresh default file takes its place, so the watcher can run.
                    // Without a safe copy the unreadable file has to stay.
                    if quarantined {
                        // A failed write must be reported: the app would run
                        // without any settings file at all.
                        try Self.persist(settings, to: settingsURL)
                    }
                }
            } else {
                try Self.persist(settings, to: settingsURL)
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

    private func loadLegacySettingsIfAvailable() -> LegacySettings {
        guard let legacyURL = legacySettingsURL else { return .none }
        guard fileExists(legacyURL) else { return .none }

        do {
            let settings = try Self.loadSettings(from: legacyURL)
            print("[SettingsManager] Migrated settings from legacy Electron location")
            return .migrated(settings)
        } catch {
            // The app starts with the default settings, so the reason has to be
            // visible. The legacy file stays on disk, so the user can recover
            // it by hand.
            let error = SettingsManagerError.decodeFailed(
                path: legacyURL.path,
                reason: "the legacy settings could not be read, so the app is using the default settings. "
                    + "The file was kept so you can recover it by hand."
            )
            legacyMigrationError = error
            report(error)
            return .unreadable
        }
    }

    private func switchSettingsLocation(to directory: URL, customDirectoryPath: String?) throws {
        let normalized = directory.standardizedFileURL
        let destinationURL = normalized.appendingPathComponent("settings.json")
        let previousURL = settingsURL

        do {
            try Self.createDirectoryIfNeeded(at: normalized)

            let destinationSettings: WallpaperSettings
            if fileExists(destinationURL) {
                // Adopting a synchronized folder must never overwrite its existing settings.
                destinationSettings = try Self.loadSettings(from: destinationURL)
            } else {
                destinationSettings = settings
                try Self.persist(destinationSettings, to: destinationURL)
            }

            stopFileWatcher()
            settingsDirectory = normalized
            settingsURL = destinationURL
            settingsSubject.send(destinationSettings)

            if let customDirectoryPath {
                userDefaults.set(customDirectoryPath, forKey: Self.customDirectoryDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: Self.customDirectoryDefaultsKey)
            }

            clearError()
            startFileWatcher()
            onSettingsChanged?()

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
        stopFileWatcher()

        let url = settingsURL
        let modificationDateBeforeIO = modificationDate(of: url)
        externalChangeGeneration &+= 1
        let generation = externalChangeGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Self.performExternalChangeIO(
                url: url,
                directory: self.settingsDirectory,
                currentSettings: { @MainActor in self.settings },
                fileExists: self.fileExists
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Self.performExternalChangeIO(
                url: url,
                directory: self.settingsDirectory,
                currentSettings: { @MainActor in self.settings },
                fileExists: self.fileExists
            )
            guard self.settingsURL == url, generation == self.externalChangeGeneration else { return }
            self.applyExternalChangeOutcome(outcome)
        }
    }

    private func applyExternalChangeOutcome(_ outcome: Result<ExternalChangeOutcome, SettingsManagerError>) {
        switch outcome {
        case .success(.unchanged):
            // A failed write is still true: the file on disk is older than the
            // settings in memory, so the message must stay visible.
            if case .writeFailed? = lastError { break }
            clearError()
        case .success(.reloaded(let reloaded)):
            settingsSubject.send(reloaded)
            onSettingsChanged?()
            clearError()
        case .success(.recreated):
            onSettingsChanged?()
            clearError()
        case .failure(let error):
            report(error)
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    private nonisolated static func performExternalChangeIO(
        url: URL,
        directory: URL,
        currentSettings: @MainActor @Sendable () async -> WallpaperSettings,
        fileExists: @Sendable (URL) -> Bool
    ) async -> Result<ExternalChangeOutcome, SettingsManagerError> {
        if fileExists(url) {
            do {
                let reloaded = try Self.loadSettings(from: url)
                let current = await currentSettings()
                return .success(reloaded == current ? .unchanged : .reloaded(reloaded))
            } catch let error as SettingsManagerError {
                return .failure(error)
            } catch {
                return .failure(.readFailed(path: url.path, reason: error.localizedDescription))
            }
        } else {
            // An atomic writer temporarily replaces the watched inode. If no replacement
            // arrives, recreate the deleted file from the last known-good in-memory state.
            do {
                try Self.createDirectoryIfNeeded(at: directory)
                // The settings are read when the file is written, not before
                // the IO started: a local change that landed in between must
                // not be overwritten by an older snapshot.
                try Self.persist(await currentSettings(), to: url)
                return .success(.recreated)
            } catch let error as SettingsManagerError {
                return .failure(error)
            } catch {
                return .failure(.readFailed(path: url.path, reason: error.localizedDescription))
            }
        }
    }


    private func report(_ error: SettingsManagerError) {
        lastError = error
        onError?(error)
        print("[SettingsManager] \(error.localizedDescription)")
    }

    private func clearError() {
        // The pending legacy migration keeps its message: it explains why the
        // app starts with the default settings.
        if let legacyMigrationError {
            lastError = legacyMigrationError
            return
        }
        lastError = nil
    }
}
