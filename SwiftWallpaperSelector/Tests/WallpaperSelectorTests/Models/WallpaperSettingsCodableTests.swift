import XCTest
@testable import WallpaperSelector

final class WallpaperSettingsCodableTests: XCTestCase {
    func testDecodesElectronCamelCaseSchema() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"currentWallpaper":"/wallpapers/a.jpg","intervalMinutes":60,"rotationAction":"next","allSpaces":true,"shortcuts":{"showMain":"⌘⇧W","showPreview":null,"showMenu":null},"themes":[],"activeThemeId":"theme-1","matchSystemAppearance":true,"allFoldersLightWallpaper":"/wallpapers/light.jpg","allFoldersDarkWallpaper":null,"appearanceLightThemeId":"theme-1","appearanceDarkThemeId":null,"historyLimit":20,"wallpaperHistory":["/wallpapers/a.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.activeThemeID, "theme-1")
        XCTAssertEqual(settings.appearanceLightThemeID, "theme-1")
        XCTAssertEqual(settings.intervalMinutes, .hour1)
        XCTAssertEqual(settings.historyLimit, 20)
    }

    func testMigratesLegacySingleFolderAndRelativeWallpaper() throws {
        let data = Data("{\"folderPath\":\"/wallpapers\",\"currentWallpaper\":\"sunset.jpg\"}".utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.currentWallpaper, "/wallpapers/sunset.jpg")
        XCTAssertEqual(settings.rotationAction, .shuffle)
    }

    func testEncodesElectronCamelCaseKeys() throws {
        let data = try JSONEncoder().encode(WallpaperSettings(activeThemeID: "theme-1", appearanceDarkThemeID: "theme-2"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["activeThemeId"] as? String, "theme-1")
        XCTAssertEqual(json?["appearanceDarkThemeId"] as? String, "theme-2")
        XCTAssertNil(json?["activeThemeID"])
    }

    func testUnknownIntervalValueFallsBackToOffAndKeepsEveryOtherField() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"currentWallpaper":"/wallpapers/a.jpg","intervalMinutes":15,"rotationAction":"next","allSpaces":true,"historyLimit":20,"wallpaperHistory":["/wallpapers/a.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.intervalMinutes, .off)
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.currentWallpaper, "/wallpapers/a.jpg")
        XCTAssertEqual(settings.rotationAction, .next)
        XCTAssertTrue(settings.allSpaces)
        XCTAssertEqual(settings.historyLimit, 20)
        XCTAssertEqual(settings.wallpaperHistory, ["/wallpapers/a.jpg"])
    }

