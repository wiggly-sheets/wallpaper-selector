import Foundation
import ServiceManagement

/// Manages launch-at-login using `SMAppService` (macOS 13+) with a fallback
/// to `SMLoginItemSetEnabled` for older macOS versions.
final class LaunchAtLoginManager {
    // MARK: - Public

    /// Whether the app is currently set to launch at login.
    var isEnabled: Bool {
        get {
            if #available(macOS 13, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback: we can't easily query SMLoginItemSetEnabled state,
                // so return false and let the setter handle it.
                return false
            }
        }
        set {
            if #available(macOS 13, *) {
                if newValue {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            } else {
                SMLoginItemSetEnabled(
                    Bundle.main.bundleIdentifier! as CFString,
                    newValue
                )
            }
        }
    }

    // MARK: - Public API

    /// Enable or disable launch-at-login.
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
}