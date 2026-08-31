import Foundation
@testable import WallpaperSelector

@MainActor
final class TestSettingsContext {
    let rootDirectory: URL
    let settingsDirectory: URL
    let defaultSettingsDirectory: URL
    let userDefaults: UserDefaults

    private let userDefaultsSuiteName: String

    init() throws {
        let identifier = UUID().uuidString
        rootDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("wallpaper-selector-tests", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        settingsDirectory = rootDirectory.appendingPathComponent("Settings", isDirectory: true)
        defaultSettingsDirectory = rootDirectory.appendingPathComponent("DefaultSettings", isDirectory: true)
        userDefaultsSuiteName = "com.wallpaper-selector.tests.\(identifier)"

        guard let defaults = UserDefaults(suiteName: userDefaultsSuiteName) else {
            throw TestSettingsContextError.couldNotCreateUserDefaults
        }
        userDefaults = defaults
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        try FileManager.default.createDirectory(
            at: settingsDirectory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func makeSettingsManager(at directory: URL? = nil) -> SettingsManager {
        SettingsManager(
            settingsDirectory: directory ?? settingsDirectory,
            userDefaults: userDefaults,
            defaultSettingsDirectory: defaultSettingsDirectory,
            migrateLegacySettings: false
        )
    }

    func makeSettingsManagerUsingStoredOrDefaultLocation() -> SettingsManager {
        SettingsManager(
            userDefaults: userDefaults,
            defaultSettingsDirectory: defaultSettingsDirectory,
            migrateLegacySettings: false
        )
    }

    func directory(named name: String) -> URL {
        rootDirectory.appendingPathComponent(name, isDirectory: true)
    }
}

private enum TestSettingsContextError: Error {
    case couldNotCreateUserDefaults
}

@MainActor
final class MockWallpaperProvider: WallpaperSetting {
    private(set) var appliedURLs: [URL] = []
    var errorToThrow: Error?

    func setWallpaper(_ url: URL) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        appliedURLs.append(url)
    }

    func reset() {
        appliedURLs = []
        errorToThrow = nil
    }
}

enum MockWallpaperProviderError: Error {
    case configuredFailure
}
