# 04 — Native parity hardening and live validation

**What changed:** Close behavior gaps found by comparing the Electron sources with the Swift rewrite.

**Blocked by:** None.

**Status:** ready-for-human

- [x] Persist Electron-compatible JSON keys and migrate legacy single-folder settings.
- [x] Add custom settings-folder relocation and default-location restore.
- [x] Restore global hot-key callback dispatch and Electron accelerator parsing.
- [x] Keep picker, menu, and popover synchronized from one settings publisher.
- [x] Fix appearance theme switching, pin resolution, wallpaper-history updates, and file URL handling.
- [x] Fix native folder/theme controls and popover hosting/open-window behavior.
- [x] Set accessory activation policy for menu-bar-only runtime behavior.
- [x] `swift test` passes: 33 tests.
- [ ] Manual: validate menu-bar popover, hotkeys, folder panel, settings relocation, wallpaper apply, and All Spaces in installed app. Computer Use could not run in this environment because its runtime requested an unavailable elicitation API.

## Comments

- 2026-08-08: App launch verified process remains running from `swift run WallpaperSelector` (PID observed during validation). No interactive macOS permission or rendered UI check was possible in this session.
