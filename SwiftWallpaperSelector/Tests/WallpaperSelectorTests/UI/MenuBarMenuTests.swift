import XCTest
@testable import WallpaperSelector

@MainActor
final class MenuBarMenuTests: XCTestCase {

    /// The menu is built once and kept for the whole life of the
    /// controller. A menu that is already open keeps the object it was
    /// opened with, so the items have to be updated in place.
    func testTheMenuIsUpdatedInPlace() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            title: "All Folders",
            isPreviewEnabled: true
        ))

        let previewItem = menu.menu.item(titled: "Preview Wallpapers")
        let statusItem = menu.menu.item(titled: "All Folders")
        XCTAssertNotNil(previewItem)
        XCTAssertNotNil(statusItem)

        menu.update(with: MenuBarMenuState(
            title: "Sunset",
            isPreviewEnabled: false
        ))

        // The items are the same items, they only show the new state.
        XCTAssertTrue(menu.menu.item(titled: "Preview Wallpapers") === previewItem)
        XCTAssertEqual(previewItem?.isEnabled, false)
        XCTAssertTrue(menu.menu.item(titled: "Sunset") === statusItem)
        XCTAssertEqual(statusItem?.title, "Sunset")
    }

    /// The rotation item changes its title with the state of the rotation.
    func testTheRotationItemFollowsTheState() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState())
        XCTAssertEqual(menu.menu.item(titled: "Start Rotation")?.title, "Start Rotation")

        menu.update(with: MenuBarMenuState(isRotationActive: true))
        XCTAssertEqual(menu.menu.item(titled: "Stop Rotation")?.title, "Stop Rotation")
        XCTAssertNil(menu.menu.item(titled: "Start Rotation"))
    }

    /// The checkmarks of the menu follow the state.
    func testTheCheckmarksFollowTheState() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            allSpaces: true,
            matchSystemAppearance: true
        ))

        XCTAssertEqual(menu.menu.item(titled: "Apply to All Spaces (opens macOS Settings)")?.state, .on)
        XCTAssertEqual(menu.menu.item(titled: "Match System Appearance")?.state, .on)
    }

    /// The failures are shown at the top of the menu, in red and greyed out.
    func testTheFailuresAreShownAtTheTop() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(
            errorMessages: ["The shortcut is already used by another app."]
        ))

        let item = menu.menu.item(titled: "The shortcut is already used by another app.")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.isEnabled, false)
        XCTAssertEqual(item?.attributedTitle?.string, "The shortcut is already used by another app.")

        // The failure is gone, so the item is hidden.
        menu.update(with: MenuBarMenuState())
        XCTAssertEqual(menu.menu.item(titled: "The shortcut is already used by another app.")?.isHidden, true)
    }

    /// The recent list changes its length, so the submenu gains and loses
    /// items.
    func testTheRecentWallpapersListGainsAndLosesItems() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState())
        XCTAssertEqual(menu.menu.item(titled: "Recent Wallpapers")?.isHidden, true)

        menu.update(with: MenuBarMenuState(recentWallpapers: [
            MenuBarRecentWallpaper(
                path: "/wallpapers/one.png",
                title: "one.png",
                isCurrent: false,
                isEnabled: true
            ),
            MenuBarRecentWallpaper(
                path: "/wallpapers/two.png",
                title: "two.png",
                isCurrent: true,
                isEnabled: true
            )
        ]))

        let recentItem = menu.menu.item(titled: "Recent Wallpapers")
        XCTAssertEqual(recentItem?.isHidden, false)
        let submenu = recentItem?.submenu
        XCTAssertEqual(submenu?.items.count, 2)
        XCTAssertEqual(submenu?.item(titled: "one.png")?.state, .off)
        XCTAssertEqual(submenu?.item(titled: "two.png")?.state, .on)

        menu.update(with: MenuBarMenuState(recentWallpapers: [
            MenuBarRecentWallpaper(
                path: "/wallpapers/two.png",
                title: "two.png",
                isCurrent: true,
                isEnabled: true
            )
        ]))

        // The submenu is the same submenu, with one item less.
        XCTAssertTrue(recentItem?.submenu === submenu)
        XCTAssertEqual(submenu?.items.count, 1)
        XCTAssertEqual(submenu?.item(titled: "two.png")?.state, .on)
        XCTAssertNil(submenu?.item(titled: "one.png"))
    }

    /// The theme list changes its length too.
    func testTheThemeListGainsAndLosesItems() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        menu.update(with: MenuBarMenuState(themes: [
            MenuBarTheme(id: "a", title: "Sunset")
        ]))

        let submenu = menu.menu.item(titled: "Theme")?.submenu
        XCTAssertEqual(submenu?.items.count, 2)
        XCTAssertEqual(submenu?.item(titled: "All Folders")?.state, .on)

        menu.update(with: MenuBarMenuState(
            themes: [
                MenuBarTheme(id: "b", title: "Mountains"),
                MenuBarTheme(id: "a", title: "Sunset")
            ],
            selectedThemeID: "a"
        ))

        XCTAssertEqual(submenu?.items.count, 3)
        XCTAssertEqual(submenu?.item(titled: "Mountains")?.state, .off)
        XCTAssertEqual(submenu?.item(titled: "Sunset")?.state, .on)
        XCTAssertEqual(submenu?.item(titled: "All Folders")?.state, .off)
        // The order of the list follows the state.
        XCTAssertEqual(submenu?.items.map(\.title), ["All Folders", "Mountains", "Sunset"])

        menu.update(with: MenuBarMenuState(themes: [
            MenuBarTheme(id: "a", title: "Sunset")
        ]))
        XCTAssertEqual(submenu?.items.map(\.title), ["All Folders", "Sunset"])
    }

    /// A click on an open menu always runs the current action.
    func testAClickRunsTheCurrentAction() {
        let menu = MenuBarMenu(title: "Wallpaper Selector")
        var selectedThemes: [String?] = []
        menu.actions.selectTheme = { selectedThemes.append($0) }
        menu.update(with: MenuBarMenuState(themes: [
            MenuBarTheme(id: "a", title: "Sunset")
        ]))

        let themeItem = menu.menu.item(titled: "Theme")?.submenu?.item(titled: "Sunset")
        XCTAssertNotNil(themeItem)
        click(themeItem)

        XCTAssertEqual(selectedThemes, ["a"])
    }

    // MARK: - The helper

    /// Clicks the item the way AppKit does.
    private func click(_ item: NSMenuItem?) {
        guard let item, let action = item.action else { return }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }
}
