# Changelog

All notable changes to Wallpaper Selector are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-11-23

### Added

- The menu bar icon now opens a preview popover with wallpaper thumbnails,
  theme and shuffle controls, rotation and All Spaces settings, and buttons for
  Settings and the main window. The popover can show every wallpaper in the
  folder or only the recent wallpapers, and selecting a wallpaper applies it.
  A right click still opens the full menu.

- A new General setting shows or hides the menu bar icon.

### Changed

- The release ships one disk image per architecture:
  `WallpaperSelector-<version>-arm64.dmg` for Apple silicon and
  `WallpaperSelector-<version>-x86_64.dmg` for Intel. The single
  `WallpaperSelector-<version>.dmg` and its `.dmg.sha256` sidecar are gone.
  Both disk images are listed in `checksums.txt`.

## [1.1.0] - 2026-11-23

### Added

- On macOS 26 and newer the app uses the native Liquid Glass design. The
  preview popover is an `NSGlassEffectView` surface, interactive on macOS 27
  and newer, and the custom toolbar and selection badges use the SwiftUI glass
  effect. The executable records the macOS 27.2 SDK, so macOS enables Liquid
  Glass for the standard windows, menus and controls instead of their legacy
  appearance. macOS 13 through 15 keep the previous material and colors.

- The Settings window offers visible delete buttons for a folder and a theme.

- A Space can keep its own wallpaper. The Spaces pane lists every desktop of
  every display; a Space without a pin follows the current wallpaper, and a
  new Space gets the current wallpaper when it appears. The picker shows a
  preview and the name of every wallpaper. Pinning a Space writes the wallpaper
  for every Space at once, so the user does not wait for the next rotation.

### Changed

- All Spaces now puts the wallpaper on every Space by writing the wallpaper
  store of macOS. The app no longer opens System Settings or needs the
  Accessibility permission. Turning the setting on applies the wallpaper that
  is on the screen, and a failure is reported in the menu bar and on the
  Settings pane.

- The appearance pin is applied when the system appearance changes, when the
  pin, the theme or the matching setting changes and at launch. A wallpaper
  that the user picked by hand is no longer replaced when the app becomes
  active.

- The rotation follows the theme of the current appearance and revalidates the
  folder scope after a slow folder scan. Choosing the active theme again is a
  no-op.

- The app declares macOS 13 as its minimum system version.

- The release notes now come from the section of this CHANGELOG for the released
  version. A stable version without a section fails the release.

- The build interface gained `make run`, `make install`, `make verify`
  (architecture, recorded SDK, bundle version and signature) and the changelog
  check in `make test`. `make release` now moves `[Unreleased]` to the
  released version, runs the tests, builds and verifies the artifacts, commits
  the changelog bump and creates the tag.

### Fixed

- A broken or partly unreadable settings file no longer resets the
  configuration: each field is decoded on its own, an unreadable file is kept
  next to the new one, and a relative folder is stored as an absolute path.

- Settings are written off the main thread, so a wallpaper change no longer
  stalls the interface. A failed write is reported on the General pane and in
  the menu bar, and an external edit or a queued change is no longer lost.

- Changing the settings folder renames the old file to
  `settings.json.migrated`, so the older copy can never be adopted silently.
  An imported legacy file is renamed the same way, and a legacy file that was
  not imported is reported on every launch.

- The preview popover opens below the status item icon, takes the height of its
  content, stays on a short display and above full-screen apps, and closes when
  the user clicks another app.

- The status item menu is updated in place, so an open menu shows the current
  state and a click runs the current action. The menu also opens from its
  global shortcut.

- The thumbnail cache is bounded and dropped when the picker closes, stale
  decodes are cancelled, and a corrupt image is not retried on every scroll.

- A folder that is named like an image is skipped, and a file that two folders
  share is listed once.

- A wallpaper that reached only some displays reports that, instead of failing
  with a plain error.

- Failures of the wallpaper, the shortcuts, the rotation and All Spaces are
  shown in the menu bar, the Settings window and the popover, and the controls
  that cannot work are greyed out while Match System Appearance is on.

- The recent wallpaper list is no longer cut off at ten entries, and an entry
  whose file is gone is disabled instead of failing when it is clicked.

- The launch-at-login toggle keeps its state and message when macOS asks for
  approval, and the controls and grid cells have labels for VoiceOver.

## [1.0.0] - 2026-08-10

### Added

- The first release of Wallpaper Selector: a native macOS menu-bar app for
  picking, rotating and organizing local wallpapers. The release publishes the
  disk image `WallpaperSelector-1.0.0.dmg` and the checksum file
  `WallpaperSelector-1.0.0.dmg.sha256` next to it.
