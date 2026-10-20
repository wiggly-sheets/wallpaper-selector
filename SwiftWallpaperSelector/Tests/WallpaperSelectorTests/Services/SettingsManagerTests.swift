import Combine
import XCTest
@testable import WallpaperSelector

@MainActor
final class SettingsManagerTests: XCTestCase {
    func testRelocationToEmptyDirectoryCopiesCurrentSettingsThenPersistsLocation() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let current = WallpaperSettings(folderPaths: ["/current"], currentWallpaper: "/current/a.jpg")
        manager.replace(current)
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
        manager.replace(WallpaperSettings(folderPaths: ["/current"]))
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
        manager.replace(current)
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

    /// The file in the old folder must not be left behind: it would be
    /// adopted silently when the old folder is chosen again.
    func testSwitchingAwayRenamesTheOldSettingsFile() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let current = WallpaperSettings(folderPaths: ["/current"])
        manager.replace(current)
        manager.flushPendingWrites()
        let oldURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let oldData = try Data(contentsOf: oldURL)
        let destination = context.directory(named: "Synchronized")

        try manager.relocateSettings(to: destination)

        let migratedURL = context.settingsDirectory.appendingPathComponent("settings.json.migrated")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: oldURL.path),
            "The old settings file must not be left behind"
        )
        XCTAssertEqual(
            try Data(contentsOf: migratedURL),
            oldData,
            "The bytes of the old settings file have to survive the rename"
        )
    }

    /// The renamed file must not be adopted when the old folder is chosen
    /// again: the settings made in between are the current ones.
    func testSwitchingBackDoesNotAdoptTheRenamedFile() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let destination = context.directory(named: "Synchronized")
        try manager.relocateSettings(to: destination)
        let changed = WallpaperSettings(folderPaths: ["/changed"])
        manager.replace(changed)

        try manager.relocateSettings(to: context.settingsDirectory)

        XCTAssertEqual(manager.settings, changed)
        XCTAssertEqual(
            try decodeSettings(at: context.settingsDirectory.appendingPathComponent("settings.json")),
            changed
        )
    }

    /// A file that cannot be renamed stays where it is, so the failure has to
    /// be reported: the old file would be adopted silently later.
    func testAFailedRenameIsReported() throws {
        let context = try TestSettingsContext()
        let manager = SettingsManager(
            settingsDirectory: context.settingsDirectory,
            userDefaults: context.userDefaults,
            defaultSettingsDirectory: context.defaultSettingsDirectory,
            fileManager: NoMoveFileManager(),
            migrateLegacySettings: false
        )
        let destination = context.directory(named: "Synchronized")

        try manager.relocateSettings(to: destination)

        guard case .renameFailed? = manager.lastError else {
            return XCTFail("Expected the failed rename to be reported")
        }
        XCTAssertEqual(manager.settingsDirectory, destination)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: context.settingsDirectory.appendingPathComponent("settings.json").path
            ),
            "The old file has to stay when it cannot be renamed"
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

    func testMalformedInitialFileIsReportedAndKeptAsCorruptCopy() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let corruptURL = context.settingsDirectory.appendingPathComponent("settings.json.corrupt")
        let malformed = Data("not-json".utf8)
        try malformed.write(to: settingsURL)

        let manager = context.makeSettingsManager()

        guard case .decodeFailed? = manager.lastError else {
            return XCTFail("Expected the malformed settings error to be surfaced")
        }
        XCTAssertEqual(manager.settings, WallpaperSettings())
        XCTAssertEqual(try Data(contentsOf: corruptURL), malformed)
    }

    /// The unreadable file is the only copy of the user's settings: it must
    /// survive the next save.
    func testTheCorruptCopyIsKeptWhenTheAppSavesAgain() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let corruptURL = context.settingsDirectory.appendingPathComponent("settings.json.corrupt")
        let malformed = Data("not-json".utf8)
        try malformed.write(to: settingsURL)

        let manager = context.makeSettingsManager()
        manager.replace(WallpaperSettings(folderPaths: ["/after"]))
        manager.flushPendingWrites()

        XCTAssertEqual(try Data(contentsOf: corruptURL), malformed)
        XCTAssertEqual(try decodeSettings(at: settingsURL).folderPaths, ["/after"])
    }

    func testAnOlderCorruptCopyIsOverwrittenAtStartup() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let corruptURL = context.settingsDirectory.appendingPathComponent("settings.json.corrupt")
        try Data("older".utf8).write(to: corruptURL)
        let malformed = Data("not-json".utf8)
        try malformed.write(to: settingsURL)

        _ = context.makeSettingsManager()

        XCTAssertEqual(try Data(contentsOf: corruptURL), malformed)
    }

    /// A theme without an id must keep its stable id when the file is saved.
    func testAThemeWithoutIdKeepsItsStableIdInTheSavedFile() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        try Data("""
        {"folderPaths":["/wallpapers"],"themes":[{"name":"Broken","folderPaths":["/wallpapers"]}],"activeThemeId":"theme-0"}
        """.utf8).write(to: settingsURL)

        let manager = context.makeSettingsManager()

        XCTAssertEqual(manager.settings.themes.first?.id, "theme-0")
        XCTAssertEqual(manager.settings.activeThemeID, "theme-0")

        manager.replace(manager.settings)
        manager.flushPendingWrites()

        let stored = try decodeSettings(at: settingsURL)
        XCTAssertEqual(stored.themes.first?.id, "theme-0")
        XCTAssertEqual(stored.activeThemeID, "theme-0")
    }

    /// A failed write is reported and the file keeps the content it had.
    ///
    /// The settings in memory are the new ones: the file catches up later.
    func testAFailedWriteIsReportedAndTheFileKeepsThePreviousContent() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        manager.replace(WallpaperSettings(folderPaths: ["/saved"]))
        await manager.waitForPendingWrites()

        // The settings folder cannot be written to, so the next save fails
        // while the file on disk keeps the saved settings.
        let directory = manager.settingsDirectory
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
        }

        manager.update { $0.folderPaths = ["/never-written"] }

        await manager.waitForPendingWrites()

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be published")
        }
        XCTAssertEqual(
            manager.settings.folderPaths,
            ["/never-written"],
            "The settings in memory are the new ones"
        )
        XCTAssertEqual(
            try decodeSettings(at: manager.settingsURL).folderPaths,
            ["/saved"],
            "The file has to keep the content it had"
        )
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
            wallpaperHistory: ["/one/a", "/one/b", "/one/a", "/one/c", "/one/d", "/one/e", "/one/f"]
        )

        manager.replace(input)
        manager.flushPendingWrites()

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
        XCTAssertEqual(normalized.wallpaperHistory, ["/one/a", "/one/b", "/one/c", "/one/d", "/one/e"])
        XCTAssertEqual(try decodeSettings(at: manager.settingsURL), normalized)
    }

    func testReplaceKeepsThemePinInsideASubfolderOfAConfiguredFolder() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let input = WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [
                Theme(
                    id: "theme",
                    name: "Theme",
                    folderPaths: ["/wallpapers"],
                    lightWallpaper: "/wallpapers/nested/light.jpg",
                    darkWallpaper: "/wallpapers/dark.jpg"
                )
            ]
        )

        manager.replace(input)

        let normalized = manager.settings
        XCTAssertEqual(normalized.themes[0].lightWallpaper, "/wallpapers/nested/light.jpg")
        XCTAssertEqual(normalized.themes[0].darkWallpaper, "/wallpapers/dark.jpg")
    }

    func testWatcherReloadsExternalAtomicReplacement() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let external = WallpaperSettings(folderPaths: ["/external"], historyLimit: 20)

        try encoded(external).write(to: manager.settingsURL, options: [.atomic])

        let reloaded = await waitUntil { manager.settings == external }
        XCTAssertTrue(reloaded, "The manager should pick up the externally written settings")
        XCTAssertEqual(manager.settings, external)
        XCTAssertNil(manager.lastError)
    }

    func testWatcherRecreatesExternallyDeletedFileFromLastKnownGoodSettings() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let expected = WallpaperSettings(folderPaths: ["/preserved"])
        manager.replace(expected)
        manager.flushPendingWrites()

        try FileManager.default.removeItem(at: manager.settingsURL)

        let recreated = await waitUntil {
            FileManager.default.fileExists(atPath: manager.settingsURL.path)
        }
        XCTAssertTrue(recreated, "The deleted settings file should be recreated")
        XCTAssertEqual(try decodeSettings(at: manager.settingsURL), expected)
        XCTAssertEqual(manager.settings, expected)
    }

    func testWatcherReportsMalformedAtomicReplacementWithoutDestroyingLastKnownGoodState() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let expected = WallpaperSettings(folderPaths: ["/preserved"])
        manager.replace(expected)
        manager.flushPendingWrites()
        let malformed = Data("{broken".utf8)

        try malformed.write(to: manager.settingsURL, options: [.atomic])

        let reported = await waitUntil { manager.lastError != nil }
        XCTAssertTrue(reported, "The malformed settings file should be reported")
        guard case .decodeFailed? = manager.lastError else {
            return XCTFail("Expected the malformed settings to be reported")
        }
        XCTAssertEqual(manager.settings, expected)
        XCTAssertEqual(try Data(contentsOf: manager.settingsURL), malformed)
    }

    func testWatcherKeepsTheNewestExternalWrite() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let first = WallpaperSettings(folderPaths: ["/first"])
        let second = WallpaperSettings(folderPaths: ["/second"])

        try encoded(first).write(to: manager.settingsURL, options: [.atomic])
        try encoded(second).write(to: manager.settingsURL, options: [.atomic])

        let updated = await waitUntil { manager.settings == second }
        XCTAssertTrue(updated, "The newest external settings should win")
        XCTAssertEqual(manager.settings, second)
    }

    /// Every external reload gets its own generation, so a reload that finishes
    /// after a newer one started cannot overwrite the newer settings.
    func testEveryExternalReloadCountsUpItsOwnGeneration() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let generationBefore = manager.externalChangeGeneration

        try encoded(WallpaperSettings(folderPaths: ["/external"]))
            .write(to: manager.settingsURL, options: [.atomic])

        let reloaded = await waitUntil { manager.settings.folderPaths == ["/external"] }
        XCTAssertTrue(reloaded, "The external settings should be reloaded")
        XCTAssertGreaterThan(manager.externalChangeGeneration, generationBefore)
    }

    /// The publisher must not deliver a value that the manager does not hold
    /// yet: every subscriber reads `settings` while it handles the change.
    func testPublisherDeliversTheNewValueAfterTheStoredValueWasUpdated() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let updated = WallpaperSettings(folderPaths: ["/new"], allSpaces: true)
        var delivered: WallpaperSettings?
        var readInsideSink: WallpaperSettings?

        let subscription = manager.settingsPublisher.sink { value in
            delivered = value
            readInsideSink = manager.settings
        }
        defer { subscription.cancel() }

        manager.replace(updated)

        XCTAssertEqual(delivered, updated)
        XCTAssertEqual(readInsideSink, updated)
    }

    /// A failed write does not stop the publish: the settings in memory are
    /// the new ones, and the failure is reported when the write runs.
    func testAFailedWriteStillPublishesTheNewValue() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let original = manager.settings
        var delivered: WallpaperSettings?
        let subscription = manager.settingsPublisher.sink { value in
            delivered = value
        }
        defer { subscription.cancel() }

        try FileManager.default.removeItem(at: manager.settingsDirectory)
        try Data("not-a-directory".utf8).write(to: manager.settingsDirectory)

        manager.update { $0.folderPaths = ["/must-be-published"] }

        XCTAssertEqual(manager.settings.folderPaths, ["/must-be-published"])
        XCTAssertEqual(delivered?.folderPaths, ["/must-be-published"])

        await manager.waitForPendingWrites()

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be published")
        }
        XCTAssertNotEqual(manager.settings, original)
    }

    /// A legacy file that cannot be read must not block the migration for
    /// ever: the location stays empty, so the next launch retries it.
    func testAnUnreadableLegacyFileKeepsTheMigrationPending() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: legacyURL)

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)

        guard case .decodeFailed? = manager.lastError else {
            return XCTFail("Expected the unreadable legacy file to be reported")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: manager.settingsURL.path),
            "A default file would skip the legacy migration for ever"
        )
    }

    /// A legacy file that does not exist changes nothing: the default
    /// settings file is written.
    func testAMissingLegacyFileWritesTheDefaultSettings() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)

        XCTAssertNil(manager.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.settingsURL.path))
    }

    /// The legacy file is the only copy of the settings: the reason for the
    /// default settings must stay visible after the first save.
    func testTheUnreadableLegacyFileKeepsItsErrorAfterTheFirstSave() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: legacyURL)

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)
        XCTAssertTrue(manager.isLegacyMigrationPending)

        manager.replace(WallpaperSettings(folderPaths: ["/after-save"]))
        manager.flushPendingWrites()

        XCTAssertNotNil(manager.lastError, "The reason for the default settings must stay visible")
        XCTAssertTrue(
            manager.lastError?.localizedDescription.contains("default settings") == true,
            "The message must say that the app uses the default settings"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: legacyURL.path),
            "The legacy file must stay on disk so the user can recover it by hand"
        )
    }

    /// A legacy file that could not be read is not renamed: the import is
    /// still pending, so the next launch can retry it.
    func testAnUnreadableLegacyFileIsNotRenamed() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: legacyURL)

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: legacyURL.path),
            "The legacy file must stay, so the migration can be retried"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: migratedLegacyURL(for: legacyURL).path),
            "A file that was not imported must not be renamed"
        )
    }

    /// A successful import renames the legacy file: the import is done, and
    /// the bytes of the legacy file survive.
    func testASuccessfulImportRenamesTheLegacyFile() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyData = try encoded(WallpaperSettings(folderPaths: ["/legacy"]))
        try legacyData.write(to: legacyURL)

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)

        XCTAssertEqual(manager.settings.folderPaths, ["/legacy"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyURL.path),
            "The imported legacy file must be renamed"
        )
        XCTAssertEqual(
            try Data(contentsOf: migratedLegacyURL(for: legacyURL)),
            legacyData,
            "The bytes of the legacy file have to survive the rename"
        )
    }

    /// A legacy file that survives a user save is reported on the next
    /// launch: it was never imported, because a newer settings file exists.
    func testALegacyFileThatSurvivesASaveIsReportedOnTheNextLaunch() throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyData = Data("not-json".utf8)
        try legacyData.write(to: legacyURL)

        // The first launch cannot read the legacy file, so the location stays
        // empty and the migration stays pending.
        let firstLaunch = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)
        guard case .decodeFailed? = firstLaunch.lastError else {
            return XCTFail("Expected the unreadable legacy file to be reported")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstLaunch.settingsURL.path))

        // The first user change writes the settings file.
        firstLaunch.replace(WallpaperSettings(folderPaths: ["/after-save"]))
        firstLaunch.flushPendingWrites()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstLaunch.settingsURL.path))

        // The next launch finds the legacy file next to a newer settings file.
        let secondLaunch = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)
        guard case .legacySettingsNotImported? = secondLaunch.lastError else {
            return XCTFail("Expected the legacy file to be reported")
        }
        XCTAssertEqual(
            secondLaunch.settings.folderPaths,
            ["/after-save"],
            "The legacy file must not be imported over the newer settings"
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyURL),
            legacyData,
            "The legacy file must not be touched"
        )
    }

    /// The path the imported legacy file is renamed to.
    private func migratedLegacyURL(for legacyURL: URL) -> URL {
        legacyURL
            .deletingLastPathComponent()
            .appendingPathComponent(legacyURL.lastPathComponent + ".migrated")
    }

    /// The watcher cannot watch a file that does not exist: the first save
    /// has to start it, or every later external change is ignored.
    func testTheWatcherStartsAfterTheFirstSave() async throws {
        let context = try TestSettingsContext()
        let legacyURL = context.directory(named: "legacy").appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: legacyURL)

        let manager = context.makeSettingsManagerMigratingLegacySettings(from: legacyURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.settingsURL.path))

        manager.replace(WallpaperSettings(folderPaths: ["/after-save"]))
        await manager.waitForPendingWrites()

        try encoded(WallpaperSettings(folderPaths: ["/external"]))
            .write(to: manager.settingsURL, options: [.atomic])

        let reloaded = await waitUntil { manager.settings.folderPaths == ["/external"] }
        XCTAssertTrue(reloaded, "The watcher must pick up the external change after the first save")
    }

    /// A write that fails after the quarantine must be reported: the app
    /// would run without any settings file at all.
    func testAFailedWriteAfterTheQuarantineIsReported() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        // A directory cannot be read as a settings file and cannot be written
        // to, so the fresh default file fails.
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: true)

        let manager = SettingsManager(
            settingsDirectory: context.settingsDirectory,
            userDefaults: context.userDefaults,
            defaultSettingsDirectory: context.defaultSettingsDirectory,
            fileManager: NoMoveFileManager(),
            migrateLegacySettings: false
        )

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be reported")
        }
    }

    /// The unreadable file is the only copy of the settings: it must not be
    /// overwritten when it cannot be stored at the `.corrupt` path.
    func testTheUnreadableFileSurvivesWhenTheQuarantineFails() throws {
        let context = try TestSettingsContext()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let corruptURL = context.settingsDirectory.appendingPathComponent("settings.json.corrupt")
        let malformed = Data("not-json".utf8)
        try malformed.write(to: settingsURL)
        // An old corrupt copy that cannot be removed keeps the quarantine from
        // storing the unreadable file.
        try Data("older".utf8).write(to: corruptURL)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: corruptURL.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: corruptURL.path)
        }

        let manager = context.makeSettingsManager()

        guard case .decodeFailed? = manager.lastError else {
            return XCTFail("Expected the malformed settings error to be surfaced")
        }
        XCTAssertEqual(
            try Data(contentsOf: settingsURL),
            malformed,
            "The only copy of the settings must not be overwritten"
        )
    }

    /// A failed write must stay visible when the watcher reads the file: the
    /// settings in memory were never written to disk.
    func testTheWriteFailureSurvivesAnUnchangedWatcherEvent() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let generationBefore = manager.externalChangeGeneration

        // The settings folder cannot be written to, so the next save fails
        // while the file on disk keeps the saved settings.
        let directory = manager.settingsDirectory
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
        }

        manager.update { $0.folderPaths = ["/never-written"] }

        await manager.waitForPendingWrites()

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be published")
        }

        // The watcher reads the file, which still holds the old settings.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: manager.settingsURL.path
        )

        let handled = await waitUntil { manager.externalChangeGeneration > generationBefore }
        XCTAssertTrue(handled, "The watcher should handle the pending change")
        // The watcher applies the outcome right after it read the file.
        let cleared = await waitUntil(timeout: 2) { manager.lastError == nil }
        XCTAssertFalse(cleared, "The write failure must stay visible")
        guard case .writeFailed? = manager.lastError else {
            return XCTFail("The write failure must stay visible after the unchanged read")
        }
        XCTAssertEqual(
            manager.settings.folderPaths,
            ["/never-written"],
            "The settings in memory are the new ones"
        )
    }

    /// Waits for the file watcher instead of relying on a tight timeout.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// The settings file is deleted externally and the app writes the
    /// settings while the reload is running. The newer value must survive:
    /// the file must not be overwritten with the snapshot from before the
    /// reload started.
    func testTheRecreatedFileKeepsTheChangeThatLandedDuringTheReload() async throws {
        let context = try TestSettingsContext()
        let fileCheck = MissingFileCheck()
        let manager = SettingsManager(
            settingsDirectory: context.settingsDirectory,
            userDefaults: context.userDefaults,
            defaultSettingsDirectory: context.defaultSettingsDirectory,
            fileExists: { url in fileCheck.fileExists(url) },
            migrateLegacySettings: false
        )
        manager.replace(WallpaperSettings(folderPaths: ["/wallpapers"]))
        manager.flushPendingWrites()

        // The next check for the deleted file pauses the reload.
        fileCheck.pauseOnMissingFile()
        try FileManager.default.removeItem(at: manager.settingsURL)

        await fileCheck.waitUntilChecked()

        // The change of the rotation timer lands while the reload runs.
        manager.update { $0.currentWallpaper = "/wallpapers/new.jpg" }
        fileCheck.resumeTheReload()

        let settled = await waitUntilTheFileStopsChanging(at: manager.settingsURL)
        XCTAssertTrue(settled, "The reload should finish")
        XCTAssertEqual(
            manager.settings.currentWallpaper,
            "/wallpapers/new.jpg",
            "The change must stay in memory"
        )
        XCTAssertEqual(
            try decodeSettings(at: manager.settingsURL).currentWallpaper,
            "/wallpapers/new.jpg",
            "The change must stay on disk"
        )
    }

    /// Waits until the settings file is not written again: the reload is
    /// done then.
    private func waitUntilTheFileStopsChanging(
        at url: URL,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastDate: Date?
        var stableChecks = 0
        while Date() < deadline {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = attributes?[.modificationDate] as? Date
            if date != nil, date == lastDate {
                stableChecks += 1
                if stableChecks >= 4 { return true }
            } else {
                stableChecks = 0
            }
            lastDate = date
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// The reload must not revert a change that lands while the file is read.
    ///
    /// The settings in memory are the truth and the file follows: the change
    /// that lands during the read is newer than the snapshot of the file, so
    /// the snapshot must not overwrite it, and the queued write must persist
    /// the change instead of the reverted one.
    func testTheReloadKeepsTheChangeThatLandsWhileTheFileIsRead() async throws {
        let context = try TestSettingsContext()
        let readGate = ReadGate()
        let writeGate = WriteGate()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let original = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/x.jpg")
        // The file holds the same settings as the memory, so the reload has
        // no external change to pick up.
        try encoded(original).write(to: settingsURL)
        let manager = context.makeSettingsManager(
            beforeWrite: { writeGate.beforeWrite() },
            beforeRead: { readGate.beforeRead() }
        )
        XCTAssertEqual(manager.settings, original)

        // The next write waits, so the file keeps the old settings while the
        // reload reads it.
        writeGate.pauseTheNextWrite()
        readGate.pauseTheNextRead()
        // The watcher reads the file, so the reload runs.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: settingsURL.path)
        let reading = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(reading, "The reload should read the settings file")
        guard reading else {
            // The write would wait for ever otherwise.
            writeGate.resumeTheWrite()
            return
        }

        // The change of the rotation lands while the file is read.
        let newer = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/y.jpg")
        manager.replace(newer)

        // The write waits for the reload: a reload that publishes the value
        // it read would make the write persist that one.
        var published = false
        let subscription = manager.settingsPublisher.dropFirst().sink { _ in
            published = true
            writeGate.resumeTheWrite()
        }
        defer { subscription.cancel() }
        readGate.resumeTheRead()

        // Nothing is published when the change is kept, so the write is
        // released after a moment.
        _ = await waitUntil({ published }, timeout: 0.5)
        writeGate.resumeTheWrite()
        await manager.waitForPendingWrites()

        XCTAssertEqual(
            manager.settings.currentWallpaper,
            "/wallpapers/y.jpg",
            "The change must stay in memory"
        )
        XCTAssertEqual(
            try decodeSettings(at: settingsURL).currentWallpaper,
            "/wallpapers/y.jpg",
            "The change must stay on disk"
        )
    }

    /// The reload must not revert a change whose write is still queued.
    ///
    /// The file holds the old settings while the write waits, so the file is
    /// older than the settings in memory. The reload must not adopt it: the
    /// queued write puts the change on the disk.
    func testTheReloadKeepsTheChangeWhoseWriteIsStillQueued() async throws {
        let context = try TestSettingsContext()
        let writeGate = WriteGate()
        let readGate = ReadGate()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let original = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/x.jpg")
        try encoded(original).write(to: settingsURL)
        let manager = context.makeSettingsManager(
            beforeWrite: { writeGate.beforeWrite() },
            beforeRead: { readGate.beforeRead() }
        )
        XCTAssertEqual(manager.settings, original)

        // The write waits, so the file keeps the old settings while the
        // change is in memory and its write is queued.
        writeGate.pauseTheNextWrite()
        let newer = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/y.jpg")
        manager.replace(newer)
        await writeGate.waitUntilTheWriteWaits()

        // The watcher reads the file, so the reload runs.
        readGate.pauseTheNextRead()
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: settingsURL.path)
        let reading = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(reading, "The reload should read the settings file")
        guard reading else {
            // The write would wait for ever otherwise.
            writeGate.resumeTheWrite()
            return
        }

        // The reload publishes the file when it adopts it, so the write is
        // released with the publish.
        var published = false
        let subscription = manager.settingsPublisher.dropFirst().sink { _ in
            published = true
            writeGate.resumeTheWrite()
        }
        defer { subscription.cancel() }
        readGate.resumeTheRead()

        // Nothing is published when the change is kept, so the write is
        // released after a moment.
        _ = await waitUntil({ published }, timeout: 0.5)
        writeGate.resumeTheWrite()
        await manager.waitForPendingWrites()

        XCTAssertEqual(
            manager.settings.currentWallpaper,
            "/wallpapers/y.jpg",
            "The change must stay in memory"
        )
        XCTAssertEqual(
            try decodeSettings(at: settingsURL).currentWallpaper,
            "/wallpapers/y.jpg",
            "The change must stay on disk"
        )
    }

    /// A file that was changed outside the app is reloaded: the change is
    /// newer than the settings in memory, and no change landed during the
    /// read of the file.
    func testAnExternalEditIsReloadedWhenNoChangeLandsDuringTheRead() async throws {
        let context = try TestSettingsContext()
        let readGate = ReadGate()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let original = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/x.jpg")
        try encoded(original).write(to: settingsURL)
        let manager = context.makeSettingsManager(beforeRead: { readGate.beforeRead() })
        XCTAssertEqual(manager.settings, original)

        // The change lands on the file, outside the app.
        let external = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/z.jpg")
        try encoded(external).write(to: settingsURL, options: [.atomic])

        // The reload reads the file, so the change is picked up.
        readGate.pauseTheNextRead()
        let reading = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(reading, "The reload should read the settings file")
        readGate.resumeTheRead()

        let reloaded = await waitUntil { manager.settings == external }
        XCTAssertTrue(reloaded, "The external change should be reloaded")
        XCTAssertEqual(manager.settings, external)
    }

    /// An external edit that lands after a failed write has to be adopted.
    ///
    /// The file on the disk is older than the settings in memory, so the
    /// file must not overwrite them. The external edit is newer than the
    /// settings in memory, so it has to be adopted: the file and the
    /// settings have to agree afterwards.
    func testAnExternalEditAfterAFailedWriteIsAdopted() async throws {
        let context = try TestSettingsContext()
        let readGate = ReadGate()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let original = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/x.jpg")
        try encoded(original).write(to: settingsURL)
        let manager = context.makeSettingsManager(beforeRead: { readGate.beforeRead() })
        XCTAssertEqual(manager.settings, original)

        // The settings folder cannot be written to, so the next save fails
        // while the file on the disk keeps the saved settings.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: context.settingsDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: context.settingsDirectory.path
            )
        }

        manager.update { $0.currentWallpaper = "/wallpapers/new.jpg" }
        await manager.waitForPendingWrites()

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be reported")
        }
        XCTAssertEqual(
            try decodeSettings(at: settingsURL).currentWallpaper,
            "/wallpapers/x.jpg",
            "The file has to keep the content it had"
        )

        // The folder is writable again, so the external edit can land.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: context.settingsDirectory.path
        )

        // The change lands on the file, outside the app.
        let external = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/external.jpg")
        readGate.pauseTheNextRead()
        try encoded(external).write(to: settingsURL, options: [.atomic])

        // The reload reads the file, so the change is picked up.
        let reading = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(reading, "The reload should read the settings file")
        readGate.resumeTheRead()

        let reloaded = await waitUntil { manager.settings == external }
        XCTAssertTrue(reloaded, "The external change has to be adopted")
        XCTAssertEqual(manager.settings, external)
        XCTAssertEqual(
            try decodeSettings(at: settingsURL),
            external,
            "The file and the settings in memory have to agree"
        )
    }

    /// A reload that reads an unchanged file must not undo a failed write.
    ///
    /// The file on the disk is older than the settings in memory, so the
    /// newer settings have to survive the reload and the message of the
    /// failed write has to stay visible. The next external edit is newer
    /// than the settings in memory, so it has to be adopted: the failed
    /// write must not keep every later external edit out.
    func testTheNewerValueSurvivesAnUnchangedReloadAfterAFailedWrite() async throws {
        let context = try TestSettingsContext()
        let readGate = ReadGate()
        let settingsURL = context.settingsDirectory.appendingPathComponent("settings.json")
        let original = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/x.jpg")
        try encoded(original).write(to: settingsURL)
        let manager = context.makeSettingsManager(beforeRead: { readGate.beforeRead() })
        XCTAssertEqual(manager.settings, original)
        let generationBefore = manager.externalChangeGeneration

        // The settings folder cannot be written to, so the next save fails
        // while the file on the disk keeps the saved settings.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: context.settingsDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: context.settingsDirectory.path
            )
        }

        manager.update { $0.currentWallpaper = "/wallpapers/new.jpg" }
        await manager.waitForPendingWrites()

        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be reported")
        }

        // The watcher reads the file, which still holds the old settings.
        readGate.pauseTheNextRead()
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: settingsURL.path
        )
        let reading = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(reading, "The reload should read the settings file")
        readGate.resumeTheRead()

        let handled = await waitUntil { manager.externalChangeGeneration > generationBefore }
        XCTAssertTrue(handled, "The watcher should handle the pending change")
        // The watcher applies the outcome right after it read the file.
        let cleared = await waitUntil({ manager.lastError == nil }, timeout: 2)
        XCTAssertFalse(cleared, "The write failure must stay visible")
        guard case .writeFailed? = manager.lastError else {
            return XCTFail("The write failure must stay visible after the unchanged read")
        }
        XCTAssertEqual(
            manager.settings.currentWallpaper,
            "/wallpapers/new.jpg",
            "The newer settings in memory have to survive the reload"
        )

        // The folder is writable again, so the external edit can land.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: context.settingsDirectory.path
        )

        // The change lands on the file, outside the app.
        let external = WallpaperSettings(folderPaths: ["/wallpapers"], currentWallpaper: "/wallpapers/external.jpg")
        readGate.pauseTheNextRead()
        try encoded(external).write(to: settingsURL, options: [.atomic])

        // The reload reads the file, so the change is picked up.
        let readingTheEdit = await readGate.waitUntilTheReadWaits()
        XCTAssertTrue(readingTheEdit, "The reload should read the settings file")
        readGate.resumeTheRead()

        let reloaded = await waitUntil { manager.settings == external }
        XCTAssertTrue(reloaded, "The external change has to be adopted after the failed write")
        XCTAssertEqual(manager.settings, external)
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

