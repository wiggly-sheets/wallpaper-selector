# 03 — Rotation service and timer

**What to build:** Create a `RotationService` that owns a `DispatchSourceTimer` (or `Timer` + `RunLoop`). On each tick, it reads the current `WallpaperSettings`, determines the effective folder list (respecting the active theme), selects the next image based on `rotationAction` (shuffle/next/previous/themeShuffle/etc.), avoids immediate repeats when possible, updates `currentWallpaper` in settings, and delegates to `WallpaperProvider`. The timer pauses when `matchSystemAppearance` is true.

**Blocked by:** None — 01 and 02 are done.

**Status:** ready-for-human

- [x] Timer starts/stops according to `intervalMinutes` and `matchSystemAppearance` flag.
- [x] Selection logic honors `rotationAction` and respects history to avoid immediate repeats when possible.
- [x] After setting a new wallpaper, `SettingsManager` is updated and `WallpaperProvider.setWallpaper` is called.
- [x] Unit tests use a mock `WallpaperProvider` and a testable timer to verify correct sequencing.
- [ ] Integration test (manual) confirms the wallpaper changes at the specified interval.

## Comments

- 2026-10-20: The service is built and tested. `RotationService` owns a `Timer` on the run loop, the tick is the seam the tests drive, and the mock provider shows the order of the calls. The last criterion needs a human: no test can show the wallpaper changing at the interval, so the ticket waits for that check.
