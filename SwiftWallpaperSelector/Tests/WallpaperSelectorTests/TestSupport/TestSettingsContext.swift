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
        // A test can leave the settings folder read-only, and removing a file
        // out of it needs write permission, so the mode is restored first.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: settingsDirectory.path
        )
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func makeSettingsManager(
        at directory: URL? = nil,
        beforeWrite: (@Sendable () -> Void)? = nil,
        beforeRead: (@Sendable () -> Void)? = nil,
        beforePublish: (@MainActor () -> Void)? = nil
    ) -> SettingsManager {
        SettingsManager(
            settingsDirectory: directory ?? settingsDirectory,
            userDefaults: userDefaults,
            defaultSettingsDirectory: defaultSettingsDirectory,
            migrateLegacySettings: false,
            beforeWrite: beforeWrite,
            beforeRead: beforeRead,
            beforePublish: beforePublish
        )
    }

    func makeSettingsManagerUsingStoredOrDefaultLocation() -> SettingsManager {
        SettingsManager(
            userDefaults: userDefaults,
            defaultSettingsDirectory: defaultSettingsDirectory,
            migrateLegacySettings: false
        )
    }

    /// A manager that migrates the settings of the given legacy file.
    func makeSettingsManagerMigratingLegacySettings(
        from legacyURL: URL,
        fileManager: FileManager = .default
    ) -> SettingsManager {
        SettingsManager(
            userDefaults: userDefaults,
            defaultSettingsDirectory: defaultSettingsDirectory,
            fileManager: fileManager,
            migrateLegacySettings: true,
            legacySettingsURL: legacyURL
        )
    }

    func directory(named name: String) -> URL {
        rootDirectory.appendingPathComponent(name, isDirectory: true)
    }
}

private enum TestSettingsContextError: Error {
    case couldNotCreateUserDefaults
}

/// The names of the notifications the tests use.
///
/// Every observer of the distributed centre receives the real notification
/// of macOS, so a test that listens to it breaks when the appearance of the
/// machine changes while the suite runs. The tests listen to a name that
/// nothing posts.
enum TestNotifications {
    /// The change of the appearance of the system.
    static let appearanceChanged = Notification.Name("WallpaperSelectorTests.appearanceChanged")
}

@MainActor
final class MockWallpaperProvider: WallpaperSetting {
    private(set) var appliedURLs: [URL] = []
    var errorToThrow: Error?
    /// Called after a wallpaper was recorded, so a test can await the effect.
    var onSetWallpaper: ((URL) -> Void)?

    func setWallpaper(_ url: URL) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        appliedURLs.append(url)
        onSetWallpaper?(url)
    }

    func reset() {
        appliedURLs = []
        errorToThrow = nil
        onSetWallpaper = nil
    }
}

enum MockWallpaperProviderError: Error {
    case configuredFailure
}
