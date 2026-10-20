import XCTest
@testable import WallpaperSelector

final class WallpaperSettingsNormalizationTests: XCTestCase {

    /// A theme without folders uses the global folder list as its scope, so a
    /// pin inside a configured folder must survive the save.
    @MainActor
    func testAThemeWithoutFoldersKeepsAPinInsideAConfiguredFolder() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: [],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        manager.replace(WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [theme],
            activeThemeID: theme.id
        ))

        XCTAssertEqual(manager.settings.themes[0].lightWallpaper, "/wallpapers/light.jpg")
        XCTAssertEqual(manager.settings.themes[0].darkWallpaper, "/wallpapers/dark.jpg")
    }

    /// The pin of a theme without folders has to survive the load of the
    /// settings file too, so the user does not lose it on the next start.
    @MainActor
    func testAThemeWithoutFoldersKeepsItsPinOnEveryLoad() throws {
        let context = try TestSettingsContext()
        let manager = context.makeSettingsManager()
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: [],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        manager.replace(WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [theme],
            activeThemeID: theme.id
        ))

        let reloaded = context.makeSettingsManager().settings

        XCTAssertEqual(reloaded.themes[0].lightWallpaper, "/wallpapers/light.jpg")
        XCTAssertEqual(reloaded.themes[0].darkWallpaper, "/wallpapers/dark.jpg")
    }

    /// A theme with its own folders keeps its scope: a pin outside those
    /// folders is dropped.
    func testAThemeWithItsOwnFoldersDropsAPinOutsideThoseFolders() {
        let theme = Theme(
            id: "scoped",
            name: "Scoped",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/other/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )

        let normalized = WallpaperSettings(
            folderPaths: ["/wallpapers", "/other"],
            themes: [theme]
        ).normalized()

        XCTAssertNil(normalized.themes[0].lightWallpaper)
        XCTAssertEqual(normalized.themes[0].darkWallpaper, "/wallpapers/dark.jpg")
    }

    /// A pin outside every configured folder is dropped.
    func testAPinOutsideEveryConfiguredFolderIsDropped() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: [],
            lightWallpaper: "/elsewhere/light.jpg"
        )

        let normalized = WallpaperSettings(
            folderPaths: ["/wallpapers"],
            themes: [theme]
        ).normalized()

        XCTAssertNil(normalized.themes[0].lightWallpaper)
    }

    /// Normalizing an already normalized value must not change it.
    func testNormalizingAnAlreadyNormalizedValueChangesNothing() {
        let settings = WallpaperSettings(
            folderPaths: ["/wallpapers", "/other"],
            themes: [
                Theme(
                    id: "empty",
                    name: "Empty",
                    folderPaths: [],
                    lightWallpaper: "/wallpapers/light.jpg"
                ),
                Theme(
                    id: "scoped",
                    name: "Scoped",
                    folderPaths: ["/wallpapers"],
                    darkWallpaper: "/wallpapers/dark.jpg"
                )
            ],
            activeThemeID: "empty"
        )

        let normalized = settings.normalized()

        XCTAssertEqual(normalized, normalized.normalized())
    }

    /// A theme action without a theme cannot run, so the stored action has to
    /// become a wallpaper action: the rotation picker has to show a
    /// selection, otherwise the stored action stays invisible.
    func testAThemeNextActionWithoutAThemeBecomesAShuffle() {
        let normalized = WallpaperSettings(rotationAction: .themeNext).normalized()

        XCTAssertEqual(normalized.rotationAction, .shuffle)
    }

    /// The same rule for the other theme actions.
    func testAThemeShuffleActionWithoutAThemeBecomesAShuffle() {
        let normalized = WallpaperSettings(rotationAction: .themeShuffle).normalized()

        XCTAssertEqual(normalized.rotationAction, .shuffle)
    }

    /// The same rule for the other theme actions.
    func testAThemePreviousActionWithoutAThemeBecomesAShuffle() {
        let normalized = WallpaperSettings(rotationAction: .themePrevious).normalized()

        XCTAssertEqual(normalized.rotationAction, .shuffle)
    }

    /// A theme action that has a theme to work with stays untouched.
    func testAThemeActionWithAThemeKeepsTheAction() {
        let theme = Theme(id: "theme", name: "Theme", folderPaths: [])

        let normalized = WallpaperSettings(
            folderPaths: ["/wallpapers"],
            rotationAction: .themeNext,
            themes: [theme]
        ).normalized()

        XCTAssertEqual(normalized.rotationAction, .themeNext)
    }

    /// Normalizing the value a second time must not change it again: the
    /// action is a wallpaper action now, so the rule does not fire twice.
    func testNormalizingAThemeActionWithoutAThemeTwiceChangesNothing() {
        let normalized = WallpaperSettings(rotationAction: .themeNext).normalized()

        XCTAssertEqual(normalized, normalized.normalized())
    }

    /// The images of the scope are the ones a pin can be stored in: the
    /// images of the folder and of its subfolders.
    func testTheScopeKeepsTheImagesInsideItAndDropsTheOtherOnes() {
        let images = [
            URL(fileURLWithPath: "/wallpapers/in-scope.jpg"),
            URL(fileURLWithPath: "/wallpapers/nested/in-scope.jpg"),
            URL(fileURLWithPath: "/other/outside.jpg")
        ]

        let scoped = WallpaperSettings.images(inScope: ["/wallpapers"], from: images)

        XCTAssertEqual(
            scoped,
            [
                URL(fileURLWithPath: "/wallpapers/in-scope.jpg"),
                URL(fileURLWithPath: "/wallpapers/nested/in-scope.jpg")
            ]
        )
    }

    /// An empty folder is the working directory, so it is not a folder.
    func testAnEmptyFolderIsDroppedFromTheFolderList() {
        let normalized = WallpaperSettings(
            folderPaths: ["", "/wallpapers", "   "]
        ).normalized()

        XCTAssertEqual(normalized.folderPaths, ["/wallpapers"])
    }

    /// A real folder survives the normalization.
    func testARealFolderSurvivesTheNormalization() {
        let normalized = WallpaperSettings(
            folderPaths: ["/wallpapers"]
        ).normalized()

        XCTAssertEqual(normalized.folderPaths, ["/wallpapers"])
    }

    /// The working directory is never a folder of the user: an empty path
    /// points at it.
    func testTheWorkingDirectoryIsNeverAFolder() {
        let normalized = WallpaperSettings(
            folderPaths: ["", "/wallpapers"]
        ).normalized()

        let workingDirectory = URL(fileURLWithPath: "").standardizedFileURL.path
        XCTAssertFalse(
            normalized.folderPaths.contains {
                URL(fileURLWithPath: $0).standardizedFileURL.path == workingDirectory
            }
        )
    }

    /// A relative folder would be resolved against the working directory of
    /// the process, so the normalization makes it absolute.
    func testARelativeFolderIsMadeAbsoluteByTheNormalization() {
        let expected = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Pictures")
            .standardizedFileURL
            .path

        let normalized = WallpaperSettings(folderPaths: ["Pictures"]).normalized()

        XCTAssertEqual(normalized.folderPaths, [expected])
    }

    /// The working directory and its parent are not folders of the user, so
    /// they are dropped.
    func testTheWorkingDirectoryIsDroppedFromTheFolderList() {
        let normalized = WallpaperSettings(
            folderPaths: [".", "..", "/wallpapers"]
        ).normalized()

        XCTAssertEqual(normalized.folderPaths, ["/wallpapers"])
    }
}
