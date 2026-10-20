import XCTest
@testable import WallpaperSelector

@MainActor
final class SettingsViewModelTests: XCTestCase {
    var settingsContext: TestSettingsContext!
    var settingsManager: SettingsManager!
    var wallpaperProvider: MockWallpaperProvider!
    var themeProvider: ThemeProvider!
    var rotationService: RotationService!
    var appState: AppState!
    var viewModel: SettingsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsContext = try TestSettingsContext()
        settingsManager = settingsContext.makeSettingsManager()
        settingsManager.replace(WallpaperSettings())

        wallpaperProvider = MockWallpaperProvider()
        themeProvider = ThemeProvider(settingsManager: settingsManager)
        let wallpaperLibrary = WallpaperLibrary()
        rotationService = RotationService(
            settingsManager: settingsManager,
            wallpaperProvider: wallpaperProvider,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
        appState = AppState(
            settingsManager: settingsManager,
            rotationService: rotationService,
            themeProvider: themeProvider,
            wallpaperLibrary: wallpaperLibrary
        )
        viewModel = SettingsViewModel(appState: appState)
    }

    override func tearDownWithError() throws {
        viewModel = nil
        appState = nil
        rotationService = nil
        themeProvider = nil
        wallpaperProvider = nil
        settingsManager = nil
        settingsContext = nil
        try super.tearDownWithError()
    }

    func testAddFolderUpdatesPublishedPropertyAndAppState() {
        XCTAssertTrue(viewModel.folderPaths.isEmpty)
        viewModel.addFolder("/tmp")
        XCTAssertEqual(viewModel.folderPaths, ["/tmp"])
        XCTAssertEqual(appState.settings.folderPaths, ["/tmp"])
    }

    /// A relative path would be resolved against the working directory of
    /// the process, so the absolute path is stored and shown.
    func testARelativeFolderPathIsStoredAbsolute() {
        let expected = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Pictures")
            .standardizedFileURL
            .path

        viewModel.addFolder("Pictures")

        XCTAssertEqual(viewModel.folderPaths, [expected])
        XCTAssertEqual(appState.settings.folderPaths, [expected])
    }

    /// The same rule for a folder the user renames.
    func testARelativeFolderPathReplacesTheFolderWithAnAbsolutePath() {
        appState.updateSettings { $0.folderPaths = ["/old"] }
        let expected = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent("Pictures")
            .standardizedFileURL
            .path

        viewModel.replaceFolder(oldPath: "/old", with: "Pictures")

        XCTAssertEqual(appState.settings.folderPaths, [expected])
        XCTAssertEqual(viewModel.folderPaths, [expected])
    }

    func testAddThemeUpdatesPublishedPropertyAndAppState() {
        XCTAssertTrue(viewModel.themes.isEmpty)
        let theme = Theme(name: "Test Theme", folderPaths: ["/tmp"])
        viewModel.addTheme(theme)
        XCTAssertEqual(viewModel.themes.count, 1)
        XCTAssertEqual(viewModel.themes.first?.name, "Test Theme")
        XCTAssertEqual(appState.settings.themes.first?.name, "Test Theme")
    }

    func testToggleMatchSystemAppearance() {
        XCTAssertFalse(viewModel.matchSystemAppearance)
        viewModel.toggleMatchSystemAppearance()
        XCTAssertTrue(viewModel.matchSystemAppearance)
        XCTAssertTrue(appState.settings.matchSystemAppearance)
        viewModel.toggleMatchSystemAppearance()
        XCTAssertFalse(viewModel.matchSystemAppearance)
    }

    func testSettersWriteThroughToAppState() {
        // A theme action needs a theme: without one the stored action is
        // normalised into a wallpaper action.
        viewModel.addTheme(Theme(name: "Test Theme", folderPaths: ["/tmp"]))
        viewModel.setAllSpaces(true)
        viewModel.setMatchSystemAppearance(true)
        viewModel.setInterval(.hour1)
        viewModel.setRotationAction(.themeNext)

        XCTAssertTrue(appState.settings.allSpaces)
        XCTAssertTrue(appState.settings.matchSystemAppearance)
        XCTAssertEqual(appState.settings.intervalMinutes, .hour1)
        XCTAssertEqual(appState.settings.rotationAction, .themeNext)
    }

