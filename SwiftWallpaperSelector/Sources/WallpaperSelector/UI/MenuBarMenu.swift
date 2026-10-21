import AppKit

/// The state the menu bar menu shows.
///
/// The menu is a pure function of this state: the mapping from the view
/// model to the state is the only place that knows what the menu shows.
struct MenuBarMenuState: Equatable {
    /// The title of the status line: the active theme or "All Folders".
    var title: String = ""
    /// The failures the menu shows at the top.
    var errorMessages: [String] = []
    /// The preview needs at least one folder.
    var isPreviewEnabled = false
    var isRotationActive = false
    var isRotationControlDisabled = false
    var intervalMinutes: RotationInterval = .off
    var rotationAction: RotationAction = .shuffle
    var themes: [MenuBarTheme] = []
    var selectedThemeID: String?
    var recentWallpapers: [MenuBarRecentWallpaper] = []
    var allSpaces = false
    var matchSystemAppearance = false
}

/// A theme of the menu.
struct MenuBarTheme: Equatable {
    let id: String
    let title: String
}

/// A wallpaper of the recent list of the menu.
struct MenuBarRecentWallpaper: Equatable {
    let path: String
    let title: String
    /// The wallpaper is the one that is shown.
    let isCurrent: Bool
    /// The file is gone, so the item cannot be used.
    let isEnabled: Bool
}

/// The action a menu item runs.
enum MenuBarMenuAction {
    case showMainWindow
    case showPreview
    case toggleRotation
    case shuffle
    case next
    case previous
    case selectTheme(String?)
    case setInterval(RotationInterval)
    case setRotationAction(RotationAction)
    case toggleAllSpaces
    case toggleMatchAppearance
    case selectRecentWallpaper(String)
    case openSettings
    case quit
}

/// The actions the items of the menu run.
///
/// The menu does not know the controller, so a menu can be built and
/// updated in a test without a status item in the menu bar of the machine.
struct MenuBarMenuActions {
    var showMainWindow: () -> Void = {}
    var showPreview: () -> Void = {}
    var toggleRotation: () -> Void = {}
    var shuffle: () -> Void = {}
    var next: () -> Void = {}
    var previous: () -> Void = {}
    var selectTheme: (String?) -> Void = { _ in }
    var setInterval: (RotationInterval) -> Void = { _ in }
    var setRotationAction: (RotationAction) -> Void = { _ in }
    var toggleAllSpaces: () -> Void = {}
    var toggleMatchAppearance: () -> Void = {}
    var selectRecentWallpaper: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

/// The menu of the menu bar item.
///
/// The menu is built once and kept for the whole life of the controller. A
/// menu that is already open keeps the object it was opened with, so a new
/// state changes the items of the menu that is on the screen instead of
/// putting a new menu on the status item.
///
/// The class owns an `NSMenu` instead of being one. A subclass of `NSMenu`
/// has to implement `init(coder:)`, and whether that initializer is failable
/// depends on the SDK, so the code would only build on some of them.
@MainActor
final class MenuBarMenu: NSObject {

    /// The menu the status item shows.
    let menu: NSMenu

    /// The actions the items run. The controller fills them in.
    var actions = MenuBarMenuActions()

