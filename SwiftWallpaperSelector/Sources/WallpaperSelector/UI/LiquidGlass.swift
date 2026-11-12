import SwiftUI

// Liquid Glass is the system design of macOS 26 and newer. The app builds
// against the newest SDK, so the standard windows, menus and controls adopt
// it on their own. These helpers cover the surfaces the app draws itself:
// the popover window uses `NSGlassEffectView` (see
// `TrayPopoverWindowController`), and the badges and bars below use the
// matching SwiftUI glass effect. Older systems keep the existing look.

extension View {
    /// Draws a badge with the native Liquid Glass material on macOS 26 and
    /// newer, and with the previous white circle before it.
    @ViewBuilder
    func glassBadgeBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Circle())
        } else {
            background(Circle().fill(Color.white))
        }
    }

    /// Draws a bar with the native Liquid Glass material on macOS 26 and
    /// newer, and with the window background before it.
    @ViewBuilder
    func glassBarBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Rectangle())
        } else {
            background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