    /// A theme action without a theme would do nothing, so the picker must
    /// not offer it.
    func testTheThemeActionsAreOnlyOfferedWhileThereIsATheme() {
        XCTAssertFalse(viewModel.availableRotationActions.contains(where: { $0.isThemeAction }))

        viewModel.addTheme(Theme(name: "Theme", folderPaths: []))

        XCTAssertTrue(viewModel.availableRotationActions.contains(where: { $0.isThemeAction }))
        XCTAssertTrue(viewModel.availableRotationActions.contains(.shuffle))
    }

    func testAppearanceOverridesWriteThroughToAppState() {
        viewModel.addFolder("/tmp")
        viewModel.addTheme(Theme(id: "light-theme", name: "Light", folderPaths: []))
        viewModel.addTheme(Theme(id: "dark-theme", name: "Dark", folderPaths: []))
        viewModel.setAppearanceOverrides(
            lightThemeID: "light-theme",
            darkThemeID: "dark-theme",
            lightWallpaper: "/tmp/light.jpg",
            darkWallpaper: "/tmp/dark.jpg"
        )

        XCTAssertEqual(appState.settings.appearanceLightThemeID, "light-theme")
        XCTAssertEqual(appState.settings.appearanceDarkThemeID, "dark-theme")
        XCTAssertEqual(appState.settings.allFoldersLightWallpaper, "/tmp/light.jpg")
        XCTAssertEqual(appState.settings.allFoldersDarkWallpaper, "/tmp/dark.jpg")
    }

    func testUpdateShortcuts() {
        let shortcuts = Shortcuts(showMain: "cmd+1")
        viewModel.setShortcuts(shortcuts)
        XCTAssertEqual(viewModel.shortcuts.showMain, "cmd+1")
        XCTAssertEqual(appState.settings.shortcuts.showMain, "cmd+1")
    }

    func testAssigningShortcutClearsSameShortcutFromOtherActions() {
        viewModel.setShortcuts(Shortcuts(
            showMain: "cmd+1",
            showPreview: "cmd+2",
            showMenu: "cmd+3"
        ))

        viewModel.setShowPreviewShortcut("cmd+1")

        XCTAssertNil(appState.settings.shortcuts.showMain)
        XCTAssertEqual(appState.settings.shortcuts.showPreview, "cmd+1")
        XCTAssertEqual(appState.settings.shortcuts.showMenu, "cmd+3")
    }

    func testSetWallpaperFromAbsolutePathUsesFileURLAndEveryDisplay() {
        appState.setWallpaper("/tmp/wallpaper.jpg")

        XCTAssertEqual(wallpaperProvider.appliedURLs, [URL(fileURLWithPath: "/tmp/wallpaper.jpg")])
        XCTAssertEqual(appState.settings.currentWallpaper, "/tmp/wallpaper.jpg")
    }

    func testHistoryLimitKeepsMostRecentWallpapers() {
        appState.updateSettings { settings in
            settings.wallpaperHistory = ["newest", "second", "third", "fourth", "fifth", "oldest"]
        }

        viewModel.setHistoryLimit(5)

        XCTAssertEqual(appState.settings.wallpaperHistory, ["newest", "second", "third", "fourth", "fifth"])
    }

    /// The view model must only store the limits the settings file accepts.
    func testHistoryLimitOnlyAcceptsTheLimitsTheSettingsFileSupports() {
        viewModel.setHistoryLimit(15)
        XCTAssertEqual(appState.settings.historyLimit, 10)

        viewModel.setHistoryLimit(3)
        XCTAssertEqual(appState.settings.historyLimit, 5)

        viewModel.setHistoryLimit(20)
        XCTAssertEqual(appState.settings.historyLimit, 20)
    }

