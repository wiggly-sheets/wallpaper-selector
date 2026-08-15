import Foundation
import Combine

final class SettingsManager: ObservableObject {

    static let defaultSettingsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WallpaperSelector", isDirectory: true)
    }()

    static let bundleID = "com.wallpaper-selector.macos"

    private(set) var settingsDirectory: URL
    private(set) var settingsURL: URL

    @Published private(set) var settings: WallpaperSettings = .init() {
        didSet { if !isLoading { save() } }
    }

    var onSettingsChanged: (() -> Void)?


    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.wallpaper-selector.settings", qos: .utility)
    private static let customDirectoryDefaultsKey = "WallpaperSelector.settingsDirectory"
    private var isLoading = false


    init(settingsDirectory requestedDirectory: URL? = nil) {
        let storedDirectory = UserDefaults.standard.string(forKey: Self.customDirectoryDefaultsKey).map(URL.init(fileURLWithPath:))
        settingsDirectory = requestedDirectory ?? storedDirectory ?? Self.defaultSettingsDirectory
        settingsURL = settingsDirectory.appendingPathComponent("settings.json")
        ensureDirectoryExists()
        if requestedDirectory == nil { migrateFromLegacyIfNeeded() }
        load()
        startFileWatcher()
    }

    deinit {
        stopFileWatcher()
    }


    func update(_ mutation: (inout WallpaperSettings) -> Void) {
        var newValue = self.settings
        mutation(&newValue)
        self.settings = newValue
        onSettingsChanged?()
    }

    func replace(_ newSettings: WallpaperSettings) {
        settings = newSettings
        onSettingsChanged?()
    }

    func relocateSettings(to directory: URL) throws {
        let normalized = directory.standardizedFileURL
        guard normalized.path != settingsDirectory.path else { return }
        try fileManager.createDirectory(at: normalized, withIntermediateDirectories: true)

        stopFileWatcher()
        settingsDirectory = normalized
        settingsURL = normalized.appendingPathComponent("settings.json")
        UserDefaults.standard.set(normalized.path, forKey: Self.customDirectoryDefaultsKey)
        save()
        startFileWatcher()
        onSettingsChanged?()
    }

    func useDefaultSettingsLocation() throws {
        try relocateSettings(to: Self.defaultSettingsDirectory)
        UserDefaults.standard.removeObject(forKey: Self.customDirectoryDefaultsKey)
    }


    private func migrateFromLegacyIfNeeded() {
        guard let legacyURL = Self.legacySettingsURL else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: settingsURL.path) else { return }

        do {
            let data = try Data(contentsOf: legacyURL)
            let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: data)
            settings = decoded
            save()
            print("[SettingsManager] Migrated settings from legacy Electron location")
        } catch {
            print("[SettingsManager] Failed to migrate legacy settings: \(error)")
        }
    }

    private static var legacySettingsURL: URL? {
        guard let home = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first else {
            return nil
        }
        return home.appendingPathComponent(".wallpaper-selector/settings.json")
    }


    private func ensureDirectoryExists() {
        try? fileManager.createDirectory(
            at: settingsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func load() {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            save()
            return
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            isLoading = true
            defer { isLoading = false }
            let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: data)
            settings = decoded
        } catch {
            print("[SettingsManager] Failed to load settings, using defaults: \(error)")
            isLoading = true
            settings = .init()
            isLoading = false
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL, options: [.atomic])
        } catch {
            print("[SettingsManager] Failed to save settings: \(error)")
        }
    }


    private func startFileWatcher() {
        let fd = open(settingsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleExternalChange()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcherSource = source
    }

    private func stopFileWatcher() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    private func handleExternalChange() {
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.stopFileWatcher()
            self.load()
            self.startFileWatcher()
            self.onSettingsChanged?()
        }
    }
}
