import XCTest
@testable import WallpaperSelector

/// The enablement of the items of the menu bar menu.
///
/// The enablement of the items used to be read from the code only. The
/// menu is a value of its own now, so every item can be checked here.
@MainActor
final class MenuBarMenuEnablementTests: XCTestCase {

    /// The failures are shown, but they cannot be clicked.
    func testTheErrorItemsAreDisabled() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            errorMessages: ["The wallpaper could not be set."]
        ))

        XCTAssertEqual(menu.menu.item(titled: "The wallpaper could not be set.")?.isEnabled, false)
    }

    /// The preview needs at least one folder.
    func testThePreviewItemIsDisabledWithoutFolders() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(isPreviewEnabled: false))
        XCTAssertEqual(menu.menu.item(titled: "Preview Wallpapers")?.isEnabled, false)

        menu.update(with: MenuBarMenuState(isPreviewEnabled: true))
        XCTAssertEqual(menu.menu.item(titled: "Preview Wallpapers")?.isEnabled, true)
    }

    /// The rotation cannot run while the appearance is matched, so the
    /// item and the items of the Rotate submenu are disabled.
    func testTheRotationItemsAreDisabledWhileTheAppearanceIsMatched() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            isRotationControlDisabled: true,
            intervalMinutes: .hour1,
            rotationAction: .shuffle
        ))

        XCTAssertEqual(menu.menu.item(titled: "Start Rotation")?.isEnabled, false)
        let rotateSubmenu = menu.menu.item(titled: "Rotate")?.submenu
        XCTAssertEqual(rotateSubmenu?.item(titled: "Every Hour")?.isEnabled, false)
        XCTAssertEqual(rotateSubmenu?.item(titled: "Shuffle Wallpaper")?.isEnabled, false)
        XCTAssertEqual(rotateSubmenu?.item(titled: "On Interval:")?.isEnabled, false)
    }

    /// The interval of the rotation is shown with a checkmark.
    func testTheIntervalOfTheRotationIsChecked() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(intervalMinutes: .daily))

        let rotateSubmenu = menu.menu.item(titled: "Rotate")?.submenu
        XCTAssertEqual(rotateSubmenu?.item(titled: "Daily")?.state, .on)
        XCTAssertEqual(rotateSubmenu?.item(titled: "Off")?.state, .off)
    }

    /// A theme action needs a theme.
    func testTheThemeActionsAreDisabledWithoutATheme() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState())

        let rotateSubmenu = menu.menu.item(titled: "Rotate")?.submenu
        XCTAssertEqual(rotateSubmenu?.item(titled: "Shuffle Theme")?.isEnabled, false)
        XCTAssertEqual(rotateSubmenu?.item(titled: "Next Theme")?.isEnabled, false)
        XCTAssertEqual(rotateSubmenu?.item(titled: "Previous Theme")?.isEnabled, false)
        XCTAssertEqual(rotateSubmenu?.item(titled: "Shuffle Wallpaper")?.isEnabled, true)
    }

    /// A wallpaper whose file is gone cannot be applied.
    func testARecentWallpaperWhoseFileIsGoneIsDisabled() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(recentWallpapers: [
            MenuBarRecentWallpaper(
                path: "/wallpapers/gone.png",
                title: "gone.png",
                isCurrent: false,
                isEnabled: false
            )
        ]))

        let submenu = menu.menu.item(titled: "Recent Wallpapers")?.submenu
        XCTAssertEqual(submenu?.item(titled: "gone.png")?.isEnabled, false)
    }

    /// The submenus with items in them can be opened.
    func testTheSubmenuParentsAreEnabled() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            themes: [MenuBarTheme(id: "a", title: "Sunset")],
            recentWallpapers: [
                MenuBarRecentWallpaper(
                    path: "/wallpapers/one.png",
                    title: "one.png",
                    isCurrent: false,
                    isEnabled: true
                )
            ]
        ))

        XCTAssertEqual(menu.menu.item(titled: "Rotate")?.isEnabled, true)
        XCTAssertEqual(menu.menu.item(titled: "Theme")?.isEnabled, true)
        XCTAssertEqual(menu.menu.item(titled: "Recent Wallpapers")?.isEnabled, true)
    }
}
