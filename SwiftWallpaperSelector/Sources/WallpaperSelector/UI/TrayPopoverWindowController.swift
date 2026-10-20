import AppKit
import SwiftUI
import Combine

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
    /// The width of the popover. The height follows the content.
    static let popoverWidth: CGFloat = 300

    private var statusItem: NSStatusItem?

    private var viewModel: TrayPopoverViewModel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let hostingView: NSHostingView<AnyView>
    private var cancellables = Set<AnyCancellable>()


    convenience init(
        statusItem: NSStatusItem?,
        appState: AppState
    ) {
        let viewModel = TrayPopoverViewModel(appState: appState)
        let view = TrayPopoverView().environmentObject(viewModel)
        let hostingView = NSHostingView(rootView: AnyView(view))
        // The hosting view follows the window, so the content is laid out
        // in the size of the window.
        hostingView.autoresizingMask = [.width, .height]
        let materialView = NSVisualEffectView()
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        let window = PopoverWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.popoverWidth, height: 1),
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

        self.init(window: window, hostingView: hostingView)
        self.statusItem = statusItem
        self.viewModel = viewModel
        materialView.addSubview(hostingView)
        hostingView.frame = materialView.bounds
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
        observeContentChanges()
    }

    private init(window: NSWindow, hostingView: NSHostingView<AnyView>) {
        self.hostingView = hostingView
        super.init(window: window)
    }

    // The initializer is not failable, so it builds against a superclass
    // initializer that is failable and against one that is not.
    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }

        // The frame is set before the window is ordered in, so the popover
        // does not flash in the corner of the screen.
        layout(in: screenFrame)

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitors()
    }

    /// The height the SwiftUI content needs.
    ///
    /// The content decides how tall the popover is, so a longer list of
    /// wallpapers makes it taller and a shorter one makes it shorter.
    func contentHeight() -> CGFloat {
        hostingView.layoutSubtreeIfNeeded()
        return max(hostingView.fittingSize.height, 1)
    }

    /// The height of the popover: the height of its content, capped by the
    /// visible frame of the display.
    static func height(forContentHeight contentHeight: CGFloat, in screenFrame: CGRect) -> CGFloat {
        min(contentHeight, screenFrame.height)
    }

    /// Sizes the window to its content and places it inside the visible
    /// frame of the display.
    func layout(in screenFrame: CGRect) {
        let width = Self.popoverWidth
        let height = Self.height(forContentHeight: contentHeight(), in: screenFrame)
        window?.setContentSize(NSSize(width: width, height: height))

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
        window?.setFrameOrigin(
            Self.clampedOrigin(
                origin,
                in: screenFrame,
                width: width,
                height: height
            )
        )
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
        let clampedX = min(max(origin.x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - width))
        let clampedY = min(max(origin.y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - height))
        return CGPoint(x: clampedX, y: clampedY)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        hide()
    }

    /// The content of the popover changed, so the window takes the new
    /// height of the content.
    private func observeContentChanges() {
        viewModel?.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // The content is laid out after the change, so the height is
                // measured in the next turn of the main queue.
                DispatchQueue.main.async { [weak self] in self?.resizeToContent() }
            }
            .store(in: &cancellables)
    }

    private func resizeToContent() {
        guard let window, window.isVisible else { return }
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }
        layout(in: screenFrame)
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
