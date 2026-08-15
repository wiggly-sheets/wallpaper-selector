import SwiftUI

@main
struct WallpaperSelectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        Settings { EmptyView() }
    }
}
