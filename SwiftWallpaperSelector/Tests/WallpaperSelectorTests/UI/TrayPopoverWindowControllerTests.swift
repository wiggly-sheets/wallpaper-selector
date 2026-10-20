import XCTest
@testable import WallpaperSelector

@MainActor
final class TrayPopoverWindowControllerTests: XCTestCase {

    /// The popover has to be able to become the key window: otherwise it
    /// never learns that the user switched to another app.
    func testThePopoverWindowCanBecomeKey() throws {
        let context = try TestSettingsContext()
        let settingsManager = context.makeSettingsManager()
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        let appState = AppState(
            settingsManager: settingsManager,
            rotationService: RotationService(
                settingsManager: settingsManager,
                wallpaperProvider: MockWallpaperProvider(),
                themeProvider: themeProvider,
                wallpaperLibrary: WallpaperLibrary()
            ),
            themeProvider: themeProvider,
            wallpaperLibrary: WallpaperLibrary()
        )
        let controller = TrayPopoverWindowController(statusItem: nil, appState: appState)

        XCTAssertTrue(
            controller.window?.canBecomeKey == true,
            "The popover has to be able to become the key window"
        )
    }

    /// The popover opens below the status item icon. The status item window
    /// covers the whole display, so its middle would open the popover in the
    /// middle of the screen.
    func testThePopoverOpensBelowTheStatusItemIcon() {
        let statusItemWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        statusItemWindow.setFrameOrigin(.zero)
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1920, height: 24))
        statusItemWindow.contentView = contentView
        let icon = NSView(frame: NSRect(x: 1700, y: 0, width: 30, height: 24))
        contentView.addSubview(icon)

        let origin = TrayPopoverWindowController.origin(
            for: icon,
            in: statusItemWindow,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            width: 300,
            height: 528
        )

        // The icon is the anchor, not the middle of the status item window.
        XCTAssertEqual(origin.x, 1715 - 150)
        XCTAssertNotEqual(origin.x, 960 - 150)
        XCTAssertEqual(origin.y, 1080 - 528)
    }

    /// A display that is shorter than the popover has no room for it, so the
    /// popover cannot fit into the visible frame. It still has to start at
    /// the bottom of the visible frame: a smaller origin would put it over
    /// the Dock and past the edge of the screen.
    func testThePopoverDoesNotHangBelowAShortDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 800, height: 400)

        let origin = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 700, y: 380),
            in: screenFrame,
            width: 300,
            height: 528
        )

        XCTAssertGreaterThanOrEqual(
            origin.y,
            screenFrame.minY,
            "The popover must not hang below the visible frame"
        )
        XCTAssertLessThanOrEqual(
            origin.y,
            screenFrame.maxY,
            "The popover must start inside the visible frame"
        )
    }

    /// The same rule for a display that is narrower than the popover: the
    /// popover must not hang beside it.
    func testThePopoverDoesNotHangBesideANarrowDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 200, height: 800)

        let origin = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 180, y: 700),
            in: screenFrame,
            width: 300,
            height: 528
        )

        XCTAssertGreaterThanOrEqual(
            origin.x,
            screenFrame.minX,
            "The popover must not hang beside the visible frame"
        )
        XCTAssertLessThanOrEqual(
            origin.x,
            screenFrame.maxX,
            "The popover must start inside the visible frame"
        )
    }

    /// A display with room for the popover clamps the origin as before: an
    /// origin outside the visible frame is pulled back into it.
    func testThePopoverIsPulledBackIntoADisplayWithRoom() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let outside = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 3000, y: 2000),
            in: screenFrame,
            width: 300,
            height: 528
        )
        XCTAssertEqual(outside.x, 1620)
        XCTAssertEqual(outside.y, 552)

        let below = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: -100, y: -100),
            in: screenFrame,
            width: 300,
            height: 528
        )
        XCTAssertEqual(below.x, 0)
        XCTAssertEqual(below.y, 0)

        let inside = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 100, y: 200),
            in: screenFrame,
            width: 300,
            height: 528
        )
        XCTAssertEqual(inside.x, 100)
        XCTAssertEqual(inside.y, 200)
    }
}
