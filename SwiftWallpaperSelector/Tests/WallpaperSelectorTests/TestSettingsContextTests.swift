import XCTest
@testable import WallpaperSelector

@MainActor
final class TestSettingsContextTests: XCTestCase {

    /// The temp tree has to be removed every time: a settings folder that is
    /// left read-only must not strand the tree under the temp directory.
    func testTheTempTreeIsRemovedWhenTheSettingsFolderIsReadOnly() throws {
        var context: TestSettingsContext? = try TestSettingsContext()
        let root = context!.rootDirectory
        try Data().write(to: context!.settingsDirectory.appendingPathComponent("settings.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: context!.settingsDirectory.path
        )

        // The context is released here, so its deinit removed the tree.
        context = nil

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path),
            "The temp tree must be removed even when the settings folder is read-only"
        )
    }
}
