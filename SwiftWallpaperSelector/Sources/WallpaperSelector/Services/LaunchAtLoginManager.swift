import Foundation
import ServiceManagement

final class LaunchAtLoginManager {

    var isEnabled: Bool {
        get {
            if #available(macOS 13, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
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


    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }
}
