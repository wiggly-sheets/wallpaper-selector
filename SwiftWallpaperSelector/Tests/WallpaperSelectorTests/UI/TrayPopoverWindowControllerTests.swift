import XCTest
@testable import WallpaperSelector

@MainActor
final class TrayPopoverWindowControllerTests: XCTestCase {

    /// The popover has to be able to become the key window: otherwise it
    /// never learns that the user switched to another app.
    func testThePopoverWindowCanBecomeKey() throws {
        let (controller, _) = try makeController()

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
            height: 300
        )

        // The icon is the anchor, not the middle of the status item window.
        XCTAssertEqual(origin.x, 1715 - 150)
        XCTAssertNotEqual(origin.x, 960 - 150)
        XCTAssertEqual(origin.y, 1080 - 300)
    }

    /// The height of the popover is the height of its content.
    func testThePopoverTakesTheHeightOfItsContent() throws {
        let (controller, _) = try makeController()
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        controller.layout(in: screenFrame)

        let contentHeight = controller.contentHeight()
        XCTAssertGreaterThan(contentHeight, 0, "The content of the popover has a height")
        XCTAssertEqual(
            controller.window?.frame.height,
            contentHeight,
            "The popover has to take the height of its content"
        )
    }

    /// More wallpapers make the content taller, so the popover is taller.
    func testThePopoverIsTallerWithMoreWallpapers() async throws {
        let (controller, context) = try makeController()
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        controller.layout(in: screenFrame)
        let heightWithoutWallpapers = controller.contentHeight()

        let folder = context.directory(named: "popover-images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png", "d.png", "e.png", "f.png", "g.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        context.makeSettingsManager().update { $0.folderPaths = [folder.path] }

        let deadline = Date().addingTimeInterval(10)
        while controller.contentHeight() <= heightWithoutWallpapers, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertGreaterThan(
            controller.contentHeight(),
            heightWithoutWallpapers,
            "The height of the popover has to follow the content"
        )
    }

    /// The height of the popover is capped by the visible frame of the
    /// display.
    func testTheHeightIsCappedByTheVisibleFrame() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(
            TrayPopoverWindowController.height(forContentHeight: 400, in: screenFrame),
            400,
            "A content that fits keeps its height"
        )
        XCTAssertEqual(
            TrayPopoverWindowController.height(forContentHeight: 2000, in: screenFrame),
            1080,
            "A content that is taller than the display is clamped to the display"
        )
    }

    /// A display that is shorter than the content has no room for the
    /// popover, so the popover is clamped to the display. The content
    /// scrolls, so every control is still reachable.
    func testThePopoverIsClampedToADisplayShorterThanTheContent() throws {
        let (controller, _) = try makeController()
        let screenFrame = CGRect(x: 0, y: 0, width: 800, height: 100)

        controller.layout(in: screenFrame)

        XCTAssertGreaterThan(
            controller.contentHeight(),
            screenFrame.height,
            "The content of the popover is taller than the display"
        )
        XCTAssertEqual(
            controller.window?.frame.height,
            screenFrame.height,
            "The popover must not be taller than the display"
        )
        XCTAssertTrue(
            screenFrame.contains(controller.window?.frame ?? .zero),
            "The popover must stay inside the visible frame"
        )
    }

    /// A display that is shorter than the popover has no room for it, so it
    /// still has to start at the bottom of the visible frame: a smaller
    /// origin would put it over the Dock and past the edge of the screen.
    func testThePopoverDoesNotHangBelowAShortDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 800, height: 400)
        let height = TrayPopoverWindowController.height(
            forContentHeight: 600,
            in: screenFrame
        )

        let origin = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 700, y: 380),
            in: screenFrame,
            width: 300,
            height: height
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
        XCTAssertLessThanOrEqual(
            origin.y + height,
            screenFrame.maxY,
            "The popover must fit into the visible frame"
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
            height: 300
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
            height: 300
        )
        XCTAssertEqual(outside.x, 1620)
        XCTAssertEqual(outside.y, 780)

        let below = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: -100, y: -100),
            in: screenFrame,
            width: 300,
            height: 300
        )
        XCTAssertEqual(below.x, 0)
        XCTAssertEqual(below.y, 0)

        let inside = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 100, y: 200),
            in: screenFrame,
            width: 300,
            height: 300
        )
        XCTAssertEqual(inside.x, 100)
        XCTAssertEqual(inside.y, 200)
    }

    /// A controller with an app state that has no wallpapers.
    private func makeController() throws -> (TrayPopoverWindowController, TestSettingsContext) {
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
        return (controller, context)
    }
}
