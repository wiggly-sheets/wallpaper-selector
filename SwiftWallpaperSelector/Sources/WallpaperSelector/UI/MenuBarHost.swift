import AppKit
import SwiftUI

@MainActor
struct MenuBarHost: NSViewControllerRepresentable {
    let appState: AppState
    let settingsViewModel: SettingsViewModel

    func makeNSViewController(context: Context) -> MenuBarHostingViewController {
        MenuBarHostingViewController(appState: appState, settingsViewModel: settingsViewModel)
    }

    func updateNSViewController(_ controller: MenuBarHostingViewController, context: Context) {}
}

@MainActor
final class MenuBarHostingViewController: NSViewController {
    private let appState: AppState
    private let settingsViewModel: SettingsViewModel
    private var menuBarController: MenuBarController?
    private var popoverController: TrayPopoverWindowController?
    private var fallbackSettingsWindowController: NSWindowController?
    private var pickerWindowController: NSWindowController?

    init(appState: AppState, settingsViewModel: SettingsViewModel) {
        self.appState = appState
        self.settingsViewModel = settingsViewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = MenuBarController(viewModel: MenuBarViewModel(appState: appState))
        controller.onShowMainWindow = { [weak self] in self?.showMainWindow() }
        controller.onShowPreview = { [weak self] in self?.showPopover() }
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBarController = controller
        controller.rebuildMenu()

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

        if appState.settings.folderPaths.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func handleHotKey(_ identifier: String) {
        switch identifier {
        case "showMain":
            showMainWindow()
        case "showPreview":
            showPopover()
        case "showMenu":
            menuBarController?.showMenu()
        default:
            break
        }
    }

    func showAllSpacesManualFallback(
        enabled: Bool,
        reason: AllSpacesManualFallbackReason
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Finish All Spaces Setup in System Settings"
        alert.informativeText = allSpacesFallbackMessage(enabled: enabled, reason: reason)
        alert.addButton(withTitle: "OK")

        if let window = pickerWindowController?.window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showMainWindow() {
        if pickerWindowController == nil {
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
        }

        pickerWindowController?.showWindow(nil)
        pickerWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPopover() {
        if popoverController == nil {
            popoverController = TrayPopoverWindowController(
                statusItem: menuBarController?.statusItem,
                appState: appState
            )
        }
        popoverController?.showWindow(nil)
    }

    private func openSettings() {
        let openedSwiftUISettings = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        if !openedSwiftUISettings {
            showFallbackSettingsWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFallbackSettingsWindow() {
        if fallbackSettingsWindowController == nil {
            let rootView = SettingsView().environmentObject(settingsViewModel)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.minSize = NSSize(width: 760, height: 560)
            window.contentMinSize = window.minSize
            window.contentViewController = NSHostingController(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.center()
            fallbackSettingsWindowController = NSWindowController(window: window)
        }
        fallbackSettingsWindowController?.showWindow(nil)
        fallbackSettingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func allSpacesFallbackMessage(
        enabled: Bool,
        reason: AllSpacesManualFallbackReason
    ) -> String {
        let desiredAction = enabled ? "turn on" : "turn off"
        let guidance = "Please \(desiredAction) ‘Show on all Spaces’ in Wallpaper settings."
        switch reason {
        case .accessibilityPermissionRequired:
            return "Wallpaper Selector needs Accessibility permission to change this setting automatically. \(guidance)"
        case .couldNotOpenWallpaperSettings:
            return "Wallpaper settings could not be opened. \(guidance)"
        case .systemSettingsUnavailable:
            return "System Settings did not finish opening. \(guidance)"
        case .showOnAllSpacesControlNotFound:
            return "The ‘Show on all Spaces’ control could not be found safely. \(guidance)"
        case .automationFailed(let detail):
            return "The setting could not be changed automatically (\(detail)). \(guidance)"
        }
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
        guard let path = notification.object as? String else { return }
        appState.setWallpaper(path)
    }
}
