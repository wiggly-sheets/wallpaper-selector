import XCTest
@testable import WallpaperSelector

@MainActor
final class TrayPopoverWindowControllerTests: XCTestCase {

    /// The popover has to be able to become the key window: otherwise it
    /// never learns that the user switched to another app.
    func testThePopoverWindowCanBecomeKey() throws {
        let (controller, _, _) = try makeController()

        XCTAssertTrue(
            controller.window?.canBecomeKey == true,
            "The popover has to be able to become the key window"
        )
    }

    /// macOS 26 draws the popover with the native Liquid Glass surface. Older
    /// systems keep the popover material, so the window always has a
    /// background.
    func testThePopoverUsesTheNativeGlassSurfaceOnMacOS26AndNewer() throws {
        let (controller, _, _) = try makeController()

        if #available(macOS 26.0, *) {
            let glassView = try XCTUnwrap(
                controller.window?.contentView as? NSGlassEffectView,
                "The popover has to use the native glass view on macOS 26 and newer"
            )
            XCTAssertEqual(glassView.style, .regular)
            XCTAssertEqual(
                glassView.cornerRadius,
                TrayPopoverWindowController.popoverCornerRadius
            )
            XCTAssertNotNil(
                glassView.contentView,
                "The SwiftUI content has to sit inside the glass effect"
            )
            controller.layout(in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            XCTAssertEqual(
                glassView.frame,
                controller.window?.contentView?.bounds,
                "The glass surface has to fill the popover"
            )
            XCTAssertEqual(
                glassView.contentView?.frame,
                glassView.bounds,
                "The content has to fill the glass surface"
            )
            if #available(macOS 27.0, *) {
                XCTAssertTrue(
                    glassView.effectIsInteractive,
                    "The glass of a popover with controls has to be interactive"
                )
            }
        } else {
            XCTAssertTrue(
                controller.window?.contentView is NSVisualEffectView,
                "The popover has to keep its material before macOS 26"
            )
        }
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

    /// A status item without a position (the system can hide it) must not
    /// put the popover in the corner of the screen.
    func testThePopoverFallsBackToTheRightEdgeWhenTheStatusItemHasNoPosition() {
        let statusItemWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: .zero)
        statusItemWindow.contentView = contentView
        // A hidden status item still reports a small icon at the origin.
        let icon = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        contentView.addSubview(icon)

        let origin = TrayPopoverWindowController.origin(
            for: icon,
            in: statusItemWindow,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            width: 360,
            height: 300
        )

        XCTAssertEqual(origin.x, 1560)
        XCTAssertEqual(origin.y, 780)
    }

    /// More wallpapers make the content taller, so the popover is taller.
    func testThePopoverIsTallerWithMoreWallpapers() async throws {
        let (controller, context, appState) = try makeController()
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        controller.layout(in: screenFrame)
        let heightWithoutWallpapers = controller.contentHeight()

        let folder = context.directory(named: "popover-images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.png", "b.png", "c.png", "d.png", "e.png", "f.png", "g.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        appState.updateSettings { $0.folderPaths = [folder.path] }
        await waitForImages(appState.$currentThemeImages) { !$0.isEmpty }
        controller.layout(in: screenFrame)

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
        let (controller, _, _) = try makeController()
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

    /// The clamp keeps the popover inside the visible frame, also when the
    /// display is shorter or narrower than the popover, and pulls an origin
    /// that is outside the frame back into it.
    func testThePopoverStaysInsideTheVisibleFrame() {
        let shortFrame = CGRect(x: 0, y: 0, width: 800, height: 400)
        let height = TrayPopoverWindowController.height(forContentHeight: 600, in: shortFrame)
        let clampedToTheHeight = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 700, y: 380),
            in: shortFrame,
            width: 300,
            height: height
        )
        XCTAssertGreaterThanOrEqual(clampedToTheHeight.y, shortFrame.minY)
        XCTAssertLessThanOrEqual(clampedToTheHeight.y, shortFrame.maxY)
        XCTAssertLessThanOrEqual(
            clampedToTheHeight.y + height,
            shortFrame.maxY,
            "The popover must fit into the visible frame"
        )

        let narrowFrame = CGRect(x: 0, y: 0, width: 200, height: 800)
        let clampedToTheWidth = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 180, y: 700),
            in: narrowFrame,
            width: 300,
            height: 300
        )
        XCTAssertGreaterThanOrEqual(clampedToTheWidth.x, narrowFrame.minX)
        XCTAssertLessThanOrEqual(clampedToTheWidth.x, narrowFrame.maxX)

        let roomyFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let outside = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 3000, y: 2000),
            in: roomyFrame,
            width: 300,
            height: 300
        )
        XCTAssertEqual(outside.x, 1620)
        XCTAssertEqual(outside.y, 780)

        let below = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: -100, y: -100),
            in: roomyFrame,
            width: 300,
            height: 300
        )
        XCTAssertEqual(below.x, 0)
        XCTAssertEqual(below.y, 0)

        let inside = TrayPopoverWindowController.clampedOrigin(
            CGPoint(x: 100, y: 200),
            in: roomyFrame,
            width: 300,
            height: 300
        )
        XCTAssertEqual(inside.x, 100)
        XCTAssertEqual(inside.y, 200)
    }

    /// The popover must be able to show over a full-screen app.
    func testThePopoverShowsOverFullScreenApps() throws {
        let (controller, _, _) = try makeController()

        let behavior = try XCTUnwrap(controller.window?.collectionBehavior)
        XCTAssertTrue(
            behavior.contains(.fullScreenAuxiliary),
            "The popover has to join the full-screen space of the active app"
        )
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.stationary))
    }

    /// A controller with an app state that has no wallpapers.
    private func makeController() throws -> (TrayPopoverWindowController, TestSettingsContext, AppState) {
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
        return (controller, context, appState)
    }
}
