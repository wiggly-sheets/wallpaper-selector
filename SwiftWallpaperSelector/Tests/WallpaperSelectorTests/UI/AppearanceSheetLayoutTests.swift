import XCTest
import SwiftUI
import AppKit
@testable import WallpaperSelector

@MainActor
final class AppearanceSheetLayoutTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var appState: AppState!
    var settingsViewModel: SettingsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        settingsManager.replace(WallpaperSettings())
        let themeProvider = ThemeProvider(settingsManager: settingsManager)
        appState = AppState(
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
        settingsViewModel = SettingsViewModel(appState: appState)
    }

    override func tearDownWithError() throws {
        settingsViewModel = nil
        appState = nil
        settingsManager = nil
        settingsContext = nil
        try super.tearDownWithError()
    }

    private func makeSheet() -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(
            AppearanceSheet()
                .environmentObject(settingsViewModel)
                .environmentObject(appState)
        ))
    }

    /// The Appearance sheet has to fit its content: a body that is longer
    /// than the sheet must not push the OK button out of it, or the sheet
    /// cannot be confirmed. The body scrolls instead, so every part of the
    /// sheet stays inside the sheet.
    func testTheOkButtonStaysInsideTheAppearanceSheet() {
        let sheet = makeSheet()
        // The smallest sheet the app shows: the body scrolls when it needs
        // more room, so the OK button has to be inside this frame.
        sheet.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        sheet.layoutSubtreeIfNeeded()

        XCTAssertFalse(sheet.subviews.isEmpty, "The sheet has to have content")
        for subview in sheet.subviews {
            XCTAssertTrue(
                sheet.bounds.contains(subview.frame),
                "The sheet content \(subview.frame) falls outside of the sheet \(sheet.bounds): the OK button cannot be reached"
            )
        }
    }

    /// The sheet grows with its content: a fixed height would clip the OK
    /// button, because the body of the sheet is taller than that height.
    func testTheAppearanceSheetIsAsTallAsItsContent() {
        let content = NSHostingView(rootView: AppearanceDialog()
            .environmentObject(settingsViewModel)
            .environmentObject(appState))
        let sheet = makeSheet()

        XCTAssertGreaterThan(
            content.fittingSize.height,
            400,
            "The body of the sheet is taller than the fixed height the sheet used to have"
        )
        XCTAssertGreaterThanOrEqual(
            sheet.fittingSize.height,
            content.fittingSize.height,
            "The sheet has to grow with its content: a fixed height clips the OK button"
        )
    }
}
