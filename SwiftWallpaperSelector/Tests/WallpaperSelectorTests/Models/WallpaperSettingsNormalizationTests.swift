import XCTest
@testable import WallpaperSelector

final class WallpaperSettingsNormalizationTests: XCTestCase {

    /// A theme without folders uses the global folder list as its scope, so a
    /// pin inside a configured folder must survive the save and the load.
    @MainActor
    func testAThemeWithoutFoldersKeepsAPinInsideAConfiguredFolderAcrossSaveAndLoad() throws {
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

        manager.flushPendingWrites()
        let reloaded = context.makeSettingsManager().settings

        XCTAssertEqual(reloaded.themes[0].lightWallpaper, "/wallpapers/light.jpg")
        XCTAssertEqual(reloaded.themes[0].darkWallpaper, "/wallpapers/dark.jpg")
    }

    func testSpacePinsUseTheUppercaseIdentifierOfMacOS() {
        let normalized = WallpaperSettings(
            spacePins: [
                "aaaaaaaa-0000-0000-0000-000000000001": "/wallpapers/pin.jpg",
                "bbbbbbbb-0000-0000-0000-000000000002": "relative.jpg",
            ]
        ).normalized()

        XCTAssertEqual(normalized.spacePins, [
            "AAAAAAAA-0000-0000-0000-000000000001": "/wallpapers/pin.jpg",
        ])
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
    func testEveryThemeActionWithoutAThemeBecomesAShuffle() {
        for action in [RotationAction.themeNext, .themeShuffle, .themePrevious] {
            let normalized = WallpaperSettings(rotationAction: action).normalized()

            XCTAssertEqual(
                normalized.rotationAction,
                .shuffle,
                "\(action) cannot run without a theme"
            )
            // The rule must not fire twice: the action is a wallpaper action
            // after the first pass.
            XCTAssertEqual(normalized, normalized.normalized())
        }
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

    /// An empty folder is the working directory, so it is not a folder. The
    /// working directory and its parent (`.` and `..`) are not folders too.
    func testAnEmptyFolderIsDroppedFromTheFolderList() {
        let normalized = WallpaperSettings(
            folderPaths: ["", "/wallpapers", "   ", ".", ".."]
        ).normalized()

        XCTAssertEqual(normalized.folderPaths, ["/wallpapers"])
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

    /// The pins are compared with the standardized path of a folder, so an
    /// absolute folder has to be stored in the same form. A trailing slash
    /// or a `.`/`..` component must name the same folder.
    func testAnAbsoluteFolderIsStoredInItsStandardizedForm() {
        let plain = WallpaperSettings(folderPaths: ["/wp"]).normalized()
        let trailingSlash = WallpaperSettings(folderPaths: ["/wp/"]).normalized()
        let dotComponents = WallpaperSettings(folderPaths: ["/wp/./"]).normalized()
        let parentComponents = WallpaperSettings(folderPaths: ["/wp/../wp"]).normalized()

        XCTAssertEqual(plain.folderPaths, ["/wp"])
        XCTAssertEqual(trailingSlash, plain)
        XCTAssertEqual(dotComponents, plain)
        XCTAssertEqual(parentComponents, plain)
    }

    /// A theme scope that is written with a trailing slash has to match the
    /// configured folder even when the folder list uses the form without it.
    /// A dropped scope would widen the theme to every configured folder.
    func testAThemeScopeWithATrailingSlashIsNotWidened() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wp/", "/wp/./"],
            lightWallpaper: "/wp/light.jpg"
        )
        let normalized = WallpaperSettings(
            folderPaths: ["/wp", "/other"],
            themes: [theme],
            activeThemeID: "theme"
        ).normalized()

        XCTAssertEqual(normalized.themes[0].folderPaths, ["/wp"])
        XCTAssertFalse(
            normalized.themes[0].folderPaths.isEmpty,
            "A dropped scope would widen the theme to every configured folder"
        )
        XCTAssertEqual(normalized.themes[0].lightWallpaper, "/wp/light.jpg")
    }
}
