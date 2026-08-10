import AppKit

/// Keeps Wallpaper Selector out of Dock and app switcher. This is runtime
/// equivalent of Electron's `skipTaskbar` / menu-bar-only lifecycle and still
/// lets windows become key when opened from menu bar or shortcut.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .OpenMainWindowRequested, object: nil)
        }
        return true
    }
}
