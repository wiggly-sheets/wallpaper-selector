import AppKit
import ApplicationServices

/// Controls macOS's separate “Show on all Spaces” preference. NSWorkspace
/// applies a wallpaper to displays but cannot change this virtual-space option.
final class AllSpacesService {
    private let wallpaperSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!
    private var lastAppliedValue: Bool?
    private let stateLock = NSLock()

    func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        let needsApply = lastAppliedValue != enabled
        stateLock.unlock()
        guard needsApply else { return }

        NSWorkspace.shared.open(wallpaperSettingsURL)
        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.setCheckboxAndClose(enabled) {
                self.stateLock.lock()
                self.lastAppliedValue = enabled
                self.stateLock.unlock()
            } else {
                print("[AllSpacesService] Could not find Show on all Spaces; Wallpaper Settings remains open for manual completion.")
            }
        }
    }

    @discardableResult
    private func setCheckboxAndClose(_ enabled: Bool) -> Bool {
        let desiredValue = enabled ? 1 : 0
        let script = """
        tell application "System Settings" to activate

        repeat 40 times
            if application "System Settings" is frontmost then exit repeat
            delay 0.25
        end repeat

        tell application "System Events"
            tell process "System Settings"
                set foundMenuItem to false
                repeat 40 times
                    try
                        if exists (menu item "Wallpaper" of menu "View" of menu bar 1) then
                            set foundMenuItem to true
                            exit repeat
                        end if
                    end try
                    delay 0.25
                end repeat
                if not foundMenuItem then error "Timed out waiting for View > Wallpaper menu item"
                click menu item "Wallpaper" of menu "View" of menu bar 1

                set targetCheckbox to missing value
                repeat 40 times
                    try
                        set targetCheckbox to checkbox "Show on all Spaces" of group 2 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                    end try
                    if targetCheckbox is not missing value then exit repeat
                    delay 0.25
                end repeat
                if targetCheckbox is missing value then error "Timed out waiting for Show on all Spaces checkbox"
                if (value of targetCheckbox as integer) is not \(desiredValue) then click targetCheckbox
            end tell
        end tell

        delay 0.2
        tell application "System Settings" to quit
        return true
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { print("[AllSpacesService] UI scripting failed: \(error)") }
        return result?.booleanValue ?? false
    }
}
