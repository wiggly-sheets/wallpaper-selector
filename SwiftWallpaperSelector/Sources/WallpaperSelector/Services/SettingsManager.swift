import Foundation
import Combine

enum SettingsManagerError: LocalizedError, Equatable {
    case createDirectoryFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case encodeFailed(reason: String)
    case writeFailed(path: String, reason: String)

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

    private(set) var settingsDirectory: URL
    private(set) var settingsURL: URL

    @Published private(set) var settings: WallpaperSettings = .init()
    @Published private(set) var lastError: SettingsManagerError?

    var onSettingsChanged: (() -> Void)?
    var onError: ((SettingsManagerError) -> Void)?


    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var pendingExternalChangeTask: Task<Void, Never>?
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.wallpaper-selector.settings", qos: .utility)
    private let userDefaults: UserDefaults
    private let configuredDefaultSettingsDirectory: URL
    private let migrateLegacySettings: Bool


    private enum ExternalChangeOutcome {
        case unchanged
        case reloaded(WallpaperSettings)
        case recreated
    }


    init(
        settingsDirectory requestedDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        defaultSettingsDirectory: URL = SettingsManager.defaultSettingsDirectory,
        fileManager: FileManager = .default,
        migrateLegacySettings: Bool = true
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.configuredDefaultSettingsDirectory = defaultSettingsDirectory.standardizedFileURL
        self.migrateLegacySettings = migrateLegacySettings

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
            try Self.persist(normalizedSettings, to: settingsURL)
            settings = normalizedSettings
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
            try Self.createDirectoryIfNeeded(at: settingsDirectory, using: fileManager)

            if shouldMigrateLegacy,
               migrateLegacySettings,
               !fileManager.fileExists(atPath: settingsURL.path),
               let migrated = try loadLegacySettingsIfAvailable() {
                try Self.persist(migrated, to: settingsURL)
                settings = migrated
                return
            }

            if fileManager.fileExists(atPath: settingsURL.path) {
                settings = try Self.loadSettings(from: settingsURL)
            } else {
                try Self.persist(settings, to: settingsURL)
            }
        } catch let error as SettingsManagerError {
            report(error)
        } catch {
            report(.readFailed(path: settingsURL.path, reason: error.localizedDescription))
        }
    }

    private func loadLegacySettingsIfAvailable() throws -> WallpaperSettings? {
        guard let legacyURL = Self.legacySettingsURL else { return nil }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return nil }

        do {
            let settings = try Self.loadSettings(from: legacyURL)
            print("[SettingsManager] Migrated settings from legacy Electron location")
            return settings
        } catch let error as SettingsManagerError {
            report(error)
            return nil
        }
    }

    private static var legacySettingsURL: URL? {
        guard let home = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first else {
            return nil
        }
        return home.appendingPathComponent(".wallpaper-selector/settings.json")
    }


    private func switchSettingsLocation(to directory: URL, customDirectoryPath: String?) throws {
        let normalized = directory.standardizedFileURL
        let destinationURL = normalized.appendingPathComponent("settings.json")

        do {
            try Self.createDirectoryIfNeeded(at: normalized, using: fileManager)

            let destinationSettings: WallpaperSettings
            if fileManager.fileExists(atPath: destinationURL.path) {
                // Adopting a synchronized folder must never overwrite its existing settings.
                destinationSettings = try Self.loadSettings(from: destinationURL)
            } else {
                destinationSettings = settings
                try Self.persist(destinationSettings, to: destinationURL)
            }

            stopFileWatcher()
            settingsDirectory = normalized
            settingsURL = destinationURL
            settings = destinationSettings

            if let customDirectoryPath {
                userDefaults.set(customDirectoryPath, forKey: Self.customDirectoryDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: Self.customDirectoryDefaultsKey)
            }

            clearError()
            startFileWatcher()
            onSettingsChanged?()
        } catch let error as SettingsManagerError {
            report(error)
            throw error
        } catch {
            let wrapped = SettingsManagerError.readFailed(path: destinationURL.path, reason: error.localizedDescription)
            report(wrapped)
            throw wrapped
        }
    }

    private nonisolated static func createDirectoryIfNeeded(at directory: URL, using fileManager: FileManager) throws {
        do {
            try fileManager.createDirectory(
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
        let directory = settingsDirectory
        let fallback = settings

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Self.performExternalChangeIO(
                url: url,
                directory: directory,
                fallback: fallback,
                fileManager: self.fileManager
            )
            guard self.settingsURL == url else { self.startFileWatcher(); return }
            switch outcome {
            case .success(.unchanged):
                self.clearError()
            case .success(.reloaded(let reloaded)):
                self.settings = reloaded
                self.onSettingsChanged?()
                self.clearError()
            case .success(.recreated):
                self.onSettingsChanged?()
                self.clearError()
            case .failure(let error):
                self.report(error)
            }
            self.startFileWatcher()
        }
    }

    private nonisolated static func performExternalChangeIO(
        url: URL,
        directory: URL,
        fallback: WallpaperSettings,
        fileManager: FileManager
    ) async -> Result<ExternalChangeOutcome, SettingsManagerError> {
        if fileManager.fileExists(atPath: url.path) {
            do {
                let reloaded = try Self.loadSettings(from: url)
                return .success(reloaded == fallback ? .unchanged : .reloaded(reloaded))
            } catch let error as SettingsManagerError {
                return .failure(error)
            } catch {
                return .failure(.readFailed(path: url.path, reason: error.localizedDescription))
            }
        } else {
            // An atomic writer temporarily replaces the watched inode. If no replacement
            // arrives, recreate the deleted file from the last known-good in-memory state.
            do {
                try Self.createDirectoryIfNeeded(at: directory, using: fileManager)
                try Self.persist(fallback, to: url)
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
        lastError = nil
    }
}