    func testUnknownRotationActionFallsBackToShuffleAndKeepsEveryOtherField() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"currentWallpaper":"/wallpapers/a.jpg","intervalMinutes":60,"rotationAction":"teleport","allSpaces":true,"historyLimit":20}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.rotationAction, .shuffle)
        XCTAssertEqual(settings.intervalMinutes, .hour1)
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.currentWallpaper, "/wallpapers/a.jpg")
        XCTAssertTrue(settings.allSpaces)
        XCTAssertEqual(settings.historyLimit, 20)
    }

    func testThemeWithoutIdentifierDoesNotRejectTheFile() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"rotationAction":"next","themes":[{"name":"Broken"},{"id":"kept","name":"Kept","folderPaths":["/wallpapers"]}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes.count, 2)
        XCTAssertEqual(settings.themes[0].id, "theme-0")
        XCTAssertEqual(settings.themes[0].name, "Broken")
        XCTAssertEqual(settings.themes[0].folderPaths, [])
        XCTAssertEqual(settings.themes[1].id, "kept")
        XCTAssertEqual(settings.themes[1].folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.rotationAction, .next)
    }

    /// A theme without an id must get the same id on every load, so the theme
    /// references keep working.
    func testThemeWithoutIdentifierKeepsTheSameIdOnEveryLoad() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"themes":[{"name":"Broken","folderPaths":["/wallpapers"]}],"activeThemeId":"theme-0"}
        """.utf8)

        let first = try JSONDecoder().decode(WallpaperSettings.self, from: data)
        let second = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(first.themes[0].id, "theme-0")
        XCTAssertEqual(second.themes[0].id, "theme-0")
        XCTAssertEqual(first.activeThemeID, "theme-0")
    }

    func testAThemeWithAnEmptyIdentifierGetsAStableId() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"themes":[{"id":"","name":"Empty","folderPaths":["/wallpapers"]}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes[0].id, "theme-0")
    }

    func testThemeWithIllTypedFolderPathsDoesNotRejectTheFile() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"rotationAction":"next","themes":[{"id":"broken","name":"Broken","folderPaths":42}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes.count, 1)
        XCTAssertEqual(settings.themes[0].id, "broken")
        XCTAssertEqual(settings.themes[0].name, "Broken")
        XCTAssertEqual(settings.themes[0].folderPaths, [])
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
        XCTAssertEqual(settings.rotationAction, .next)
    }

    func testIllTypedTopLevelFieldDoesNotRejectTheFile() throws {
        let data = Data("""
        {"folderPaths":42,"currentWallpaper":"/wallpapers/a.jpg","rotationAction":"next","allSpaces":true}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertEqual(settings.currentWallpaper, "/wallpapers/a.jpg")
        XCTAssertEqual(settings.rotationAction, .next)
        XCTAssertTrue(settings.allSpaces)
    }

    /// The distance to the closest limit must not overflow: an extreme limit
    /// would trap while the file is decoded, and the app could not be opened
    /// to repair the file.
    func testAnExtremeHistoryLimitStillDecodes() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"historyLimit":9223372036854775807}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.historyLimit, 20)
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
    }

    /// The lowest possible limit overflows the distance to the closest
    /// limit, so the file must not be able to crash the app.
    func testANegativeHistoryLimitStillDecodes() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"historyLimit":-9223372036854775808}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.historyLimit, 5)
        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
    }

    /// One broken element must not take the whole list with it: the folders
    /// that are still there have to survive, because the next save writes the
    /// list into the file.
    func testABrokenFolderPathElementDoesNotRejectTheOtherFolders() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers",42,"/more-wallpapers"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/wallpapers", "/more-wallpapers"])
    }

    /// The same rule for the recent wallpapers.
    func testABrokenHistoryElementDoesNotRejectTheOtherWallpapers() throws {
        let data = Data("""
        {"wallpaperHistory":["/wallpapers/a.jpg",null,"/wallpapers/b.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.wallpaperHistory, ["/wallpapers/a.jpg", "/wallpapers/b.jpg"])
    }

    /// The same rule for the folders of a theme.
    func testABrokenFolderPathElementOfATThemeDoesNotRejectTheOtherFolders() throws {
        let data = Data("""
        {"themes":[{"id":"theme","name":"Theme","folderPaths":["/wallpapers",42]}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes[0].folderPaths, ["/wallpapers"])
    }

    /// A theme that is not an object is not a theme: it must not become a
    /// theme without a name that covers every configured folder.
    func testAThemeThatIsNotAnObjectIsSkipped() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"themes":[{"id":"kept","name":"Kept","folderPaths":["/wallpapers"]},42]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes.count, 1)
        XCTAssertEqual(settings.themes[0].id, "kept")
        XCTAssertFalse(settings.themes[0].name.isEmpty)
        XCTAssertFalse(settings.themes[0].folderPaths.isEmpty)
    }

    /// A file that holds a theme action but no theme must not keep the theme
    /// action: the rotation picker would show no selection at all. The file
    /// itself is still valid, so it decodes.
    func testAThemeActionWithoutAThemeDecodesAndNormalizesToShuffle() throws {
        let data = Data("""
        {"folderPaths":["/wallpapers"],"rotationAction":"themeNext","themes":[]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.rotationAction, .themeNext)
        XCTAssertTrue(settings.themes.isEmpty)
        XCTAssertEqual(settings.normalized().rotationAction, .shuffle)
    }

    /// The legacy folder is only used when the new key is missing: a file
    /// that has the key wins, even with an empty list. A relative wallpaper
    /// belongs to no configured folder then, so it stays unknown.
    func testTheLegacyFolderIsIgnoredWhenTheFolderPathsKeyIsThere() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":[],"currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertNil(settings.currentWallpaper)
        XCTAssertEqual(settings.wallpaperHistory, [])
    }

    /// The file does not say which of the configured folders the wallpaper
    /// belongs to, so a relative wallpaper must not be resolved against the
    /// legacy folder: the path would be outside the configured scope.
    func testARelativeWallpaperIsNotResolvedAgainstTheLegacyFolderWhenTheFolderPathsKeyIsThere() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":["/configured"],"currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/configured"])
        XCTAssertNil(settings.currentWallpaper)
    }

    /// A relative history entry that cannot be resolved never matches an
    /// absolute path, so it is dropped.
    func testARelativeHistoryEntryIsDroppedWhenTheFolderPathsKeyIsThere() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":["/configured"],"wallpaperHistory":["sunset.jpg","/configured/a.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.wallpaperHistory, ["/configured/a.jpg"])
    }

    /// The legacy folder is the scope when the file does not have the new
    /// key, so a relative wallpaper and a relative history entry are still
    /// resolved against it.
    func testARelativeWallpaperIsResolvedAgainstTheLegacyFolderWithoutTheFolderPathsKey() throws {
        let data = Data("""
        {"folderPath":"/legacy","currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.currentWallpaper, "/legacy/sunset.jpg")
        XCTAssertEqual(settings.wallpaperHistory, ["/legacy/sunset.jpg"])
    }

    /// A relative legacy folder has to become absolute: the migration writes
    /// the folder list into the file, so a relative folder would make the
    /// relative wallpaper unreadable on the next launch.
    func testARelativeLegacyFolderBecomesAbsolute() throws {
        let data = Data("""
        {"folderPath":"wallpapers","currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let folder = try XCTUnwrap(settings.folderPaths.first)
        XCTAssertEqual(settings.folderPaths.count, 1)
        XCTAssertTrue(folder.hasPrefix("/"), "The legacy folder has to be absolute: \(folder)")
        XCTAssertTrue(folder.hasSuffix("/wallpapers"), "The legacy folder has to be kept: \(folder)")
        XCTAssertEqual(settings.currentWallpaper, folder + "/sunset.jpg")
        XCTAssertEqual(settings.wallpaperHistory, [folder + "/sunset.jpg"])
        XCTAssertEqual(settings.currentWallpaper?.hasPrefix("/"), true)
        XCTAssertEqual(settings.wallpaperHistory.first?.hasPrefix("/"), true)
    }

    /// A legacy folder that starts with a tilde is expanded, so it is
    /// absolute too.
    func testALegacyFolderWithATildeIsExpanded() throws {
        let data = Data("""
        {"folderPath":"~/wallpapers","currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let folder = try XCTUnwrap(settings.folderPaths.first)
        XCTAssertTrue(folder.hasPrefix("/"), "The legacy folder has to be absolute: \(folder)")
        XCTAssertFalse(folder.contains("~"), "The tilde has to be expanded: \(folder)")
        XCTAssertEqual(settings.currentWallpaper, folder + "/sunset.jpg")
    }

    /// The legacy folder is the scope of the file, so every relative
    /// wallpaper it names belongs to that folder. A pin that is not resolved
    /// would be dropped by the next save.
    func testARelativePinIsResolvedAgainstTheLegacyFolder() throws {
        let data = Data("""
        {"folderPath":"/legacy","allFoldersLightWallpaper":"light.jpg","allFoldersDarkWallpaper":"dark.jpg","themes":[{"id":"theme","name":"Theme","folderPaths":[],"lightWallpaper":"theme-light.jpg","darkWallpaper":"theme-dark.jpg"}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.allFoldersLightWallpaper, "/legacy/light.jpg")
        XCTAssertEqual(settings.allFoldersDarkWallpaper, "/legacy/dark.jpg")
        XCTAssertEqual(settings.themes[0].lightWallpaper, "/legacy/theme-light.jpg")
        XCTAssertEqual(settings.themes[0].darkWallpaper, "/legacy/theme-dark.jpg")

        // The pins have to survive the next save.
        let normalized = settings.normalized()
        XCTAssertEqual(normalized.allFoldersLightWallpaper, "/legacy/light.jpg")
        XCTAssertEqual(normalized.allFoldersDarkWallpaper, "/legacy/dark.jpg")
        XCTAssertEqual(normalized.themes[0].lightWallpaper, "/legacy/theme-light.jpg")
        XCTAssertEqual(normalized.themes[0].darkWallpaper, "/legacy/theme-dark.jpg")
    }

    /// The folders of a theme are its scope, and a scope is a folder path
    /// like every other folder path in the file, so it is made absolute. A
    /// relative scope would be resolved against the working directory of the
    /// process.
    func testTheScopeFoldersOfAThemeAreResolved() throws {
        let data = Data("""
        {"folderPath":"/legacy","themes":[{"id":"theme","name":"Theme","folderPaths":["scope"]}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let expected = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("scope")
            .standardizedFileURL
            .path
        XCTAssertEqual(settings.themes[0].folderPaths, [expected])
    }

    /// A scope that names a configured folder has to survive the next save:
    /// a dropped scope would widen the theme to every configured folder.
    func testARelativeThemeScopeThatMatchesAConfiguredFolderSurvivesTheRoundTrip() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = URL(fileURLWithPath: home)
            .appendingPathComponent("Pictures")
            .standardizedFileURL
            .path
        let otherFolder = URL(fileURLWithPath: home)
            .appendingPathComponent("Movies")
            .standardizedFileURL
            .path
        let data = Data("""
        {"folderPaths":["\(folder)","\(otherFolder)"],"themes":[{"id":"theme","name":"Theme","folderPaths":["Pictures"]}]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.themes[0].folderPaths, [folder])

        let written = try JSONEncoder().encode(settings.normalized())
        let nextLaunch = try JSONDecoder().decode(WallpaperSettings.self, from: written)

        XCTAssertEqual(nextLaunch.themes[0].folderPaths, [folder])
        XCTAssertEqual(
            nextLaunch.themes[0].folderPaths.count,
            1,
            "The theme must not widen to every configured folder"
        )
    }

    /// A folder list that is not a list of strings cannot be used, so the
    /// legacy folder is the scope: the folder configuration must not be
    /// lost.
    func testTheLegacyFolderIsUsedWhenTheFolderPathsValueIsNotAList() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":42,"currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.currentWallpaper, "/legacy/sunset.jpg")
        XCTAssertEqual(settings.wallpaperHistory, ["/legacy/sunset.jpg"])
    }

    /// The same rule for a folder list that is null.
    func testTheLegacyFolderIsUsedWhenTheFolderPathsValueIsNull() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":null,"currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.currentWallpaper, "/legacy/sunset.jpg")
    }

    /// A folder list without a usable folder cannot be used, so the legacy
    /// folder is the scope: the folder configuration must not be lost on the
    /// next save.
    func testTheLegacyFolderIsUsedWhenTheFolderPathsListHasNoUsableFolder() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":[42],"currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.currentWallpaper, "/legacy/sunset.jpg")
        XCTAssertEqual(settings.wallpaperHistory, ["/legacy/sunset.jpg"])

        // The legacy folder has to survive the next save.
        let written = try JSONEncoder().encode(settings.normalized())
        let nextLaunch = try JSONDecoder().decode(WallpaperSettings.self, from: written)

        XCTAssertEqual(nextLaunch.folderPaths, ["/legacy"])
        XCTAssertEqual(nextLaunch.currentWallpaper, "/legacy/sunset.jpg")
        XCTAssertEqual(nextLaunch.wallpaperHistory, ["/legacy/sunset.jpg"])
    }

    /// An empty folder is not a usable folder, so the list is a value that
    /// cannot be used.
    func testTheLegacyFolderIsUsedWhenTheFolderPathsListHasOnlyEmptyAndBrokenFolders() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":["",42],"currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.currentWallpaper, "/legacy/sunset.jpg")
    }

    /// A list with a usable folder is used: the file says which folders it
    /// has, so the legacy folder is not the scope.
    func testAPartlyBrokenFolderPathsListKeepsTheUsableFolders() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":["/a",42],"currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/a"])
        XCTAssertNil(settings.currentWallpaper)
    }

    /// An empty list says that there is nothing in it: the legacy folder is
    /// not the scope then, and the next save must not bring it back.
    func testAnEmptyFolderPathsListKeepsTheLegacyFolderOut() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":[],"currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertNil(settings.currentWallpaper)

        let written = try JSONEncoder().encode(settings.normalized())
        let nextLaunch = try JSONDecoder().decode(WallpaperSettings.self, from: written)

        XCTAssertEqual(nextLaunch.folderPaths, [])
    }

    /// A list of recent wallpapers that is broken stays empty: it must not
    /// bring a legacy value back.
    func testABrokenRecentWallpaperListStaysEmpty() throws {
        let data = Data("""
        {"folderPath":"/legacy","folderPaths":[42],"wallpaperHistory":[42,null]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/legacy"])
        XCTAssertEqual(settings.wallpaperHistory, [])
    }

    /// An empty legacy folder is not a folder: it would be the home
    /// directory, and the rotation would pick wallpapers from there.
    func testALegacyFolderThatIsEmptyProducesNoFolder() throws {
        let data = Data("""
        {"folderPath":"","currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertNil(settings.currentWallpaper)
        XCTAssertFalse(settings.folderPaths.contains(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    /// A legacy folder that is only whitespace is not a folder either.
    func testALegacyFolderThatIsOnlyWhitespaceProducesNoFolder() throws {
        let data = Data("""
        {"folderPath":"   ","currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertNil(settings.currentWallpaper)
    }

    /// A tilde that cannot be expanded is not a folder: the user has no such
    /// home directory, so the path must not become a folder of the home
    /// directory.
    func testALegacyFolderWithAnUnexpandableTildeProducesNoFolder() throws {
        let data = Data("""
        {"folderPath":"~nosuchuser12345/Pictures","currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertNil(settings.currentWallpaper)
        XCTAssertEqual(settings.wallpaperHistory, [])
    }

    /// A relative legacy folder is resolved against the home directory: the
    /// legacy settings file lived there.
    func testARelativeLegacyFolderIsResolvedAgainstTheHomeDirectory() throws {
        let data = Data("""
        {"folderPath":"wallpapers","currentWallpaper":"sunset.jpg"}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = URL(fileURLWithPath: home)
            .appendingPathComponent("wallpapers")
            .standardizedFileURL
            .path
        XCTAssertEqual(settings.folderPaths, [expected])
        XCTAssertEqual(settings.currentWallpaper, expected + "/sunset.jpg")
    }

    /// A folder path that is empty is the working directory, so it is not a
    /// folder.
    func testAModernFileWithAnEmptyFolderPathHasNoFolder() throws {
        let data = Data("""
        {"folderPaths":[""]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, [])
        XCTAssertEqual(settings.normalized().folderPaths, [])
        XCTAssertFalse(settings.folderPaths.contains(FileManager.default.currentDirectoryPath))
    }

    /// A relative folder would be resolved against the working directory of
    /// the process, so it has to be stored absolute.
    func testARelativeFolderPathBecomesAbsolute() throws {
        let data = Data("""
        {"folderPaths":["Pictures"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let expected = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Pictures")
            .standardizedFileURL
            .path
        XCTAssertEqual(settings.folderPaths, [expected])
        XCTAssertEqual(settings.normalized().folderPaths, [expected])
    }

    /// The working directory is not a folder of the user, so it is dropped.
    func testAFolderPathThatIsTheWorkingDirectoryIsDropped() throws {
        let data = Data("""
        {"folderPaths":[".","/wallpapers"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        XCTAssertEqual(settings.folderPaths, ["/wallpapers"])
    }

    /// A folder path with a tilde is expanded, so it is absolute too.
    func testAFolderPathWithATildeIsExpanded() throws {
        let data = Data("""
        {"folderPaths":["~/Pictures"]}
        """.utf8)

        let settings = try JSONDecoder().decode(WallpaperSettings.self, from: data)

        let folder = try XCTUnwrap(settings.folderPaths.first)
        XCTAssertTrue(folder.hasPrefix("/"), "The folder has to be absolute: \(folder)")
        XCTAssertFalse(folder.contains("~"), "The tilde has to be expanded: \(folder)")
        XCTAssertTrue(folder.hasSuffix("/Pictures"), "The folder has to be kept: \(folder)")
    }

    /// The migrated file has the folder list, so the wallpaper has to survive
    /// the next launch.
    func testTheMigratedLegacyFolderSurvivesTheNextLaunch() throws {
        let data = Data("""
        {"folderPath":"wallpapers","currentWallpaper":"sunset.jpg","wallpaperHistory":["sunset.jpg"]}
        """.utf8)

        let migrated = try JSONDecoder().decode(WallpaperSettings.self, from: data)
        // The app writes the migrated settings back into the file.
        let written = try JSONEncoder().encode(migrated.normalized())
        let nextLaunch = try JSONDecoder().decode(WallpaperSettings.self, from: written)

        XCTAssertEqual(nextLaunch.folderPaths, migrated.folderPaths)
        XCTAssertEqual(nextLaunch.currentWallpaper, migrated.currentWallpaper)
        XCTAssertEqual(nextLaunch.wallpaperHistory, migrated.wallpaperHistory)
        XCTAssertEqual(nextLaunch.folderPaths.first?.hasPrefix("/"), true)
        XCTAssertEqual(nextLaunch.currentWallpaper?.hasPrefix("/"), true)
        XCTAssertEqual(nextLaunch.wallpaperHistory.first?.hasPrefix("/"), true)

        let roundTrip = try JSONDecoder().decode(
            WallpaperSettings.self,
            from: try JSONEncoder().encode(nextLaunch)
        )
        XCTAssertEqual(roundTrip.currentWallpaper, migrated.currentWallpaper)
        XCTAssertEqual(roundTrip.wallpaperHistory, migrated.wallpaperHistory)
    }
}