    func testEditFolderPreservesOrderAndUpdatesThemeReferences() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/first", "/old", "/last"]
            settings.themes = [
                Theme(id: "theme", name: "Theme", folderPaths: ["/old", "/last"])
            ]
        }

        viewModel.replaceFolder(oldPath: "/old", with: "/replacement")

        XCTAssertEqual(appState.settings.folderPaths, ["/first", "/replacement", "/last"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/replacement", "/last"])
    }

    /// Renaming a folder must not wipe the wallpaper pins of the themes.
    func testRenamingAFolderKeepsTheThemeWallpaperPins() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/old"]
            settings.themes = [
                Theme(
                    id: "theme",
                    name: "Theme",
                    folderPaths: ["/old"],
                    lightWallpaper: "/old/light.jpg",
                    darkWallpaper: "/old/nested/dark.jpg"
                )
            ]
        }

        viewModel.replaceFolder(oldPath: "/old", with: "/new")

        XCTAssertEqual(appState.settings.themes[0].lightWallpaper, "/new/light.jpg")
        XCTAssertEqual(appState.settings.themes[0].darkWallpaper, "/new/nested/dark.jpg")
    }

    /// A theme that is scoped to another folder keeps its pins: a pin must
    /// not leave the scope of its theme.
    func testRenamingAFolderKeepsThePinsOfAThemeThatIsScopedElsewhere() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/old", "/old/sub"]
            settings.themes = [
                Theme(
                    id: "theme",
                    name: "Theme",
                    folderPaths: ["/old/sub"],
                    lightWallpaper: "/old/sub/light.jpg",
                    darkWallpaper: "/old/sub/dark.jpg"
                )
            ]
        }

        viewModel.replaceFolder(oldPath: "/old", with: "/new")

        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/old/sub"])
        XCTAssertEqual(appState.settings.themes[0].lightWallpaper, "/old/sub/light.jpg")
        XCTAssertEqual(appState.settings.themes[0].darkWallpaper, "/old/sub/dark.jpg")
    }

    /// The pins of all folders, the current wallpaper and the history point
    /// at files in the renamed folder too.
    func testRenamingAFolderKeepsTheGlobalPinsTheCurrentWallpaperAndTheHistory() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/old"]
            settings.allFoldersLightWallpaper = "/old/light.jpg"
            settings.allFoldersDarkWallpaper = "/old/dark.jpg"
            settings.currentWallpaper = "/old/current.jpg"
            settings.wallpaperHistory = ["/old/history.jpg", "/elsewhere/other.jpg"]
        }

        viewModel.replaceFolder(oldPath: "/old", with: "/new")

        XCTAssertEqual(appState.settings.allFoldersLightWallpaper, "/new/light.jpg")
        XCTAssertEqual(appState.settings.allFoldersDarkWallpaper, "/new/dark.jpg")
        XCTAssertEqual(appState.settings.currentWallpaper, "/new/current.jpg")
        XCTAssertEqual(
            appState.settings.wallpaperHistory,
            ["/new/history.jpg", "/elsewhere/other.jpg"]
        )
    }

    func testEditFolderRejectsDuplicateDestination() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/first", "/second"]
            settings.themes = [Theme(id: "theme", name: "Theme", folderPaths: ["/first"])]
        }

        viewModel.replaceFolder(oldPath: "/first", with: "/second")

        XCTAssertEqual(appState.settings.folderPaths, ["/first", "/second"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/first"])
    }

    func testRemoveFolderAlsoRemovesThemeReferences() {
        appState.updateSettings { settings in
            settings.folderPaths = ["/remove", "/keep"]
            settings.themes = [
                Theme(id: "theme", name: "Theme", folderPaths: ["/remove", "/keep"])
            ]
        }

        viewModel.removeFolder("/remove")

        XCTAssertEqual(appState.settings.folderPaths, ["/keep"])
        XCTAssertEqual(appState.settings.themes[0].folderPaths, ["/keep"])
    }

    func testRemoveThemeClearsEveryThemeReference() {
        let theme = Theme(id: "remove", name: "Theme", folderPaths: [])
        appState.updateSettings { settings in
            settings.themes = [theme]
            settings.activeThemeID = theme.id
            settings.appearanceLightThemeID = theme.id
            settings.appearanceDarkThemeID = theme.id
        }

        viewModel.removeTheme(id: theme.id)

        XCTAssertTrue(appState.settings.themes.isEmpty)
        XCTAssertNil(appState.settings.activeThemeID)
        XCTAssertNil(appState.settings.appearanceLightThemeID)
        XCTAssertNil(appState.settings.appearanceDarkThemeID)
    }

    /// A theme action without a theme cannot run, and the picker would show
    /// no selection at all, so the stored action becomes a wallpaper action.
    func testRemovingTheLastThemeRewritesAThemeRotationAction() {
        let theme = Theme(id: "theme", name: "Theme", folderPaths: [])
        appState.updateSettings { $0.themes = [theme] }
        viewModel.setRotationAction(.themeNext)
        XCTAssertTrue(viewModel.availableRotationActions.contains(.themeNext))

        viewModel.removeTheme(id: theme.id)

        XCTAssertFalse(
            appState.settings.rotationAction.isThemeAction,
            "A theme action without a theme cannot be stored"
        )
        XCTAssertTrue(
            viewModel.availableRotationActions.contains(appState.settings.rotationAction),
            "The stored action has to be offered by the picker"
        )
        XCTAssertEqual(viewModel.rotationAction, .shuffle)
    }

    /// A theme that stays keeps the theme action: the picker still offers it.
    func testRemovingOneThemeKeepsAThemeRotationAction() {
        let theme = Theme(id: "theme", name: "Theme", folderPaths: [])
        let otherTheme = Theme(id: "other", name: "Other", folderPaths: [])
        appState.updateSettings { $0.themes = [theme, otherTheme] }
        viewModel.setRotationAction(.themeNext)

        viewModel.removeTheme(id: theme.id)

        XCTAssertEqual(appState.settings.rotationAction, .themeNext)
        XCTAssertTrue(viewModel.availableRotationActions.contains(.themeNext))
    }

    func testReplaceThemeCanExplicitlyClearAppearancePins() {
        let theme = Theme(
            id: "theme",
            name: "Before",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { $0.themes = [theme] }

        viewModel.replaceTheme(
            id: theme.id,
            with: Theme(id: "ignored", name: "After", folderPaths: ["/wallpapers"])
        )

        XCTAssertEqual(appState.settings.themes[0].id, theme.id)
        XCTAssertEqual(appState.settings.themes[0].name, "After")
        XCTAssertNil(appState.settings.themes[0].lightWallpaper)
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }

    func testAppearanceWallpaperSetterClearsPinsForSpecificTheme() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { $0.themes = [theme] }

        viewModel.setAppearanceWallpapers(light: nil, dark: nil, forThemeID: theme.id)

        XCTAssertNil(appState.settings.themes[0].lightWallpaper)
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }

    func testAppearanceConfigurationUpdatesMappingAndClearsPinsAtomically() {
        let theme = Theme(
            id: "theme",
            name: "Theme",
            folderPaths: ["/wallpapers"],
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )
        appState.updateSettings { settings in
            settings.folderPaths = ["/wallpapers"]
            settings.themes = [theme]
            settings.appearanceLightThemeID = theme.id
            settings.appearanceDarkThemeID = theme.id
        }

        viewModel.setAppearanceConfiguration(
            lightThemeID: nil,
            darkThemeID: theme.id,
            lightWallpaper: nil,
            darkWallpaper: nil
        )

        XCTAssertNil(appState.settings.appearanceLightThemeID)
        XCTAssertEqual(appState.settings.appearanceDarkThemeID, theme.id)
        // Without a light appearance theme the light pin belongs to all
        // folders, so the pin of the theme is not touched by it.
        XCTAssertNil(appState.settings.allFoldersLightWallpaper)
        XCTAssertEqual(appState.settings.themes[0].lightWallpaper, "/wallpapers/light.jpg")
        XCTAssertNil(appState.settings.themes[0].darkWallpaper)
    }

    /// The pin the sheet writes has to be the pin the app reads: the light
    /// pin belongs to the light appearance theme and the dark pin to the dark
    /// appearance theme.
    func testTheAppearancePinIsStoredWhereTheAppReadsIt() {
        viewModel.addFolder("/wallpapers")
        viewModel.addTheme(Theme(id: "light", name: "Light", folderPaths: ["/wallpapers"]))
        viewModel.addTheme(Theme(id: "dark", name: "Dark", folderPaths: ["/wallpapers"]))
        appState.updateSettings { $0.matchSystemAppearance = true }

        viewModel.setAppearanceConfiguration(
            lightThemeID: "light",
            darkThemeID: "dark",
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )

        let pins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: false)
        XCTAssertEqual(pins.light, "/wallpapers/light.jpg")
        let darkPins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: true)
        XCTAssertEqual(darkPins.dark, "/wallpapers/dark.jpg")
    }

    /// Without an appearance theme the pin belongs to all folders, and that
    /// is where the app reads it.
    func testTheAppearancePinIsStoredInTheGlobalPinsWithoutAnAppearanceTheme() {
        viewModel.addFolder("/wallpapers")
        appState.updateSettings { $0.matchSystemAppearance = true }

        viewModel.setAppearanceConfiguration(
            lightThemeID: nil,
            darkThemeID: nil,
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )

        let pins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: false)
        XCTAssertEqual(pins.light, "/wallpapers/light.jpg")
        let darkPins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: true)
        XCTAssertEqual(darkPins.dark, "/wallpapers/dark.jpg")
    }

    /// While the appearance is not matched the app reads the pins of the
    /// active theme, so the pin has to be visible there too.
    func testTheAppearancePinIsVisibleWhileTheAppearanceIsNotMatched() {
        viewModel.addFolder("/wallpapers")
        viewModel.addTheme(Theme(id: "theme", name: "Theme", folderPaths: ["/wallpapers"]))
        appState.updateSettings { $0.activeThemeID = "theme" }

        viewModel.setAppearanceConfiguration(
            lightThemeID: "theme",
            darkThemeID: "theme",
            lightWallpaper: "/wallpapers/light.jpg",
            darkWallpaper: "/wallpapers/dark.jpg"
        )

        let pins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: false)
        XCTAssertEqual(pins.light, "/wallpapers/light.jpg")
        let darkPins = themeProvider.effectiveAppearanceWallpapers(isDarkAppearance: true)
        XCTAssertEqual(darkPins.dark, "/wallpapers/dark.jpg")
    }

    /// The rotation cannot run while the appearance is matched, so the
    /// interval and the action of the rotation would do nothing. The flag
    /// states the effect, so a view binds it without negating it.
    func testTheRotationControlsAreDisabledWhileTheAppearanceIsMatched() {
        XCTAssertFalse(viewModel.isRotationControlDisabled)

        viewModel.setMatchSystemAppearance(true)

        XCTAssertTrue(viewModel.isRotationControlDisabled)
    }

    /// The pin of all folders is only read while no theme is set for the
    /// light appearance: a theme owns the pin of its appearance, so the app
    /// reads the pin of that theme instead. The picker must be disabled
    /// then, so a value cannot be picked that the app ignores.
    func testTheGlobalLightPinIsDisabledWhileAThemeIsSetForTheLightAppearance() {
        XCTAssertFalse(viewModel.isGlobalLightPinDisabled)
        XCTAssertFalse(viewModel.isGlobalDarkPinDisabled)

        viewModel.addTheme(Theme(id: "light", name: "Light", folderPaths: []))
        viewModel.setAppearanceThemeIDs(light: "light", dark: nil)

        XCTAssertTrue(viewModel.isGlobalLightPinDisabled)
        XCTAssertFalse(viewModel.isGlobalDarkPinDisabled)
    }

    /// The same rule for the dark appearance.
    func testTheGlobalDarkPinIsDisabledWhileAThemeIsSetForTheDarkAppearance() {
        XCTAssertFalse(viewModel.isGlobalDarkPinDisabled)
        XCTAssertFalse(viewModel.isGlobalLightPinDisabled)

        viewModel.addTheme(Theme(id: "dark", name: "Dark", folderPaths: []))
        viewModel.setAppearanceThemeIDs(light: nil, dark: "dark")

        XCTAssertTrue(viewModel.isGlobalDarkPinDisabled)
        XCTAssertFalse(viewModel.isGlobalLightPinDisabled)
    }

    /// The theme images are loaded by a separate task, so they arrive after the
    /// settings change that requested them.
    func testCurrentThemeImagesFollowTheAppState() async throws {
        let folder = settingsContext.directory(named: "images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appendingPathComponent("wallpaper.png")
        try Data().write(to: image)

        appState.updateSettings { $0.folderPaths = [folder.path] }

        let deadline = Date().addingTimeInterval(10)
        while viewModel.currentThemeImages.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(viewModel.currentThemeImages, [image])
    }

    /// The README promises the wallpaper failures in the Settings window too.
    func testTheWallpaperErrorIsShownInTheSettingsWindow() {
        wallpaperProvider.errorToThrow = MockWallpaperProviderError.configuredFailure

        appState.setWallpaper("/tmp/failed-wallpaper.jpg")

        XCTAssertNotNil(appState.lastWallpaperError)
        XCTAssertEqual(viewModel.wallpaperErrorMessage, appState.lastWallpaperError)
    }

    /// The theme source has to reach the application, otherwise the radio
    /// group does nothing.
    func testSetThemeSourceSetsTheAppearanceOfTheApplication() {
        let previousAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previousAppearance }

        // The picker writes the value before the change is reported.
        viewModel.themeSource = .light
        viewModel.setThemeSource(.light)

        XCTAssertEqual(
            NSApplication.shared.appearance?.name.rawValue,
            NSAppearance.Name.aqua.rawValue
        )
    }

    /// The dark theme source has to reach the application too.
    func testSetThemeSourceSetsTheDarkAppearanceOfTheApplication() {
        let previousAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previousAppearance }

        // The picker writes the value before the change is reported.
        viewModel.themeSource = .dark
        viewModel.setThemeSource(.dark)

        XCTAssertEqual(
            NSApplication.shared.appearance?.name.rawValue,
            NSAppearance.Name.darkAqua.rawValue
        )
    }

    /// The theme source is read back from the application, so the radio group
    /// has to show the source that the user picked.
    func testTheThemeSourceIsReadBackFromTheApplication() {
        let previousAppearance = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previousAppearance }

        // The picker writes the value before the change is reported.
        viewModel.themeSource = .light
        viewModel.setThemeSource(.light)
        // A settings change reads the state of the application again.
        appState.updateSettings { $0.allSpaces = true }

        XCTAssertEqual(viewModel.themeSource, .light)
    }

    /// A pin whose file is missing has to stay in the picker: the pin is set,
    /// so the user has to see it and be able to clear it.
    func testTheAllFolderPinPickersKeepAPinWhoseFileIsMissing() async throws {
        let folder = settingsContext.directory(named: "pin-images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appendingPathComponent("wallpaper.png")
        try Data().write(to: image)
        let missing = folder.appendingPathComponent("missing.png")

        appState.updateSettings { $0.folderPaths = [folder.path] }

        let deadline = Date().addingTimeInterval(10)
        while viewModel.allFolderImages.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        appState.updateSettings { $0.allFoldersLightWallpaper = missing.path }

        XCTAssertEqual(viewModel.allFolderImages, [image])
        XCTAssertTrue(
            viewModel.allFoldersLightWallpaperImages.contains { $0.path == missing.path },
            "The missing pin has to stay in the picker"
        )
        XCTAssertEqual(viewModel.allFoldersLightWallpaperImages.count, 2)
    }

    /// The pin of the Appearance dialog is stored in the appearance theme, so
    /// the menu may only offer the images of that theme. The theme the
    /// appearance picks is the theme the pin is stored in.
    func testTheAppearancePinOffersOnlyTheImagesOfTheAppearanceTheme() async throws {
        let lightFolder = settingsContext.directory(named: "light-images")
        let darkFolder = settingsContext.directory(named: "dark-images")
        for folder in [lightFolder, darkFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let lightImage = lightFolder.appendingPathComponent("light.png")
        let darkImage = darkFolder.appendingPathComponent("dark.png")
        try Data().write(to: lightImage)
        try Data().write(to: darkImage)

        appState.updateSettings { settings in
            settings.folderPaths = [lightFolder.path, darkFolder.path]
            settings.themes = [
                Theme(id: "light", name: "Light", folderPaths: [lightFolder.path]),
                Theme(id: "dark", name: "Dark", folderPaths: [darkFolder.path])
            ]
            settings.activeThemeID = "light"
            // While the appearance is matched, the system picks the theme, and
            // the pin is stored in that theme.
            settings.matchSystemAppearance = true
            settings.appearanceLightThemeID = "light"
            settings.appearanceDarkThemeID = "dark"
        }

        let deadline = Date().addingTimeInterval(10)
        while viewModel.allFolderImages.count < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(viewModel.appearancePinImages(forThemeID: "light"), [lightImage])
        XCTAssertEqual(viewModel.appearancePinImages(forThemeID: "dark"), [darkImage])
        // Without an appearance theme the pin belongs to all folders.
        XCTAssertEqual(viewModel.appearancePinImages(forThemeID: nil).count, 2)
    }
}
