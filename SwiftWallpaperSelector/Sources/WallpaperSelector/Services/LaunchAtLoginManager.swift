import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    /// The state of the main app in the login items of the system.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// The login item is on. A registration that waits for the approval of
    /// the user already appears in the login items, so it counts as on.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// The user has to approve the login item in System Settings.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                // Registering an item that is already registered throws, and
                // an item that waits for approval must not be registered
                // again. Both already count as on.
                guard status != .enabled, status != .requiresApproval else {
                    return .success(())
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Opens the login items of the system, so the user can approve the app.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
