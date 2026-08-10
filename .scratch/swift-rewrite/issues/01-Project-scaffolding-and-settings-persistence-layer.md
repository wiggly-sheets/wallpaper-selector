# 01 — Project scaffolding and settings persistence layer

**What to build:** Create the Swift package, define the `WallpaperSettings` model, and implement a `SettingsManager` that reads/writes JSON to the default Application Support folder, watches for external changes, and provides a default‑value fallback.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Project compiles with `swift build` and generates an executable target.
- [ ] `WallpaperSettings` struct encodes/decodes to/from JSON matching the existing schema.
- [ ] `SettingsManager` loads existing file or creates a default one on first launch.
- [ ] File‑watcher notifies observers when the settings file changes on disk.
- [ ] Unit tests for encoding/decoding, default values, and file‑watcher behavior.
