import SwiftUI

@main
struct WallpaperSelectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // AppKit owns lazily-created picker/settings windows. Keeping this
        // scene empty prevents SwiftUI from showing a picker on every launch.
        Settings { EmptyView() }
    }
}
