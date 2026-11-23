import Foundation

/// A desktop of Mission Control, as macOS reports it.
struct DesktopSpace: Identifiable, Equatable, Sendable {
    /// The UUID of the Space. It is the key of the wallpaper store.
    let id: String
    /// The display the Space belongs to: `Main` or the UUID of a display.
    let displayID: String
    /// The position of the Space on its display, counted from 1.
    let index: Int
    /// Whether the Space is the one the user sees now.
    let isCurrent: Bool

    /// The display as the settings list shows it.
    var displayName: String {
        displayID == "Main" ? "Main Display" : "Display \(displayID.prefix(4))"
    }
}

/// The Spaces of the Mac and their order.
///
/// macOS does not publish the list of Spaces. The Dock keeps it in the
/// preference domain `com.apple.spaces`, in the order Mission Control shows.
/// The preference is read, never written.
enum SpaceInventory {
    /// The Spaces of the current session, in the order of their displays.
    static func spaces() -> [DesktopSpace] {
        guard let configuration = CFPreferencesCopyAppValue(
            "SpacesDisplayConfiguration" as CFString,
            "com.apple.spaces" as CFString
        ) as? [String: Any] else { return [] }
        return spaces(from: configuration)
    }

    /// The Spaces of a preference value. A test passes the value.
    static func spaces(from configuration: [String: Any]) -> [DesktopSpace] {
        guard let management = configuration["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]]
        else { return [] }

        var result: [DesktopSpace] = []
        for monitor in monitors {
            guard let displayID = monitor["Display Identifier"] as? String,
                  let spaces = monitor["Spaces"] as? [[String: Any]]
            else { continue }
            let current = (monitor["Current Space"] as? [String: Any])?["uuid"] as? String
            var desktopIndex = 0
            for space in spaces {
                guard let id = space["uuid"] as? String else { continue }
                // A full-screen app is a Space of its own, but the user does
                // not keep a wallpaper for it.
                if let type = space["type"] as? Int, type != 0 { continue }
                desktopIndex += 1
                result.append(
                    DesktopSpace(
                        id: id.uppercased(),
                        displayID: displayID,
                        index: desktopIndex,
                        isCurrent: id.caseInsensitiveCompare(current ?? "") == .orderedSame
                    )
                )
            }
        }
        return result
    }
}
