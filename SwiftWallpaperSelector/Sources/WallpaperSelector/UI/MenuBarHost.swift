import AppKit
import SwiftUI

/// A hidden SwiftUI view that hosts the MenuBarController.
/// This is used as a WindowGroup scene to keep the menu-bar extra alive.
struct MenuBarHost: NSViewControllerRepresentable {
    let appState: AppState
    let rotationService: RotationService
    let settingsViewModel: SettingsViewModel

    func makeNSViewController(context: Context) -> MenuBarHostingViewController {
        MenuBarHostingViewController(appState: appState, rotationService: rotationService, settingsViewModel: settingsViewModel)
    }

    func updateNSViewController(_ nsViewController: MenuBarHostingViewController, context: Context) {
        nsViewController.appState = appState
        nsViewController.rotationService = rotationService
        nsViewController.settingsViewModel = settingsViewModel
    }
}

/// An NSViewController that owns the MenuBarController.
final class MenuBarHostingViewController: NSViewController {
    var appState: AppState
    var rotationService: RotationService
    var settingsViewModel: SettingsViewModel

    private var menuBarController: MenuBarController?
    private var hotKeyManager: HotKeyManager?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var appearanceMonitor: AppearanceMonitor?
    private var popoverController: TrayPopoverWindowController?
    private var settingsWindowController: NSWindowController?
    private var pickerWindowController: NSWindowController?

    init(appState: AppState, rotationService: RotationService, settingsViewModel: SettingsViewModel) {
        self.appState = appState
        self.rotationService = rotationService
        self.settingsViewModel = settingsViewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let provider = WallpaperProvider()
        let themeProvider = ThemeProvider(settingsManager: appState.settingsManager)
        self.appearanceMonitor = AppearanceMonitor(
            settingsManager: appState.settingsManager,
            wallpaperProvider: provider,
            themeProvider: themeProvider
        )

        let viewModel = MenuBarViewModel(
            appState: appState,
            rotationService: rotationService,
            themeProvider: themeProvider
        )
        let controller = MenuBarController(viewModel: viewModel)

        controller.onShowMainWindow = { [weak self] in self?.showMainWindow() }
        controller.onShowPreview = { [weak self] in self?.showPopover() }
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onShuffle = { [weak self] in self?.rotationService.tick() }
        controller.onNext = { [weak self] in
            self?.appState.updateSettings { $0.rotationAction = .next }
            self?.rotationService.tick()
        }
        controller.onPrevious = { [weak self] in
            self?.appState.updateSettings { $0.rotationAction = .previous }
            self?.rotationService.tick()
        }
        controller.onToggleAllSpaces = { [weak self] enabled in
            self?.appState.updateSettings { $0.allSpaces = enabled }
        }
        controller.onToggleMatchSystemAppearance = { [weak self] enabled in
            self?.appState.updateSettings { $0.matchSystemAppearance = enabled }
            self?.rotationService.updateSettings()
            if enabled {
                self?.appearanceMonitor?.applyAppearanceWallpaperIfNeeded()
            }
        }

        self.menuBarController = controller
        controller.rebuildMenu()

        // Register hotkeys
        let hotKeyManager = HotKeyManager(settingsManager: appState.settingsManager)
        hotKeyManager.onHotKeyPressed = { [weak self] identifier in
            self?.handleHotKey(identifier)
        }
        hotKeyManager.register()
        self.hotKeyManager = hotKeyManager

        // Register launch-at-login
        let loginManager = LaunchAtLoginManager()
        self.launchAtLoginManager = loginManager

        // Apply appearance wallpaper on launch if needed
        appearanceMonitor?.applyAppearanceWallpaperIfNeeded()

        // Observe notifications from the popover
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShuffleRequested),
            name: .ShuffleRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettingsWindow),
            name: .openSettingsWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainWindow),
            name: .OpenMainWindowRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNextRequested),
            name: .NextRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviousRequested),
            name: .PreviousRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplyRecentWallpaper),
            name: .ApplyRecentWallpaper,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarOpenSettings),
            name: .MenuBarOpenSettings,
            object: nil
        )

        // Match original first-run behavior: stay menu-bar-only once folders
        // exist, but immediately show folder setup for a fresh install.
        if appState.settings.folderPaths.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    private func showMainWindow() {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "Wallpaper Selector" }) {
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            let rootView = PickerWindow()
                .environmentObject(settingsViewModel)
                .environmentObject(appState)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Wallpaper Selector"
            window.minSize = NSSize(width: 520, height: 460)
            window.contentViewController = NSHostingController(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.center()
            pickerWindowController = NSWindowController(window: window)
            pickerWindowController?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPopover() {
        if popoverController == nil {
            popoverController = TrayPopoverWindowController(
                statusItem: menuBarController?.statusItem,
                settingsManager: appState.settingsManager,
                wallpaperProvider: WallpaperProvider(),
                themeProvider: ThemeProvider(settingsManager: appState.settingsManager),
                rotationService: rotationService
            )
        }
        popoverController?.showWindow(nil)
    }

    private func openSettings() {
        if settingsWindowController == nil {
            let rootView = SettingsView().environmentObject(settingsViewModel)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.minSize = NSSize(width: 760, height: 560)
            window.contentMinSize = window.minSize
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleHotKey(_ identifier: String) {
        switch identifier {
        case "showMain":
            showMainWindow()
        case "showPreview":
            showPopover()
        case "showMenu":
            menuBarController?.rebuildMenu()
        default:
            break
        }
    }

    @objc private func handleShuffleRequested() {
        rotationService.tick()
    }

    @objc private func handleNextRequested() {
        appState.updateSettings { $0.rotationAction = .next }
        rotationService.tick()
    }

    @objc private func handlePreviousRequested() {
        appState.updateSettings { $0.rotationAction = .previous }
        rotationService.tick()
    }

    @objc private func handleMenuBarOpenSettings() {
        openSettings()
    }

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    @objc private func handleOpenSettingsWindow() {
        openSettings()
    }

    @objc private func handleApplyRecentWallpaper(_ notification: Notification) {
        if let path = notification.object as? String {
            // Apply the wallpaper directly
            appState.setWallpaper(path)
        }
    }
}
