import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {

    private(set) var statusItem: NSStatusItem?

    var onShowMainWindow: (() -> Void)?

    var onShowPreview: (() -> Void)?

    var onOpenSettings: (() -> Void)?

    private let viewModel: MenuBarViewModel
    private let menu: MenuBarMenu
    private var cancellables = Set<AnyCancellable>()
    private var isMenuUpdateScheduled = false


    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self.menu = MenuBarMenu(title: "Wallpaper Selector")
        super.init()
        menu.actions = MenuBarMenuActions(
            showMainWindow: { [weak self] in self?.onShowMainWindow?() },
            showPreview: { [weak self] in self?.onShowPreview?() },
            toggleRotation: { [weak self] in self?.viewModel.toggleRotation() },
            shuffle: { [weak self] in self?.viewModel.shuffle() },
            next: { [weak self] in self?.viewModel.next() },
            previous: { [weak self] in self?.viewModel.previous() },
            selectTheme: { [weak self] themeID in self?.viewModel.selectTheme(themeID) },
            setInterval: { [weak self] interval in self?.viewModel.setInterval(interval) },
            setRotationAction: { [weak self] action in self?.viewModel.setRotationAction(action) },
            toggleAllSpaces: { [weak self] in
                guard let self else { return }
                self.viewModel.setAllSpaces(!self.viewModel.allSpaces)
            },
            toggleMatchAppearance: { [weak self] in
                guard let self else { return }
                self.viewModel.setMatchSystemAppearance(!self.viewModel.matchSystemAppearance)
            },
            selectRecentWallpaper: { path in
                guard FileManager.default.fileExists(atPath: path) else { return }
                NotificationCenter.default.post(name: .ApplyRecentWallpaper, object: path)
            },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            quit: { [weak self] in self?.viewModel.quit() }
        )
        createStatusItem()
        observeViewModelChanges()
    }


    /// Updates the items of the menu in place.
    ///
    /// The menu object stays the same for the whole life of the
    /// controller, so a menu that is already open shows the new state.
    func updateMenu() {
        menu.update(with: viewModel.menuState)
    }

    func showMenu() {
        updateMenu()
        guard let button = statusItem?.button, let menu = statusItem?.menu else { return }
        NSApp.activate(ignoringOtherApps: true)
        // Anchor the menu at the bottom-left of the status item so it drops
        // below the menu bar instead of opening above the screen edge.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
        }
        statusItem?.menu = menu.menu
        updateMenu()
    }

    private func observeViewModelChanges() {
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleMenuUpdate() }
            .store(in: &cancellables)
    }

    /// Updates the menu at most once per main-queue turn: one settings
    /// change publishes many properties, and every one of them would
    /// otherwise update the menu again.
    private func scheduleMenuUpdate() {
        guard !isMenuUpdateScheduled else { return }
        isMenuUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMenuUpdateScheduled = false
            self.updateMenu()
        }
    }
}


extension Notification.Name {
    static let PopoverShowRequested = Notification.Name("PopoverShowRequested")
    static let RotationToggled = Notification.Name("RotationToggled")
    static let ApplyRecentWallpaper = Notification.Name("ApplyRecentWallpaper")
}
