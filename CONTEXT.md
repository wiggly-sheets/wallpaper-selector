# Wallpaper Selector

A menu-bar-only macOS application that aggregates images from local folders and allows users to visually select and rotate desktop wallpapers.

## Language

**Wallpaper**:
An image file (PNG, JPEG, or WebP) that can be set as the desktop picture.
_Avoid_: picture, image, photo

**Folder**:
A directory on the local filesystem containing wallpaper images.
_Avoid_: directory, directory path

**Theme**:
A named subset of configured folders, used to switch between different wallpaper collections.
_Avoid_: collection, album, preset

**Wallpaper Pin**:
An exact wallpaper that the app uses for one appearance instead of picking a random image from the folders.
_Avoid_: lock, bookmark, favorite

**Scope**:
The folders a wallpaper pin belongs to: the folders of its theme, or every configured folder when that theme has none.
_Avoid_: collection, set, group

**All Spaces**:
A macOS setting that makes the desktop picture appear on all spaces/virtual desktops.
_Avoid_: everywhere, all desktops, global wallpaper

**Rotation**:
The automatic cycling of wallpapers at a set interval.
_Avoid_: slideshow, timer, automation

**Appearance Matching**:
The feature that automatically switches between light and dark wallpapers based on the system appearance.
_Avoid_: dark mode switching, light/dark switching

**Recent Wallpapers**:
A history of recently applied wallpapers for quick re-selection.
_Avoid_: history, previous wallpapers, recents

## Rules

The rules below are intentional product decisions. They look like defects to a reader who does not know why they exist, so they are written down here.

**A wallpaper pin belongs to a scope.**
The pin of a theme belongs to the folders of that theme. The pin of all folders belongs to the global list of every configured folder. When a folder is removed, the pins that pointed into it are dropped with it, and `WallpaperSettings.normalized()` enforces that on every save. A theme with no folders of its own uses the global folder list as its scope, so its pin is validated against the global list.

**An appearance pin belongs to the appearance theme.**
The light pin of the Appearance sheet is stored in the theme that the system uses in light appearance, and the dark pin in the theme it uses in dark appearance, because that is the scope the app reads a pin from. Without such a theme the pin is stored in the pin of all folders for that appearance. The sheet names the scope it writes to and offers only the images of that scope. The Settings window disables the pin of all folders for an appearance while a theme is set for it, so a pin cannot be picked that the app never reads.

**Appearance matching pauses the timer and the theme actions.**
While Appearance Matching is on, the rotation timer and the theme actions (shuffle theme, next theme, previous theme) are paused. A manual shuffle, next or previous is still allowed. It stays inside the matched collection, the folders of the effective theme, and it only ignores the exact-image pin. The theme actions are blocked because a theme action would show one theme and the wallpaper of another one.

**A pinned wallpaper is a standing instruction, not a wake-up rule.**
While Appearance Matching is on, the pinned wallpaper of the current appearance is applied when the system changes appearance, and when the user changes the pin, the theme or the matching itself. It is not applied when the app only wakes up, so a wallpaper the user picked by hand stays on the screen.

**A wallpaper picked by hand waits for a running rotation.**
A wallpaper picked by hand while a rotation is running waits for the rotation to finish. A second pick replaces the first one - the last pick wins. Only one pick is kept, so the wallpaper of the last pick is applied when the rotation is done. The wait is reported through the wallpaper error, so the user knows why the wallpaper did not change yet. While the pick waits, the deferral notice is what the user sees: a failure that is reported in that window is not shown, and the outcome of the pick is reported when the pick is applied.

**The settings in memory are the truth, the file follows.**
A change is applied in memory at once: the new settings are normalised, stored and published, and the app reacts to them right away. The file is written in the background on a queue of its own, so the user interface never waits for the disk. A write that fails keeps the content the file had and is reported to the user instead of being swallowed. The write that runs last writes the settings that are current when it runs.
