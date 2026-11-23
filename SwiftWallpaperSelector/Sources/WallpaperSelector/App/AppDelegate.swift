import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // A menu-bar app has no window to reopen. Without this, macOS would
        // open the Settings scene first; the main window is the place where
        // the user starts.
        NotificationCenter.default.post(name: .OpenMainWindowRequested, object: nil)
        return true
    }
}
