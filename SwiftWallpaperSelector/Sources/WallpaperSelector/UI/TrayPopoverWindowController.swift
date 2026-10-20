import AppKit
import SwiftUI

extension Notification.Name {
    static let OpenMainWindowRequested = Notification.Name("OpenMainWindowRequested")
}

/// A borderless window that can become the key window.
///
/// AppKit refuses the key status for a window without a title bar, so the
/// popover would never learn that it lost the key.
final class PopoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class TrayPopoverWindowController: NSWindowController {
    private var statusItem: NSStatusItem?

    private var viewModel: TrayPopoverViewModel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?


    convenience init(
        statusItem: NSStatusItem?,
        appState: AppState
    ) {
        let viewModel = TrayPopoverViewModel(appState: appState)
        let view = TrayPopoverView().environmentObject(viewModel)
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let materialView = NSVisualEffectView()
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        let window = PopoverWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 528),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = materialView
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }


    override func showWindow(_ sender: Any?) {
        let width = 300.0
        let height = 528.0
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }

        // The vertical anchor comes from the screen: the status item window
        // frame is stale when displays of different heights are connected.
        let origin: CGPoint
        if let button = statusItem?.button, let buttonWindow = button.window {
            // The status item window covers the whole display, so the icon
            // itself is the anchor.
            origin = Self.origin(
                for: button,
                in: buttonWindow,
                screenFrame: screenFrame,
                width: width,
                height: height
            )
        } else {
            origin = CGPoint(x: screenFrame.maxX - width, y: screenFrame.maxY - height)
        }

        let clamped = Self.clampedOrigin(
            origin,
            in: screenFrame,
            width: width,
            height: height
        )
        // The frame is set before the window is ordered in, so the popover
        // does not flash in the corner of the screen.
        window?.setFrameOrigin(clamped)

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitors()
    }


    /// The origin of the popover: below the status item icon.
    ///
    /// The status item window covers the whole display, so the icon itself is
    /// the anchor. The window of the icon gives the position on the screen.
    static func origin(
        for button: NSView,
        in window: NSWindow,
        screenFrame: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let inWindow = button.convert(button.bounds, to: nil)
        let onScreen = window.convertToScreen(inWindow)
        return CGPoint(x: onScreen.midX - width / 2, y: screenFrame.maxY - height)
    }

    /// The origin of the popover inside the visible frame of the display.
    ///
    /// A display that is shorter or narrower than the popover has no room
    /// for it. The upper bound must never fall below the lower bound then,
    /// because the smaller of the two would be picked and the popover would
    /// hang off the bottom or off the right edge of the display.
    static func clampedOrigin(
        _ origin: CGPoint,
        in screenFrame: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        // shortcut: the height of the popover is fixed at 528 pt, upgrade when a display shorter than the popover has to be supported
        let clampedX = min(max(origin.x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - width))
        let clampedY = min(max(origin.y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - height))
        return CGPoint(x: clampedX, y: clampedY)
    }

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
