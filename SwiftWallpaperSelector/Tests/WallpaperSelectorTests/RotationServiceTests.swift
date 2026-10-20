import XCTest
@testable import WallpaperSelector

@MainActor
final class RotationServiceTests: XCTestCase {

    private var settingsContext: TestSettingsContext!
    private var settingsManager: SettingsManager!
    private var mockProvider: MockWallpaperProvider!
    private var themeProvider: ThemeProvider!
    private var rotationService: RotationService!
    private var wallpaperLibrary: WallpaperLibrary!

    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        mockProvider = MockWallpaperProvider()
        themeProvider = ThemeProvider(settingsManager: settingsManager)
        wallpaperLibrary = WallpaperLibrary()
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: mockProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
    }

    override func tearDownWithError() throws {
        rotationService.stop()
        mockProvider = nil
        themeProvider = nil
        settingsManager = nil
        rotationService = nil
        wallpaperLibrary = nil
        settingsContext = nil
        try super.tearDownWithError()
    }


    func testStartWhenIntervalIsSetAndAppearanceMatchingOff() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertTrue(rotationService.isRunning)
    }

    func testStopWhenIntervalIsOff() {
        settingsManager.update { s in
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertFalse(rotationService.isRunning)
    }

    func testStopWhenMatchSystemAppearanceIsOn() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = true
        }
        rotationService.start()
        XCTAssertFalse(rotationService.isRunning)
    }

    func testUpdateSettingsStopsTimerWhenIntervalTurnedOff() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }
        rotationService.start()
        XCTAssertTrue(rotationService.isRunning)

        settingsManager.update { s in
            s.intervalMinutes = .off
        }
        rotationService.updateSettings()
        XCTAssertFalse(rotationService.isRunning)
    }


    func testShuffleSelectsFromAvailableImages() async throws {
        let folderURL = settingsContext.directory(named: "shuffle-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent("test_shuffle.png")
        try "dummy".write(to: fileURL, atomically: true, encoding: .utf8)

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(mockProvider.appliedURLs, [fileURL])
    }

    func testNextSelectsSequentialImage() async throws {
        let folderURL = settingsContext.directory(named: "next-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let file1 = folderURL.appendingPathComponent("a.png")
        let file2 = folderURL.appendingPathComponent("b.png")
        try "dummy".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy".write(to: file2, atomically: true, encoding: .utf8)

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .next
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = file1.path
        }

        await rotationService.perform(.next)

        XCTAssertEqual(mockProvider.appliedURLs, [file2])
    }


    func testHistoryAvoidsImmediateRepeat() async throws {
        let folderURL = try makeFolder(named: "history-images", images: ["current.png", "other.png"])
        let current = folderURL.appendingPathComponent("current.png")
        let other = folderURL.appendingPathComponent("other.png")

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
            s.currentWallpaper = current.path
            s.wallpaperHistory = [current.path]
            s.historyLimit = 10
        }

        await rotationService.perform(.shuffle)

        // The wallpaper in the history is never picked again while another one is left.
        XCTAssertEqual(mockProvider.appliedURLs, [other])
    }

    func testHistoryIsSkippedWhenItIsNotTheCurrentWallpaper() async throws {
        let folderURL = try makeFolder(named: "history-only-images", images: ["used.png", "other.png"])
        let used = folderURL.appendingPathComponent("used.png")
        let other = folderURL.appendingPathComponent("other.png")

        // The history holds one image and the current wallpaper is elsewhere,
        // so only one image is left to pick and every run picks the same one.
        // The repetition is here to catch a broken history rule: without the
        // filter the shuffle could pick the image from the history, and every
        // run is a new chance to catch it.
        for _ in 0..<10 {
            settingsManager.update { s in
                s.folderPaths = [folderURL.path]
                s.rotationAction = .shuffle
                s.intervalMinutes = .off
                s.matchSystemAppearance = false
                s.currentWallpaper = "/elsewhere/current.png"
                s.wallpaperHistory = [used.path]
                s.historyLimit = 10
            }

            await rotationService.perform(.shuffle)

            XCTAssertEqual(mockProvider.appliedURLs.last, other)
        }
    }

    func testFailedWallpaperApplyDoesNotPublishFalseCurrentWallpaperOrHistory() {
        let original = WallpaperSettings(
            currentWallpaper: "/wallpapers/original.png",
            wallpaperHistory: ["/wallpapers/original.png"]
        )
        settingsManager.replace(original)
        mockProvider.errorToThrow = MockWallpaperProviderError.configuredFailure

        let applied = rotationService.apply(URL(fileURLWithPath: "/wallpapers/failed.png"))

        XCTAssertFalse(applied)
        XCTAssertEqual(settingsManager.settings.currentWallpaper, original.currentWallpaper)
        XCTAssertEqual(settingsManager.settings.wallpaperHistory, original.wallpaperHistory)
        XCTAssertNotNil(rotationService.lastError)
    }

    func testFailedSettingsWriteIsReportedAsAnError() throws {
        try FileManager.default.removeItem(at: settingsManager.settingsDirectory)
        try Data("not-a-directory".utf8).write(to: settingsManager.settingsDirectory)

        let applied = rotationService.apply(URL(fileURLWithPath: "/wallpapers/applied.png"))

        XCTAssertTrue(applied)
        XCTAssertNotNil(rotationService.lastError)
    }

    /// The wallpaper reached one of the two displays, so it is on the screen
    /// and has to be recorded. The failed display is still reported.
    func testAPartialDisplayFailureStillRecordsTheWallpaper() {
        mockProvider.errorToThrow = WallpaperProviderError.failedToSetOnDisplays(
            failedCount: 1,
            totalCount: 2,
            underlying: MockWallpaperProviderError.configuredFailure
        )

        let applied = rotationService.apply(URL(fileURLWithPath: "/wallpapers/partial.png"))

        XCTAssertTrue(applied)
        XCTAssertEqual(settingsManager.settings.currentWallpaper, "/wallpapers/partial.png")
        XCTAssertEqual(settingsManager.settings.wallpaperHistory, ["/wallpapers/partial.png"])
        XCTAssertNotNil(rotationService.lastError, "The failed display has to be reported")
    }

    /// No display accepted the wallpaper, so nothing changed on the screen.
    func testATotalDisplayFailureDoesNotRecordTheWallpaper() {
        mockProvider.errorToThrow = WallpaperProviderError.failedToSetOnDisplays(
            failedCount: 2,
            totalCount: 2,
            underlying: MockWallpaperProviderError.configuredFailure
        )

        let applied = rotationService.apply(URL(fileURLWithPath: "/wallpapers/failed.png"))

        XCTAssertFalse(applied)
        XCTAssertNil(settingsManager.settings.currentWallpaper)
        XCTAssertTrue(settingsManager.settings.wallpaperHistory.isEmpty)
        XCTAssertNotNil(rotationService.lastError)
    }

    /// A wallpaper error that happened outside the rotation uses the same
    /// channel, so it shows up everywhere a rotation error does.
    func testAReportedWallpaperErrorIsShown() {
        rotationService.reportWallpaperError("x")

        XCTAssertEqual(rotationService.lastError, "x")
    }

    func testScheduledTimerDoesNotKeepTheServiceAlive() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }
        weak var weakService: RotationService?
        var service: RotationService? = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: mockProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )

        weakService = service
        service?.start()
        XCTAssertTrue(service?.isRunning == true)

        // The service is released by hand: the compiler may keep a local
        // alive until the end of the function.
        service = nil
        XCTAssertNil(weakService)
    }

    func testManualNextDoesNotReplaceScheduledRotationAction() async throws {
        let folderURL = settingsContext.directory(named: "manual-next-images")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let first = folderURL.appendingPathComponent("a.png")
        let second = folderURL.appendingPathComponent("b.png")
        try Data().write(to: first)
        try Data().write(to: second)
        settingsManager.update { settings in
            settings.folderPaths = [folderURL.path]
            settings.currentWallpaper = first.path
            // A theme action needs a theme: without one the stored action is
            // normalised into a wallpaper action.
            settings.themes = [Theme(id: "theme", name: "Theme", folderPaths: [])]
            settings.rotationAction = .themeShuffle
        }

        await rotationService.perform(.next)

        XCTAssertEqual(mockProvider.appliedURLs.last, second)
        XCTAssertEqual(settingsManager.settings.rotationAction, .themeShuffle)
    }

    func testThemeNextAppliesWallpaperWithASingleTheme() async throws {
        let result = try await applyThemeAction(.themeNext)

        XCTAssertEqual(result.applied, result.expected)
        XCTAssertEqual(settingsManager.settings.activeThemeID, "only")
    }

    func testThemeShuffleAppliesWallpaperWithASingleTheme() async throws {
        let result = try await applyThemeAction(.themeShuffle)

        XCTAssertEqual(result.applied, result.expected)
        XCTAssertEqual(settingsManager.settings.activeThemeID, "only")
    }

    func testThemePreviousAppliesWallpaperWithASingleTheme() async throws {
        let result = try await applyThemeAction(.themePrevious)

        XCTAssertEqual(result.applied, result.expected)
        XCTAssertEqual(settingsManager.settings.activeThemeID, "only")
    }

    func testThemeNextMovesToTheNextTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: "first")

        await rotationService.perform(.themeNext)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "second")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["second"])
    }

    func testThemePreviousMovesToThePreviousTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: "second")

        await rotationService.perform(.themePrevious)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "first")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["first"])
    }

    func testThemeNextWrapsAroundToTheFirstTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: "third")

        await rotationService.perform(.themeNext)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "first")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["first"])
    }

    func testThemePreviousWrapsAroundToTheLastTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: "first")

        await rotationService.perform(.themePrevious)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "third")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["third"])
    }

    /// The themes are a circle: without an active theme the next theme is the
    /// first one and the previous theme is the last one.
    func testThemeNextStartsWithTheFirstTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: nil)

        await rotationService.perform(.themeNext)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "first")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["first"])
    }

    func testThemePreviousStartsWithTheLastTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: nil)

        await rotationService.perform(.themePrevious)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "third")
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images["third"])
    }

    func testThemeShuffleSwitchesToAnotherTheme() async throws {
        let fixture = try makeThemeFixture()
        applyThemeFixture(fixture, activeThemeID: "first")

        await rotationService.perform(.themeShuffle)

        let activeThemeID = settingsManager.settings.activeThemeID
        XCTAssertNotEqual(activeThemeID, "first")
        XCTAssertNotNil(activeThemeID)
        XCTAssertEqual(mockProvider.appliedURLs.last, fixture.images[activeThemeID ?? ""])
    }

    /// While the appearance is matched, the system picks the theme: a theme
    /// action must not change the theme or the wallpaper.
    func testThemeActionsDoNothingWhileTheAppearanceIsMatched() async throws {
        let folderURL = try makeFolder(named: "matched-appearance-images", images: ["only.png"])
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.themes = [
                Theme(id: "first", name: "First", folderPaths: [folderURL.path]),
                Theme(id: "second", name: "Second", folderPaths: [folderURL.path])
            ]
            s.activeThemeID = "first"
            s.matchSystemAppearance = true
        }

        await rotationService.perform(.themeNext)
        await rotationService.perform(.themeShuffle)
        await rotationService.perform(.themePrevious)

        XCTAssertEqual(settingsManager.settings.activeThemeID, "first")
        XCTAssertTrue(mockProvider.appliedURLs.isEmpty)
    }

    func testPreviousSelectsTheSequentialPreviousImage() async throws {
        let folderURL = try makeFolder(named: "previous-images", images: ["a.png", "b.png"])

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.currentWallpaper = folderURL.appendingPathComponent("b.png").path
        }

        await rotationService.perform(.previous)

        XCTAssertEqual(mockProvider.appliedURLs, [folderURL.appendingPathComponent("a.png")])
    }

    func testNextWrapsAroundToTheFirstImage() async throws {
        let folderURL = try makeFolder(named: "wrap-next-images", images: ["a.png", "b.png"])

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.currentWallpaper = folderURL.appendingPathComponent("b.png").path
        }

        await rotationService.perform(.next)

        XCTAssertEqual(mockProvider.appliedURLs, [folderURL.appendingPathComponent("a.png")])
    }

    func testPreviousWrapsAroundToTheLastImage() async throws {
        let folderURL = try makeFolder(named: "wrap-previous-images", images: ["a.png", "b.png"])

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.currentWallpaper = folderURL.appendingPathComponent("a.png").path
        }

        await rotationService.perform(.previous)

        XCTAssertEqual(mockProvider.appliedURLs, [folderURL.appendingPathComponent("b.png")])
    }

    func testRotationWithoutFoldersReportsAnError() async {
        settingsManager.update { s in
            s.folderPaths = []
        }

        await rotationService.perform(.shuffle)

        XCTAssertNotNil(rotationService.lastError)
        XCTAssertTrue(mockProvider.appliedURLs.isEmpty)
    }

    func testRotationWithoutImagesReportsAnError() async throws {
        let folderURL = try makeFolder(named: "empty-images", images: [])

        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
        }

        await rotationService.perform(.shuffle)

        XCTAssertNotNil(rotationService.lastError)
        XCTAssertTrue(mockProvider.appliedURLs.isEmpty)
    }

    /// A theme action without a theme changes nothing, so the user has to
    /// know why the wallpaper stayed the same.
    func testAThemeActionWithoutThemesReportsTheError() async {
        settingsManager.update { s in
            s.folderPaths = []
            s.themes = []
            s.rotationAction = .themeNext
        }

        await rotationService.perform(.themeNext)

        XCTAssertEqual(rotationService.lastError, "No themes are configured.")
        XCTAssertTrue(mockProvider.appliedURLs.isEmpty)
    }

    func testScheduledIntervalMatchesTheSelectedRotationInterval() {
        settingsManager.update { s in
            s.intervalMinutes = .hour1
            s.matchSystemAppearance = false
        }

        rotationService.start()
        XCTAssertEqual(rotationService.scheduledInterval, 3600)

        settingsManager.update { s in
            s.intervalMinutes = .minutes30
        }
        rotationService.updateSettings()
        XCTAssertEqual(rotationService.scheduledInterval, 1800)
    }

    func testRequestEnqueuedDuringARunningRotationIsNotDropped() async throws {
        let folderURL = try makeFolder(named: "pending-images", images: ["a.png", "b.png"])
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
            s.intervalMinutes = .off
            s.matchSystemAppearance = false
        }
        let applied = expectation(description: "both rotations applied a wallpaper")
        applied.expectedFulfillmentCount = 2
        mockProvider.onSetWallpaper = { _ in applied.fulfill() }

        rotationService.enqueue(.shuffle)
        // The first rotation is already running, so this one has to wait.
        rotationService.enqueue(.next)

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(mockProvider.appliedURLs.count, 2)
    }

    /// A manual pick must not be overwritten by the rotation that is running.
    func testAManualPickDuringARunningRotationIsAppliedAfterIt() async throws {
        let folderURL = try makeFolder(named: "rotation-images", images: ["a.png"])
        let manualFolderURL = settingsContext.directory(named: "manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
        }
        var didPick = false
        mockProvider.onSetWallpaper = { _ in
            // The pick happens while the rotation is still running.
            guard !didPick else { return }
            didPick = true
            _ = self.rotationService.apply(manual)
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(mockProvider.appliedURLs.last, manual)
        XCTAssertEqual(settingsManager.settings.currentWallpaper, manual.path)
    }

    /// A second pick replaces the pending one: the user changed their mind,
    /// so only the last pick is applied.
    func testASecondManualPickReplacesThePendingOne() async throws {
        let folderURL = try makeFolder(named: "rotation-images", images: ["a.png"])
        let manualFolderURL = settingsContext.directory(named: "manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let firstPick = manualFolderURL.appendingPathComponent("first.png")
        let secondPick = manualFolderURL.appendingPathComponent("second.png")
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
        }
        var didPick = false
        mockProvider.onSetWallpaper = { _ in
            guard !didPick else { return }
            didPick = true
            // Both picks happen while the rotation is still running.
            _ = self.rotationService.apply(firstPick)
            _ = self.rotationService.apply(secondPick)
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(mockProvider.appliedURLs.last, secondPick)
        XCTAssertFalse(
            mockProvider.appliedURLs.contains(firstPick),
            "The replaced pick must not be applied"
        )
        XCTAssertEqual(settingsManager.settings.currentWallpaper, secondPick.path)
    }

    /// An action that is enqueued while `perform` runs must not be dropped.
    func testAnActionEnqueuedDuringPerformIsNotDropped() async throws {
        let folderURL = try makeFolder(named: "perform-pending-images", images: ["a.png", "b.png"])
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .next
        }
        let applied = expectation(description: "both actions apply a wallpaper")
        applied.expectedFulfillmentCount = 2
        var applicationCount = 0
        mockProvider.onSetWallpaper = { _ in
            applicationCount += 1
            if applicationCount == 1 {
                self.rotationService.enqueue(.next)
            }
            applied.fulfill()
        }

        await rotationService.perform(.next)

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(mockProvider.appliedURLs.count, 2)
    }

    /// Three presses during a running rotation must not collapse into one
    /// step: every request is kept.
    func testRepeatedRequestsDuringARunningRotationAreAllKept() async throws {
        let folderURL = try makeFolder(
            named: "fifo-images",
            images: ["a.png", "b.png", "c.png", "d.png"]
        )
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .next
        }
        let applied = expectation(description: "every request applies a wallpaper")
        applied.expectedFulfillmentCount = 4
        var didEnqueue = false
        mockProvider.onSetWallpaper = { _ in
            applied.fulfill()
            guard !didEnqueue else { return }
            didEnqueue = true
            // Three presses while the rotation is running.
            self.rotationService.enqueue(.next)
            self.rotationService.enqueue(.next)
            self.rotationService.enqueue(.next)
        }

        rotationService.enqueue(.next)

        await fulfillment(of: [applied], timeout: 10)
        XCTAssertEqual(mockProvider.appliedURLs.count, 4)
    }

    /// A pick that waits for a running rotation must say so: the user must
    /// not see a dead tap.
    func testAManualPickDuringARunningRotationReportsTheDeferral() async throws {
        let folderURL = try makeFolder(named: "deferred-pick-images", images: ["a.png"])
        let manualFolderURL = settingsContext.directory(named: "deferred-manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
        }
        var deferredMessage: String?
        var didPick = false
        mockProvider.onSetWallpaper = { _ in
            guard !didPick else { return }
            didPick = true
            let applied = self.rotationService.apply(manual)
            XCTAssertFalse(applied)
            deferredMessage = self.rotationService.lastError
        }

        await rotationService.perform(.shuffle)

        XCTAssertTrue(
            deferredMessage?.contains("rotation is in progress") == true,
            "The deferral must be reported, got \(deferredMessage ?? "no message")"
        )
        XCTAssertEqual(mockProvider.appliedURLs.last, manual)
        XCTAssertNil(rotationService.lastError, "The message must be cleared after the pick")
    }

    /// A failure that is reported while a pick waits must not replace the
    /// deferral notice: the notice tells the user why their pick is not on
    /// the screen yet.
    func testAReportedWallpaperErrorDoesNotReplaceTheDeferralNotice() async throws {
        let folderURL = try makeFolder(named: "reported-error-images", images: ["a.png"])
        let manualFolderURL = settingsContext.directory(named: "reported-error-manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
        }
        var messageWhilePending: String?
        var didPick = false
        mockProvider.onSetWallpaper = { _ in
            guard !didPick else { return }
            didPick = true
            _ = self.rotationService.apply(manual)
            // A display failure is reported while the pick waits.
            self.rotationService.reportWallpaperError("The wallpaper could not be set.")
            messageWhilePending = self.rotationService.lastError
        }

        await rotationService.perform(.shuffle)

        XCTAssertEqual(
            messageWhilePending,
            RotationService.deferredPickMessage,
            "The deferral notice must stay while the pick waits"
        )
        XCTAssertEqual(mockProvider.appliedURLs.last, manual)
        XCTAssertNil(rotationService.lastError, "The message must be cleared after the pick")
    }

    /// The pick waits for the rotation, so the rotation has to run even when
    /// it fails: the deferral notice must not stay and hide a later failure.
    func testThePendingPickIsAppliedWhenTheRotationFails() async throws {
        let manualFolderURL = settingsContext.directory(named: "failed-rotation-manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        let applied = expectation(description: "the pending pick is applied")
        mockProvider.onSetWallpaper = { _ in applied.fulfill() }

        // The rotation fails: there is no theme to change.
        rotationService.enqueue(.themeNext)
        // The pick arrives while the rotation is still running.
        XCTAssertFalse(rotationService.apply(manual))
        XCTAssertEqual(rotationService.lastError, RotationService.deferredPickMessage)

        await fulfillment(of: [applied], timeout: 10)

        XCTAssertEqual(mockProvider.appliedURLs, [manual])
        XCTAssertEqual(settingsManager.settings.currentWallpaper, manual.path)
    }

    /// The deferral notice is what the user sees while the pick waits: the
    /// failure of the rotation must not replace it.
    func testTheRotationFailureDoesNotReplaceTheDeferralNotice() async throws {
        let manualFolderURL = settingsContext.directory(named: "failed-rotation-notice")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        var messages: [String] = []
        let subscription = rotationService.$lastError.sink { message in
            if let message { messages.append(message) }
        }
        defer { subscription.cancel() }
        let applied = expectation(description: "the pending pick is applied")
        mockProvider.onSetWallpaper = { _ in applied.fulfill() }

        // The rotation fails: there is no theme to change.
        rotationService.enqueue(.themeNext)
        XCTAssertFalse(rotationService.apply(manual))

        await fulfillment(of: [applied], timeout: 10)

        XCTAssertFalse(
            messages.contains("No themes are configured."),
            "The failure of the rotation must not replace the deferral notice"
        )
        XCTAssertTrue(
            messages.contains(RotationService.deferredPickMessage),
            "The deferral notice has to be shown while the pick waits"
        )
    }

    /// A pick that fails is reported: the deferral notice is replaced by the
    /// failure, and the failure is reported after the settings write that
    /// stores the wallpaper.
    func testAFailedPendingPickReportsTheFailure() async throws {
        let folderURL = try makeFolder(named: "failed-pick-images", images: ["a.png"])
        let manualFolderURL = settingsContext.directory(named: "failed-pick-manual-pick")
        try FileManager.default.createDirectory(at: manualFolderURL, withIntermediateDirectories: true)
        let manual = manualFolderURL.appendingPathComponent("manual.png")
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.rotationAction = .shuffle
        }
        var didPick = false
        mockProvider.onSetWallpaper = { _ in
            guard !didPick else { return }
            didPick = true
            // The pick fails on one of the two displays.
            self.mockProvider.errorToThrow = WallpaperProviderError.failedToSetOnDisplays(
                failedCount: 1,
                totalCount: 2,
                underlying: MockWallpaperProviderError.configuredFailure
            )
            _ = self.rotationService.apply(manual)
        }

        await rotationService.perform(.shuffle)

        XCTAssertNotNil(rotationService.lastError, "The failed pick has to be reported")
        XCTAssertNotEqual(
            rotationService.lastError,
            RotationService.deferredPickMessage,
            "The deferral notice must not hide the failure"
        )
        XCTAssertEqual(
            settingsManager.settings.currentWallpaper,
            manual.path,
            "The wallpaper reached a display, so it is stored"
        )
    }

    /// A single theme must still apply a wallpaper when it is the only one.
    private func applyThemeAction(_ action: RotationAction) async throws -> (applied: URL?, expected: URL) {
        let folderURL = try makeFolder(named: "theme-images", images: ["only.png"])
        settingsManager.update { s in
            s.folderPaths = [folderURL.path]
            s.themes = [Theme(id: "only", name: "Only", folderPaths: [folderURL.path])]
            s.activeThemeID = nil
            s.matchSystemAppearance = false
        }

        await rotationService.perform(action)

        return (mockProvider.appliedURLs.last, folderURL.appendingPathComponent("only.png"))
    }

    /// Three themes with one folder each, so a theme change is visible in the
    /// applied wallpaper.
    private struct ThemeFixture {
        let folders: [String]
        let themes: [Theme]
        /// The image of every theme, keyed by the theme id.
        let images: [String: URL]
    }

    private func makeThemeFixture() throws -> ThemeFixture {
        var folders: [String] = []
        var themes: [Theme] = []
        var images: [String: URL] = [:]
        for id in ["first", "second", "third"] {
            let folderURL = try makeFolder(named: "theme-\(id)-images", images: ["\(id).png"])
            folders.append(folderURL.path)
            themes.append(Theme(id: id, name: id, folderPaths: [folderURL.path]))
            images[id] = folderURL.appendingPathComponent("\(id).png")
        }
        return ThemeFixture(folders: folders, themes: themes, images: images)
    }

    private func applyThemeFixture(_ fixture: ThemeFixture, activeThemeID: String?) {
        settingsManager.update { s in
            s.folderPaths = fixture.folders
            s.themes = fixture.themes
            s.activeThemeID = activeThemeID
            s.matchSystemAppearance = false
        }
    }

    private func makeFolder(named name: String, images: [String]) throws -> URL {
        let folderURL = settingsContext.directory(named: name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for image in images {
            try Data().write(to: folderURL.appendingPathComponent(image))
        }
        return folderURL
    }
}
