# 02 — Wallpaper service implementation

**What to build:** Implement a `WallpaperProvider` that sets the desktop picture using `NSWorkspace.shared.setDesktopImageURL(_:for:options:)`. Provide a method to set the wallpaper on all screens (to simulate “All Spaces”) without invoking System Settings UI scripting.

**Blocked by:** 01 (needs access to settings for currentWallpaper, but can work standalone).

**Status:** ready-for-agent

- [ ] `setWallpaper(_ url: URL, onAllScreens: Bool)` iterates over `NSScreen.screens` and calls `NSWorkspace` for each screen.
- [ ] Success/failure is logged; errors are surfaced via a Result type or thrown.
- [ ] Unit test mocks `NSWorkspace` (or uses dependency injection) to verify the correct URLs are passed for each screen.
- [ ] The service does not depend on any necessary information that file exists and is an image – that validation can be done elsewhere.
