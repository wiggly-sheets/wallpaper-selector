# 03 — Rotation service and timer

**What to build:** Create a `RotationService` that owns a `DispatchSourceTimer` (or `Timer` + `RunLoop`). On each tick, it reads the current `WallpaperSettings`, determines the effective folder list (respecting the active theme), selects the next image based on `rotationAction` (shuffle/next/previous/themeShuffle/etc.), avoids immediate repeats when possible, updates `currentWallpaper` in settings, and delegates to `WallpaperProvider`. The timer pauses when `matchSystemAppearance` is true.

**Blocked by:** 01 (settings), 02 (wallpaper setting).

**Status:** ready-for-agent

- [ ] Timer starts/stops according to `intervalMinutes` and `matchSystemAppearance` flag.
- [ ] Selection logic honors `rotationAction` and respects history to avoid immediate repeats when possible.
- [ ] After setting a new wallpaper, `SettingsManager` is updated and `WallpaperProvider.setWallpaper` is called.
- [ ] Unit tests use a mock `WallpaperProvider` and a testable timer to verify correct sequencing.
- [ ] Integration test (manual) confirms the wallpaper changes at the specified interval.
