import AppKit
import SwiftUI
import Combine

/// A thin menu-bar controller that delegates all business logic to `MenuBarViewModel`.
/// This class only handles UI plumbing: creating the status item, building menus,
/// and forwarding menu callbacks to the view model.
final class MenuBarController: NSObject {
    // MARK: - Public Properties

    /// The status item shown in the menu bar.
    private(set) var statusItem: NSStatusItem?

    /// Callback for showing the main window.
    var onShowMainWindow: (() -> Void)?

    /// Callback for showing the popover.
    var onShowPreview: (() -> Void)?

    /// Callback for opening settings.
    var onOpenSettings: (() -> Void)?

    /// Callback for shuffle action.
    var onShuffle: (() -> Void)?

    /// Callback for next wallpaper action.
    var onNext: (() -> Void)?

    /// Callback for previous wallpaper action.
    var onPrevious: (() -> Void)?

    /// Callback for toggling all spaces.
    var onToggleAllSpaces: ((Bool) -> Void)?

    /// Callback for toggling match system appearance.
    var onToggleMatchSystemAppearance: ((Bool) -> Void)?

    // MARK: - Private State

    private let viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        super.init()
        createStatusItem()
        observeViewModelChanges()
    }

    // MARK: - Public API

    /// Rebuild the menu-bar menu based on current view model state.
    func rebuildMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu(title: "Wallpaper Selector")

        // Current status display
        let statusMenuItem = NSMenuItem(title: viewModel.menuTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Open Main Window
        let openMainItem = NSMenuItem(title: "Open Main Window", action: #selector(showMainWindow(_:)), keyEquivalent: "")
        openMainItem.target = self
        openMainItem.image = symbol("photo.on.rectangle.angled")
        menu.addItem(openMainItem)

        // Preview Wallpapers
        let previewItem = NSMenuItem(title: "Preview Wallpapers", action: #selector(togglePopover(_:)), keyEquivalent: "")
        previewItem.target = self
        previewItem.isEnabled = !viewModel.folderPaths.isEmpty
        previewItem.image = symbol("eye")
        menu.addItem(previewItem)

        menu.addItem(NSMenuItem.separator())

        // Rotation controls
        let rotationTitle = viewModel.isRotationActive ? "Stop Rotation" : "Start Rotation"
        let rotationItem = NSMenuItem(title: rotationTitle, action: #selector(toggleRotation(_:)), keyEquivalent: "")
        rotationItem.target = self
        menu.addItem(rotationItem)

        menu.addItem(NSMenuItem.separator())

        // Quick actions
        menu.addItem(NSMenuItem(title: "Shuffle", action: #selector(shuffle(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Next Wallpaper", action: #selector(next(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Previous Wallpaper", action: #selector(previous(_:)), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Recent wallpapers submenu
        if !viewModel.recentWallpapers.isEmpty {
            let recentMenu = NSMenu(title: "Recent Wallpapers")

            // Limit to most recent 10 items to prevent overly long menu
            let displayedRecents = Array(viewModel.recentWallpapers.prefix(10))

            for (index, path) in displayedRecents.enumerated() {
                let menuItem = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(selectRecentWallpaper(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index
                menuItem.representedObject = path
                menuItem.state = path == viewModel.currentWallpaper ? .on : .off
                recentMenu.addItem(menuItem)
            }

            let recentMenuItem = NSMenuItem(title: "Recent Wallpapers", action: nil, keyEquivalent: "")
            recentMenuItem.image = symbol("clock.arrow.circlepath")
            recentMenuItem.submenu = recentMenu
            menu.addItem(recentMenuItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Rotate submenu
        if let rotateMenu = buildRotateSubmenu() {
            let rotateItem = NSMenuItem(title: "Rotate", action: nil, keyEquivalent: "")
            rotateItem.image = symbol("arrow.triangle.2.circlepath")
            rotateItem.submenu = rotateMenu
            menu.addItem(rotateItem)
        }

        // Theme submenu
        if let themeMenu = buildThemeSubmenu() {
            let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
            themeItem.image = symbol("paintpalette")
            themeItem.submenu = themeMenu
            menu.addItem(themeItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Apply to All Spaces
        let allSpacesItem = NSMenuItem(title: "Apply to All Spaces (opens macOS Settings)", action: #selector(toggleAllSpaces(_:)), keyEquivalent: "")
        allSpacesItem.target = self
        allSpacesItem.state = viewModel.allSpaces ? .on : .off
        allSpacesItem.image = symbol("rectangle.stack")
        menu.addItem(allSpacesItem)

        // Match System Appearance
        let appearanceItem = NSMenuItem(title: "Match System Appearance", action: #selector(toggleMatchAppearance(_:)), keyEquivalent: "")
        appearanceItem.target = self
        appearanceItem.state = viewModel.matchSystemAppearance ? .on : .off
        appearanceItem.image = symbol("circle.lefthalf.filled")
        menu.addItem(appearanceItem)

        menu.addItem(NSMenuItem.separator())

        // Settings and Quit
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.image = symbol("gearshape")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Wallpaper Selector", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbol("power", colored: .systemRed)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Builds the "Rotate" submenu of interval and action radio items.
    private func buildRotateSubmenu() -> NSMenu? {
        let submenu = NSMenu(title: "Rotate")
        let controlsDisabled = viewModel.matchSystemAppearance

        // Interval radios
        let intervals: [(RotationInterval, String)] = [
            (.off, "Off"),
            (.minutes30, "Every 30 Minutes"),
            (.hour1, "Every Hour"),
            (.hours12, "Every 12 Hours"),
            (.daily, "Daily")
        ]
        for (interval, label) in intervals {
            let item = NSMenuItem(title: label, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.state = viewModel.intervalMinutes == interval ? .on : .off
            item.isEnabled = !controlsDisabled
            item.representedObject = interval
            submenu.addItem(item)
        }

        submenu.addItem(NSMenuItem.separator())

        let onIntervalLabel = NSMenuItem(title: "On Interval:", action: nil, keyEquivalent: "")
        onIntervalLabel.isEnabled = false
        submenu.addItem(onIntervalLabel)

        // Action radios (theme actions tinted with the accent color)
        let themeActions: Set<RotationAction> = [.themeShuffle, .themeNext, .themePrevious]
        let actions: [(RotationAction, String)] = [
            (.shuffle, "shuffle"),
            (.next, "chevron.right"),
            (.previous, "chevron.left"),
            (.themeShuffle, "shuffle"),
            (.themeNext, "chevron.right"),
            (.themePrevious, "chevron.left")
        ]
        for (action, iconName) in actions {
            let item = NSMenuItem(title: action.label, action: #selector(setRotationAction(_:)), keyEquivalent: "")
            item.target = self
            item.state = viewModel.rotationAction == action ? .on : .off
            item.representedObject = action
            let themed = themeActions.contains(action)
            item.image = symbol(iconName, colored: themed ? .controlAccentColor : nil)
            item.isEnabled = !controlsDisabled && (!themed || !viewModel.themes.isEmpty)
            submenu.addItem(item)
        }

        return submenu
    }

    /// Builds the theme submenu. "All Folders" and the themes form one
    /// contiguous radio group with no separator between them.
    private func buildThemeSubmenu() -> NSMenu? {
        let submenu = NSMenu(title: "Theme")

        let allFoldersItem = NSMenuItem(title: "All Folders", action: #selector(selectTheme(_:)), keyEquivalent: "")
        allFoldersItem.target = self
        allFoldersItem.state = viewModel.selectedThemeID == nil ? .on : .off
        allFoldersItem.image = symbol("folder")
        submenu.addItem(allFoldersItem)

        for theme in viewModel.themes {
            let item = NSMenuItem(title: viewModel.themeLabel(theme), action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.state = theme.id == viewModel.selectedThemeID ? .on : .off
            item.image = symbol("paintpalette", colored: .controlAccentColor)
            item.representedObject = theme.id
            submenu.addItem(item)
        }

        return submenu
    }

    /// Returns an SF Symbol image, optionally tinted with the given color.
    private func symbol(_ name: String, colored color: NSColor? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        guard let color = color else { return base }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return base.withSymbolConfiguration(config)
    }

    // MARK: - Private

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        rebuildMenu()
    }

    private func observeViewModelChanges() {
        // Rebuild the menu whenever any published property changes (themes,
        // recents, rotation action, active theme, all spaces, appearance, etc.).
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func showMainWindow(_ sender: Any?) {
        onShowMainWindow?()
    }

    @objc private func togglePopover(_ sender: Any?) {
        onShowPreview?()
    }

    @objc private func toggleRotation(_ sender: Any?) {
        // Rotation toggle logic is handled by the service via AppState
        viewModel.toggleRotation()
    }

    @objc private func shuffle(_ sender: Any?) {
        viewModel.shuffle()
    }

    @objc private func next(_ sender: Any?) {
        viewModel.next()
    }

    @objc private func previous(_ sender: Any?) {
        viewModel.previous()
    }

    @objc private func selectTheme(_ sender: NSMenuItem?) {
        // The "All Folders" item carries no representedObject.
        let themeID = sender?.representedObject as? String
        viewModel.selectTheme(themeID)
    }

    @objc private func setInterval(_ sender: NSMenuItem?) {
        guard let interval = sender?.representedObject as? RotationInterval else { return }
        viewModel.setInterval(interval)
    }

    @objc private func setRotationAction(_ sender: NSMenuItem?) {
        guard let action = sender?.representedObject as? RotationAction else { return }
        viewModel.setRotationAction(action)
    }

    @objc private func toggleAllSpaces(_ sender: Any?) {
        onToggleAllSpaces?(!viewModel.allSpaces)
    }

    @objc private func toggleMatchAppearance(_ sender: Any?) {
        onToggleMatchSystemAppearance?(!viewModel.matchSystemAppearance)
    }

    @objc private func selectRecentWallpaper(_ sender: NSMenuItem?) {
        if let path = sender?.representedObject as? String {
            // Apply the selected recent wallpaper
            if FileManager.default.fileExists(atPath: path) {
                // Find the AppState from the view model to call setWallpaper
                // We need to access appState through a different approach since MenuBarController doesn't have direct access
                // Instead, we'll post a notification that the AppCoordinator can handle
                NotificationCenter.default.post(name: .ApplyRecentWallpaper, object: path)
            }
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings?()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let PopoverShowRequested = Notification.Name("PopoverShowRequested")
    static let RotationToggled = Notification.Name("RotationToggled")
    static let ApplyRecentWallpaper = Notification.Name("ApplyRecentWallpaper")
}