    private var errorItems: [NSMenuItem] = []
    private let errorSeparator = NSMenuItem.separator()
    private let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openMainItem = NSMenuItem(title: "Open Main Window", action: nil, keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "Preview Wallpapers", action: nil, keyEquivalent: "")
    private let rotationItem = NSMenuItem(title: "Start Rotation", action: nil, keyEquivalent: "")
    private let shuffleItem = NSMenuItem(title: "Shuffle", action: nil, keyEquivalent: "")
    private let nextItem = NSMenuItem(title: "Next Wallpaper", action: nil, keyEquivalent: "")
    private let previousItem = NSMenuItem(title: "Previous Wallpaper", action: nil, keyEquivalent: "")
    private let recentItem = NSMenuItem(title: "Recent Wallpapers", action: nil, keyEquivalent: "")
    private let recentSeparator = NSMenuItem.separator()
    private let rotateItem = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
    private let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
    private let allSpacesItem = NSMenuItem(title: "All Spaces", action: nil, keyEquivalent: "")
    private let appearanceItem = NSMenuItem(title: "Match System Appearance", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Wallpaper Selector", action: nil, keyEquivalent: "")

    private let recentMenu = NSMenu(title: "Recent Wallpapers")
    private let rotateMenu = NSMenu(title: "Rotate")
    private let themeMenu = NSMenu(title: "Theme")
    private let allFoldersItem = NSMenuItem(title: "All Folders", action: nil, keyEquivalent: "")

    private var intervalItems: [RotationInterval: NSMenuItem] = [:]
    private var rotationActionItems: [RotationAction: NSMenuItem] = [:]
    private var themeItems: [String: NSMenuItem] = [:]
    private var recentItems: [String: NSMenuItem] = [:]

    init(title: String) {
        menu = NSMenu(title: title)
        super.init()
        // The items set `isEnabled` by hand: AppKit must not enable the
        // items again.
        menu.autoenablesItems = false
        recentMenu.autoenablesItems = false
        rotateMenu.autoenablesItems = false
        themeMenu.autoenablesItems = false
        buildItems()
    }

    /// Updates the items of the menu in place.
    ///
    /// The menu object stays the same, so a menu that is open shows the new
    /// state. The items keep their identity, so a click on an open menu
    /// always runs the current action.
    func update(with state: MenuBarMenuState) {
        updateErrors(state.errorMessages)
        statusItem.title = state.title
        previewItem.isEnabled = state.isPreviewEnabled
        rotationItem.title = state.isRotationActive ? "Stop Rotation" : "Start Rotation"
        rotationItem.isEnabled = !state.isRotationControlDisabled
        allSpacesItem.state = state.allSpaces ? .on : .off
        appearanceItem.state = state.matchSystemAppearance ? .on : .off
        updateRecentWallpapers(state.recentWallpapers)
        updateRotateSubmenu(with: state)
        updateThemeSubmenu(with: state)
    }

    // MARK: - The items

    private func buildItems() {
        // The menu shows two failures at most: the wallpaper failure and
        // the hot-key failure. The items are hidden when there is no
        // failure, so the items keep their place in the menu.
        for _ in 0..<2 {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.isHidden = true
            errorItems.append(item)
            menu.addItem(item)
        }
        errorSeparator.isHidden = true
        menu.addItem(errorSeparator)

        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        openMainItem.target = self
        openMainItem.action = #selector(runAction(_:))
        openMainItem.representedObject = MenuBarMenuAction.showMainWindow
        openMainItem.image = symbol("photo.on.rectangle.angled")
        menu.addItem(openMainItem)

        previewItem.target = self
        previewItem.action = #selector(runAction(_:))
        previewItem.representedObject = MenuBarMenuAction.showPreview
        previewItem.image = symbol("eye")
        menu.addItem(previewItem)

        menu.addItem(NSMenuItem.separator())

        rotationItem.target = self
        rotationItem.action = #selector(runAction(_:))
        rotationItem.representedObject = MenuBarMenuAction.toggleRotation
        menu.addItem(rotationItem)

        menu.addItem(NSMenuItem.separator())

        addActionItem(shuffleItem, action: .shuffle)
        addActionItem(nextItem, action: .next)
        addActionItem(previousItem, action: .previous)

        menu.addItem(NSMenuItem.separator())

        recentItem.submenu = recentMenu
        recentItem.image = symbol("clock.arrow.circlepath")
        recentItem.isEnabled = true
        recentItem.isHidden = true
        menu.addItem(recentItem)
        recentSeparator.isHidden = true
        menu.addItem(recentSeparator)

        rotateItem.submenu = rotateMenu
        rotateItem.image = symbol("arrow.triangle.2.circlepath")
        rotateItem.isEnabled = true
        menu.addItem(rotateItem)

        themeItem.submenu = themeMenu
        themeItem.image = symbol("paintpalette")
        themeItem.isEnabled = true
        menu.addItem(themeItem)

        menu.addItem(NSMenuItem.separator())

        allSpacesItem.target = self
        allSpacesItem.action = #selector(runAction(_:))
        allSpacesItem.representedObject = MenuBarMenuAction.toggleAllSpaces
        allSpacesItem.image = symbol("rectangle.stack")
        menu.addItem(allSpacesItem)

        appearanceItem.target = self
        appearanceItem.action = #selector(runAction(_:))
        appearanceItem.representedObject = MenuBarMenuAction.toggleMatchAppearance
        appearanceItem.image = symbol("circle.lefthalf.filled")
        menu.addItem(appearanceItem)

        menu.addItem(NSMenuItem.separator())

        settingsItem.target = self
        settingsItem.action = #selector(runAction(_:))
        settingsItem.representedObject = MenuBarMenuAction.openSettings
        settingsItem.image = symbol("gearshape")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        quitItem.target = self
        quitItem.action = #selector(runAction(_:))
        quitItem.representedObject = MenuBarMenuAction.quit
        quitItem.image = symbol("power", colored: .systemRed)
        menu.addItem(quitItem)

        buildRotateSubmenu()
        buildThemeSubmenu()
    }

    private func addActionItem(_ item: NSMenuItem, action: MenuBarMenuAction) {
        item.target = self
        item.action = #selector(runAction(_:))
        item.representedObject = action
        menu.addItem(item)
    }

    private func buildRotateSubmenu() {
        let intervals: [(RotationInterval, String)] = [
            (.off, "Off"),
            (.minutes30, "Every 30 Minutes"),
            (.hour1, "Every Hour"),
            (.hours12, "Every 12 Hours"),
            (.daily, "Daily")
        ]
        for (interval, label) in intervals {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.target = self
            item.action = #selector(runAction(_:))
            item.representedObject = MenuBarMenuAction.setInterval(interval)
            intervalItems[interval] = item
            rotateMenu.addItem(item)
        }

        rotateMenu.addItem(NSMenuItem.separator())

        let onIntervalLabel = NSMenuItem(title: "On Interval:", action: nil, keyEquivalent: "")
        onIntervalLabel.isEnabled = false
        rotateMenu.addItem(onIntervalLabel)

        let icons: [(RotationAction, String)] = [
            (.shuffle, "shuffle"),
            (.next, "chevron.right"),
            (.previous, "chevron.left"),
            (.themeShuffle, "shuffle"),
            (.themeNext, "chevron.right"),
            (.themePrevious, "chevron.left")
        ]
        for (action, iconName) in icons {
            let item = NSMenuItem(title: action.label, action: nil, keyEquivalent: "")
            item.target = self
            item.action = #selector(runAction(_:))
            item.representedObject = MenuBarMenuAction.setRotationAction(action)
            item.image = symbol(iconName, colored: action.isThemeAction ? .controlAccentColor : nil)
            rotationActionItems[action] = item
            rotateMenu.addItem(item)
        }
    }

    private func buildThemeSubmenu() {
        allFoldersItem.target = self
        allFoldersItem.action = #selector(runAction(_:))
        allFoldersItem.representedObject = MenuBarMenuAction.selectTheme(nil)
        allFoldersItem.image = symbol("folder")
        themeMenu.addItem(allFoldersItem)
    }

    // MARK: - The update

    private func updateErrors(_ messages: [String]) {
        while errorItems.count < messages.count {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            // The new item comes before the separator that closes the block.
            menu.insertItem(item, at: errorItems.count)
            errorItems.append(item)
        }
        for (index, item) in errorItems.enumerated() {
            guard index < messages.count else {
                item.isHidden = true
                continue
            }
            let message = messages[index]
            item.title = message
            item.attributedTitle = NSAttributedString(
                string: message,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            item.isHidden = false
        }
        errorSeparator.isHidden = messages.isEmpty
    }

    private func updateRecentWallpapers(_ wallpapers: [MenuBarRecentWallpaper]) {
        let gone = recentItems.keys.filter { path in
            !wallpapers.contains(where: { $0.path == path })
        }
        for path in gone {
            guard let item = recentItems[path] else { continue }
            recentMenu.removeItem(item)
            recentItems.removeValue(forKey: path)
        }
        for (index, wallpaper) in wallpapers.enumerated() {
            let item = recentItems[wallpaper.path] ?? makeRecentItem(wallpaper)
            item.title = wallpaper.title
            item.state = wallpaper.isCurrent ? .on : .off
            item.isEnabled = wallpaper.isEnabled
            recentItems[wallpaper.path] = item
            move(item, to: index, in: recentMenu)
        }
        // The recent list is only shown when there is a history.
        recentItem.isHidden = wallpapers.isEmpty
        recentSeparator.isHidden = wallpapers.isEmpty
    }

    private func updateRotateSubmenu(with state: MenuBarMenuState) {
        for (interval, item) in intervalItems {
            item.state = state.intervalMinutes == interval ? .on : .off
            item.isEnabled = !state.isRotationControlDisabled
        }
        for (action, item) in rotationActionItems {
            item.state = state.rotationAction == action ? .on : .off
            // A theme action needs a theme, and the rotation cannot run
            // while the appearance is matched.
            item.isEnabled = !state.isRotationControlDisabled
                && (!action.isThemeAction || !state.themes.isEmpty)
        }
    }

    private func updateThemeSubmenu(with state: MenuBarMenuState) {
        allFoldersItem.state = state.selectedThemeID == nil ? .on : .off
        let gone = themeItems.keys.filter { id in
            !state.themes.contains(where: { $0.id == id })
        }
        for id in gone {
            guard let item = themeItems[id] else { continue }
            themeMenu.removeItem(item)
            themeItems.removeValue(forKey: id)
        }
        for (index, theme) in state.themes.enumerated() {
            let item = themeItems[theme.id] ?? makeThemeItem(theme)
            item.title = theme.title
            item.state = theme.id == state.selectedThemeID ? .on : .off
            themeItems[theme.id] = item
            // The first item of the submenu is "All Folders".
            move(item, to: index + 1, in: themeMenu)
        }
    }

    private func makeThemeItem(_ theme: MenuBarTheme) -> NSMenuItem {
        let item = NSMenuItem(title: theme.title, action: nil, keyEquivalent: "")
        item.target = self
        item.action = #selector(runAction(_:))
        item.representedObject = MenuBarMenuAction.selectTheme(theme.id)
        item.image = symbol("paintpalette", colored: .controlAccentColor)
        return item
    }

    private func makeRecentItem(_ wallpaper: MenuBarRecentWallpaper) -> NSMenuItem {
        let item = NSMenuItem(title: wallpaper.title, action: nil, keyEquivalent: "")
        item.target = self
        item.action = #selector(runAction(_:))
        item.representedObject = MenuBarMenuAction.selectRecentWallpaper(wallpaper.path)
        return item
    }

    /// Puts the item at the given index. The item keeps its identity, so a
    /// click on an open menu always runs the current action.
    private func move(_ item: NSMenuItem, to index: Int, in submenu: NSMenu) {
        let current = submenu.index(of: item)
        guard current != index else { return }
        if current != -1 {
            submenu.removeItem(item)
        }
        submenu.insertItem(item, at: min(index, submenu.numberOfItems))
    }

    // MARK: - The actions

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuBarMenuAction else { return }
        switch action {
        case .showMainWindow:
            actions.showMainWindow()
        case .showPreview:
            actions.showPreview()
        case .toggleRotation:
            actions.toggleRotation()
        case .shuffle:
            actions.shuffle()
        case .next:
            actions.next()
        case .previous:
            actions.previous()
        case .selectTheme(let themeID):
            actions.selectTheme(themeID)
        case .setInterval(let interval):
            actions.setInterval(interval)
        case .setRotationAction(let action):
            actions.setRotationAction(action)
        case .toggleAllSpaces:
            actions.toggleAllSpaces()
        case .toggleMatchAppearance:
            actions.toggleMatchAppearance()
        case .selectRecentWallpaper(let path):
            actions.selectRecentWallpaper(path)
        case .openSettings:
            actions.openSettings()
        case .quit:
            actions.quit()
        }
    }

    private func symbol(_ name: String, colored color: NSColor? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        guard let color = color else { return base }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(config)
    }
}

extension NSMenu {
    /// The first item with the given title.
    func item(titled title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }
}
