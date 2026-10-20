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
        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/after"])))

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

        XCTAssertSuccess(manager.replace(manager.settings))

        let stored = try decodeSettings(at: settingsURL)
        XCTAssertEqual(stored.themes.first?.id, "theme-0")
        XCTAssertEqual(stored.activeThemeID, "theme-0")
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
            wallpaperHistory: ["/one/a", "/one/b", "/one/a", "/one/c", "/one/d", "/one/e", "/one/f"]
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

        XCTAssertSuccess(manager.replace(input))

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
        XCTAssertSuccess(manager.replace(expected))

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
        XCTAssertSuccess(manager.replace(expected))
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

        XCTAssertSuccess(manager.replace(updated))

        XCTAssertEqual(delivered, updated)
        XCTAssertEqual(readInsideSink, updated)
    }

    /// A failed write must not publish anything at all.
    func testFailedWriteDoesNotPublishTheNewValue() throws {
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

        let result = manager.update { $0.folderPaths = ["/must-not-publish"] }

        guard case .failure(.writeFailed) = result else {
            return XCTFail("Expected the failed write to be returned")
        }
        XCTAssertEqual(manager.settings, original)
        XCTAssertEqual(delivered, original)
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

        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/after-save"])))

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

        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/after-save"])))

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
            fileManager: CopyOnlyFileManager(),
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

    /// A failed write must stay visible when the watcher reads an unchanged
    /// file: the settings in memory were never written to disk.
    func testTheWriteFailureSurvivesAnUnchangedWatcherEvent() async throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/saved"])))
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

        let result = manager.update { $0.folderPaths = ["/never-written"] }
        guard case .failure(.writeFailed) = result else {
            return XCTFail("Expected the failed write to be returned")
        }
        guard case .writeFailed? = manager.lastError else {
            return XCTFail("Expected the failed write to be published")
        }

        let handled = await waitUntil { manager.externalChangeGeneration > generationBefore }
        XCTAssertTrue(handled, "The watcher should handle the pending change")
        // The watcher applies the outcome right after it read the file.
        let cleared = await waitUntil(timeout: 2) { manager.lastError == nil }
        XCTAssertFalse(cleared, "The write failure must stay visible")
        guard case .writeFailed? = manager.lastError else {
            return XCTFail("The write failure must stay visible after the unchanged read")
        }
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
        let fileManager = PausingFileManager()
        let manager = SettingsManager(
            settingsDirectory: context.settingsDirectory,
            userDefaults: context.userDefaults,
            defaultSettingsDirectory: context.defaultSettingsDirectory,
            fileManager: fileManager,
            migrateLegacySettings: false
        )
        XCTAssertSuccess(manager.replace(WallpaperSettings(folderPaths: ["/wallpapers"])))

        // The next check for the deleted file pauses the reload.
        fileManager.pauseOnMissingFile()
        try FileManager.default.removeItem(at: manager.settingsURL)

        await fileManager.waitUntilChecked()

        // The change of the rotation timer lands while the reload runs.
        XCTAssertSuccess(manager.update { $0.currentWallpaper = "/wallpapers/new.jpg" })
        fileManager.resumeTheReload()

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

/// A file manager that cannot move a file: the quarantine falls back to a
/// copy, so the unreadable file stays where it is.
private final class CopyOnlyFileManager: FileManager {
    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteFileExists)
    }
}

/// A file manager that pauses the check for a settings file that was deleted
/// externally, so a test can change the settings while the reload runs.
private final class PausingFileManager: FileManager {
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

    override func fileExists(atPath path: String) -> Bool {
        let exists = super.fileExists(atPath: path)
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