/// A file manager that cannot move a file: the quarantine falls back to a
/// copy, so the unreadable file stays where it is, and the settings file
/// cannot be renamed.
private final class NoMoveFileManager: FileManager {
    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteFileExists)
    }
}

/// Pauses the check for a settings file that was deleted externally, so a
/// test can change the settings while the reload runs.
private final class MissingFileCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var pausesOnMissingFile = false
    private var isChecked = false
    private var checkedContinuation: CheckedContinuation<Void, Never>?
    private let resume = DispatchSemaphore(value: 0)

    /// Pauses the next check for a missing file.
    func pauseOnMissingFile() {
        lock.lock()
        pausesOnMissingFile = true
        lock.unlock()
    }

    /// The check that the manager uses for the settings file.
    func fileExists(_ url: URL) -> Bool {
        let exists = FileManager.default.fileExists(atPath: url.path)
        lock.lock()
        let shouldPause = pausesOnMissingFile && !exists
        pausesOnMissingFile = false
        isChecked = shouldPause || isChecked
        let continuation = checkedContinuation
        checkedContinuation = nil
        lock.unlock()
        guard shouldPause else { return exists }
        // The test changes the settings and then lets the reload continue.
        continuation?.resume()
        resume.wait()
        return exists
    }

    /// Waits until the reload checks for the deleted file. The caller must
    /// not block the main actor: the reload runs there.
    func waitUntilChecked() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isChecked {
                lock.unlock()
                continuation.resume()
                return
            }
            checkedContinuation = continuation
            lock.unlock()
        }
    }

    /// Lets the reload continue.
    func resumeTheReload() {
        resume.signal()
    }
}

/// Pauses the read of the settings file, so a test can change the settings
/// while the file is read.
///
/// The gate runs off the main actor, so the test can change the settings
/// while the read waits.
private final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pausesTheNextRead = false
    private var isWaiting = false
    private let resume = DispatchSemaphore(value: 0)

    /// Pauses the next read.
    func pauseTheNextRead() {
        lock.lock()
        pausesTheNextRead = true
        lock.unlock()
    }

    /// The seam the settings manager calls before it reads the file.
    func beforeRead() {
        lock.lock()
        let shouldPause = pausesTheNextRead
        pausesTheNextRead = false
        isWaiting = shouldPause
        lock.unlock()

        guard shouldPause else { return }
        // The test changes the settings and then lets the read continue.
        resume.wait()
        lock.lock()
        isWaiting = false
        lock.unlock()
    }

    /// Waits until the read waits at the gate.
    func waitUntilTheReadWaits(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if waitsForTheRead { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    /// Tells whether the read waits at the gate.
    private var waitsForTheRead: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isWaiting
    }

    /// Lets the waiting read continue.
    func resumeTheRead() {
        resume.signal()
    }
}
