import XCTest
@testable import WallpaperSelector

@MainActor
final class SettingsManagerTests: XCTestCase {
    func testRelocationToEmptyDirectoryCopiesCurrentSettingsThenPersistsLocation() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let current = WallpaperSettings(folderPaths: ["/current"], currentWallpaper: "/current/a.jpg")
        XCTAssertSuccess(manager.replace(current))
        let destination = context.directory(named: "Synchronized")

        try manager.relocateSettings(to: destination)

        let stored = try decodeSettings(at: destination.appendingPathComponent("settings.json"))
        XCTAssertEqual(stored, current)
        XCTAssertEqual(manager.settings, current)
        XCTAssertEqual(manager.settingsDirectory, destination)
        XCTAssertEqual(
            context.userDefaults.string(forKey: SettingsManager.customDirectoryDefaultsKey),
            destination.path
        )
    }

    func testRelocationAdoptsExistingValidSettingsWithoutOverwritingFile() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/current"])))
        let destination = context.directory(named: "Existing")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = WallpaperSettings(
            folderPaths: ["/synchronized"],
            themes: [Theme(id: "theme", name: "Synchronized", folderPaths: ["/synchronized"])],
            activeThemeID: "theme"
        )
        let destinationURL = destination.appendingPathComponent("settings.json")
        let originalData = try encoded(existing, prettyPrinted: true)
        try originalData.write(to: destinationURL)

        try manager.relocateSettings(to: destination)

        XCTAssertEqual(manager.settings, existing)
        XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
    }

    func testRelocationRejectsMalformedExistingSettingsWithoutChangingCurrentState() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let current = WallpaperSettings(folderPaths: ["/current"])
        XCTAssertSuccess(manager.replace(current))
        let originalDirectory = manager.settingsDirectory
        context.userDefaults.set("/previous", forKey: SettingsManager.customDirectoryDefaultsKey)

        let destination = context.directory(named: "Malformed")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destinationURL = destination.appendingPathComponent("settings.json")
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: destinationURL)

        XCTAssertThrowsError(try manager.relocateSettings(to: destination)) { error in
            guard case SettingsManagerError.decodeFailed = error else {
                return XCTFail("Expected decodeFailed, got \(error)")
            }
        }
        XCTAssertEqual(manager.settingsDirectory, originalDirectory)
        XCTAssertEqual(manager.settings, current)
        XCTAssertEqual(try Data(contentsOf: destinationURL), malformed)
        XCTAssertEqual(
            context.userDefaults.string(forKey: SettingsManager.customDirectoryDefaultsKey),
            "/previous"
        )
    }

    func testRelocationFailureDoesNotPersistRequestedLocation() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        context.userDefaults.set("/previous", forKey: SettingsManager.customDirectoryDefaultsKey)
        let regularFile = context.directory(named: "not-a-directory")
        try Data("file".utf8).write(to: regularFile)
        let impossibleDestination = regularFile.appendingPathComponent("child", isDirectory: true)

        XCTAssertThrowsError(try manager.relocateSettings(to: impossibleDestination))

        XCTAssertEqual(
            manager.settingsDirectory.resolvingSymlinksInPath(),
            context.settingsDirectory.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            context.userDefaults.string(forKey: SettingsManager.customDirectoryDefaultsKey),
            "/previous"
        )
    }

    func testUsingDefaultLocationAdoptsExistingSettingsAndClearsCustomLocation() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let expected = WallpaperSettings(folderPaths: ["/default-synchronized"])
        try FileManager.default.createDirectory(
            at: context.defaultSettingsDirectory,
            withIntermediateDirectories: true
        )
        try encoded(expected).write(
            to: context.defaultSettingsDirectory.appendingPathComponent("settings.json")
        )
        context.userDefaults.set(context.settingsDirectory.path, forKey: SettingsManager.customDirectoryDefaultsKey)

        try manager.useDefaultSettingsLocation()

        XCTAssertEqual(manager.settings, expected)
        XCTAssertTrue(manager.isUsingDefaultSettingsDirectory)
        XCTAssertNil(context.userDefaults.string(forKey: SettingsManager.customDirectoryDefaultsKey))
    }

    func testMalformedInitialFileIsReportedAndNotOverwritten() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let malformed = Data("not-json".utf8)
        try malformed.write(to: settingsURL)

        let manager = context.makeSettingsManager()

        guard case .decodeFailed? = manager.lastError else {
            return XCTFail("Expected the malformed settings error to be surfaced")
        }
        XCTAssertEqual(manager.settings, WallpaperSettings())
        XCTAssertEqual(try Data(contentsOf: settingsURL), malformed)
    }

    func testFailedSaveKeepsLastPersistedAndInMemorySettings() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let original = manager.settings
        try FileManager.default.removeItem(at: manager.settingsURL)
        try FileManager.default.removeItem(at: manager.settingsDirectory)
        try Data("not-a-directory".utf8).write(to: manager.settingsDirectory)

        let result = manager.update { $0.folderPaths = ["/must-not-publish"] }

        guard case .failure(.writeFailed) = result else {
            return XCTFail("Expected the failed write to be returned")
        }
        XCTAssertEqual(manager.settings, original)
        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be published")
        }
    }

    func testReplaceNormalizesCrossReferencesPinsAndHistoryBeforePublishingAndSaving() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let input = WallpaperSettings(
            folderPaths: ["/one", "/one", "/two"],
            shortcuts: Shortcuts(showMain: "cmd+1", showPreview: "cmd+1", showMenu: "cmd+2"),
            themes: [
                Theme(
                    id: "kept",
                    name: "Kept",
                    folderPaths: ["/one", "/missing", "/one"],
                    lightWallpaper: "/missing/light.jpg",
                    darkWallpaper: "/one/dark.jpg"
                ),
                Theme(id: "kept", name: "Duplicate", folderPaths: ["/two"])
            ],
            activeThemeID: "missing-theme",
            allFoldersLightWallpaper: "/missing/light.jpg",
            allFoldersDarkWallpaper: "/two/dark.jpg",
            appearanceLightThemeID: "kept",
            appearanceDarkThemeID: "missing-theme",
            historyLimit: 5,
            wallpaperHistory: ["a", "b", "a", "c", "d", "e", "f"]
        )

        XCTAssertSuccess(manager.replace(input))

        let normalized = manager.settings
        XCTAssertEqual(normalized.folderPaths, ["/one", "/two"])
        XCTAssertEqual(normalized.themes.count, 1)
        XCTAssertEqual(normalized.themes[0].folderPaths, ["/one"])
        XCTAssertNil(normalized.themes[0].lightWallpaper)
        XCTAssertEqual(normalized.themes[0].darkWallpaper, "/one/dark.jpg")
        XCTAssertNil(normalized.activeThemeID)
        XCTAssertEqual(normalized.shortcuts.showMain, "cmd+1")
        XCTAssertNil(normalized.shortcuts.showPreview)
        XCTAssertEqual(normalized.shortcuts.showMenu, "cmd+2")
        XCTAssertEqual(normalized.appearanceLightThemeID, "kept")
        XCTAssertNil(normalized.appearanceDarkThemeID)
        XCTAssertNil(normalized.allFoldersLightWallpaper)
        XCTAssertEqual(normalized.allFoldersDarkWallpaper, "/two/dark.jpg")
        XCTAssertEqual(normalized.wallpaperHistory, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(try decodeSettings(at: manager.settingsURL), normalized)
    }

    func testWatcherReloadsExternalAtomicReplacement() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let external = WallpaperSettings(folderPaths: ["/external"], historyLimit: 20)
        let changed = expectation(description: "External settings were loaded")
        manager.onSettingsChanged = { [weak manager] in
            if manager?.settings == external {
                changed.fulfill()
            }
        }

        try encoded(external).write(to: manager.settingsURL, options: [.atomic])
        await fulfillment(of: [changed], timeout: 2)

        XCTAssertEqual(manager.settings, external)
        XCTAssertNil(manager.lastError)
    }

    func testWatcherRecreatesExternallyDeletedFileFromLastKnownGoodSettings() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let expected = WallpaperSettings(folderPaths: ["/preserved"])
        XCTAssertSuccess(manager.replace(expected))
        let changed = expectation(description: "Deleted settings were restored")
        manager.onSettingsChanged = { [weak manager] in
            guard let manager else { return }
            if FileManager.default.fileExists(atPath: manager.settingsURL.path) {
                changed.fulfill()
            }
        }

        try FileManager.default.removeItem(at: manager.settingsURL)
        await fulfillment(of: [changed], timeout: 2)

        XCTAssertEqual(try decodeSettings(at: manager.settingsURL), expected)
        XCTAssertEqual(manager.settings, expected)
    }

    func testWatcherReportsMalformedAtomicReplacementWithoutDestroyingLastKnownGoodState() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let expected = WallpaperSettings(folderPaths: ["/preserved"])
        XCTAssertSuccess(manager.replace(expected))
        let malformed = Data("{broken".utf8)
        let failed = expectation(description: "Malformed external settings were reported")
        manager.onError = { error in
            if case .decodeFailed = error {
                failed.fulfill()
            }
        }

        try malformed.write(to: manager.settingsURL, options: [.atomic])
        await fulfillment(of: [failed], timeout: 2)

        XCTAssertEqual(manager.settings, expected)
        XCTAssertEqual(try Data(contentsOf: manager.settingsURL), malformed)
    }

    private func encoded(_ settings: WallpaperSettings, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(settings)
    }

    private func decodeSettings(at url: URL) throws -> WallpaperSettings {
        try JSONDecoder().decode(WallpaperSettings.self, from: Data(contentsOf: url))
    }
}

private func XCTAssertSuccess(
    _ result: Result<Void, SettingsManagerError>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case let .failure(error) = result {
        XCTFail("Expected success, got \(error)", file: file, line: line)
    }
}
