import AppKit
import SwiftUI

// Global notification names for communication from popover to services
extension Notification.Name {
    static let ShuffleRequested = Notification.Name("ShuffleRequested")
    static let NextRequested = Notification.Name("NextRequested")
    static let PreviousRequested = Notification.Name("PreviousRequested")
    static let OpenMainWindowRequested = Notification.Name("OpenMainWindowRequested")
}

/// Window controller for the compact tray popover.
/// Owns the popover view, the shared tray `statusItem` (for anchoring),
/// and auto-hides on blur per PLAN §7.
final class TrayPopoverWindowController: NSWindowController {
    private var statusItem: NSStatusItem?

    private var viewModel: TrayPopoverViewModel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    // MARK: - Init

    convenience init(
        statusItem: NSStatusItem?,
        settingsManager: SettingsManager,
        wallpaperProvider: WallpaperSetting,
        themeProvider: ThemeProvider,
        rotationService: RotationService
    ) {
        let viewModel = TrayPopoverViewModel(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            rotationService: rotationService
        )
        let view = TrayPopoverView().environmentObject(viewModel)
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let materialView = NSVisualEffectView()
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 528),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = materialView
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = .floating
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        self.init(window: window)
        self.statusItem = statusItem
        self.viewModel = viewModel
        materialView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])
        viewModel.onShowMainWindow = { [weak self] in
            self?.hide()
            NotificationCenter.default.post(name: .OpenMainWindowRequested, object: nil)
        }

        // Auto-hide when the popover loses focus.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    deinit {
        removeOutsideClickMonitors()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Presenting

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        let width = 300.0
        let height = 528.0
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }

        // Anchor centered under the tray icon (+4px below); fall back to the
        // top-right corner when the tray bounds are unavailable.
        let origin: CGPoint
        if let buttonFrame = statusItem?.button?.window?.frame {
            origin = CGPoint(x: buttonFrame.midX - width / 2, y: buttonFrame.minY - height - 4)
        } else {
            origin = CGPoint(x: screenFrame.maxX - width, y: screenFrame.maxY - height)
        }

        let clampedX = min(max(origin.x, screenFrame.minX), screenFrame.maxX - width)
        let clampedY = min(max(origin.y, screenFrame.minY), screenFrame.maxY - height)
        window?.setFrameOrigin(CGPoint(x: clampedX, y: clampedY))

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitors()
    }

    // MARK: - Blur handling

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        hide()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            DispatchQueue.main.async {
                self?.hideIfOutside(screenPoint: event.locationInWindow)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.hideIfOutside(screenPoint: screenPoint)
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func hideIfOutside(screenPoint: NSPoint) {
        guard let window, window.isVisible, !window.frame.contains(screenPoint) else { return }
        hide()
    }

    private func hide() {
        removeOutsideClickMonitors()
        window?.orderOut(nil)
    }
}
