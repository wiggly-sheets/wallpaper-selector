## Problem Statement

The user wants to replace the existing Electron/Node.js (Glaze-based) wallpaper selector with a fully native macOS Swift/SwiftUI application to significantly reduce memory, CPU, and GPU usage, eliminate the Electron/Node overhead, and provide a truly macOS‑native experience while retaining all existing feature set (menu‑bar only, wallpaper folders, themes, timed rotation, appearance‑matching, per‑appearance wallpaper pinning, recent wallpapers, launch‑at‑login, global shortcuts, and the ability to set wallpaper on all spaces).

## Solution

Create a new Xcode/Swift Package Manager project that contains a single macOS app target configured as an accessory (menu‑bar‑only) application. The app will:

- Store user settings as JSON in `~/Library/Application Support/<bundle-id>/settings.json` (with an option to relocate the file to a custom folder for power users).
- Use `NSWorkspace.shared.setDesktopImageURL(_:for:options:)` to set the wallpaper, iterating over `NSScreen.screens` to cover all spaces without invoking System Settings UI scripting.
- Manage a rotation timer with `DispatchSourceTimer` (or `Timer` + `RunLoop`) that dispatches async work to avoid blocking the timer thread.
- Provide a dynamic menu bar extra built from SwiftUI/AppKit that reflects folders, themes, rotation controls, “All Spaces” toggle, “Match Appearance” switch, and Settings.
- Offer a Settings window (SwiftUI or AppKit) where users can adjust launch‑at‑login, global shortcuts, recent‑wallpapers count, and choose a custom settings folder.
- Persist global hot‑keys via a lightweight carbon‑based helper (or a chosen Swift hot‑key library) and register/unregister them when the `shortcuts` setting changes.
- Preserve the existing JSON settings schema to allow seamless migration from the Electron version on first launch.
- Be built and run via `swift run` or Xcode, with a `Package.swift` declaring the executable target and any Swift‑only dependencies.

## User Stories

1. As a user, I want the app to appear only in the menu bar (no Dock icon) so that it stays out of my way while providing quick access to wallpaper controls.
2. As a user, I want my existing settings (folders, current wallpaper, rotation interval, themes, etc.) to be automatically migrated from the Electron version so I don’t have to reconfigure the app after upgrading.
3. As a user, I want to add or remove folders of wallpaper images (PNG/JPEG/WebP) so I can control which pictures the app can choose from.
4. As a user, I want to create, rename, delete, and assign folders to themes so I can switch between different wallpaper collections with a single click.
5. As a user, I want the menu bar to show the active theme (or “All Folders”) so I know which set of images is currently in use.
6. As a user, I want to manually shuffle, go to the next, or go to the previous wallpaper from the menu bar so I can quickly change the background when desired.
7. As a user, I want to configure a timed rotation interval (off, 30 min, 1 hour, 12 hours, daily) and choose what action occurs each tick (shuffle, next, previous, theme shuffle, next theme, previous theme) so my desktop changes automatically according to my preference.
8. As a user, I want the rotation to pause when “Match System Appearance” is enabled so that the automatic light/dark wallpaper switching does not conflict with the timer.
9. As a user, I want the app to automatically switch between my pre‑selected light and dark wallpapers (or themes) when the system appearance changes, so my desktop always matches the current mode without manual intervention.
10. As a user, I want to pin a specific light and/or dark wallpaper to the active scope (theme or “All Folders”) so that a particular image is always used for that appearance, while still allowing a fallback to a random pick from the scope when no pinned image is set.
11. As a user, I want to see a list of recently applied wallpapers in the menu bar so I can quickly re‑apply a favorite without searching through folders.
12. As a user, I want to control how many recent wallpapers are remembered (5, 10, or 20) so I can balance history length with menu clutter.
13. As a user, I want to enable the “Apply to All Spaces” option so that my wallpaper appears on every desktop/spaces, and I want this to be done efficiently via direct `NSWorkspace` calls per screen rather than scripting System Settings.
14. As a user, I want to launch the app automatically at login so my wallpaper preferences are always active after I sign in.
15. As a user, I want to assign global keyboard shortcuts (Show Main Window, Show Preview, Open Menu Bar Menu) so I can access the app’s features without using the mouse.
16. As a power user, I want to relocate the settings file to a custom directory (e.g., a dotfiles repo) so I can version‑control and synchronize my preferences across machines.
17. As a developer, I want the core logic (settings persistence, wallpaper selection, rotation algorithm, theme resolution) to be covered by unit tests so I can refactor with confidence.
18. As a developer, I want the app to be buildable with Xcode and Swift Package Manager, depending only on Swift‑compatible libraries (if any), so the build process is simple and reproducible.

## Additional Notes

- The app will target macOS 13+ (or the minimum version the team decides) and use only public APIs; no reliance on `osascript` or AppleScript.
- The `wallpaper-img://` custom protocol used by the Electron version is unnecessary because SwiftUI/AppKit can load local file URLs directly.
- All asynchronous work (e.g., reading image directories) will be performed off the main timer thread to keep the UI responsive.
- The settings file will be watched for external changes (using a `DispatchSourceFileSystemObject`) so that manual edits are reflected immediately.
- Upon first launch, if a settings file is detected in the legacy Electron location, it will be copied to the new location (Application Support) and a migration notice logged.

</file>