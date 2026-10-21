# The wallpaper store instead of Accessibility

## Status

Accepted

## Decision

The app puts the wallpaper on every Space by writing it into the store of the
macOS wallpaper agent and restarting the agent. The store is
`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. The
agent owns the file and rewrites it on every change, so the app writes the
file itself and restarts the agent with `killall WallpaperAgent`. The agent is
started by launchd, so it reads the store on its own.

The Accessibility integration of ADR 0001 is gone. The app does not open the
Wallpaper pane of the System Settings, does not press the “Show on all Spaces”
control and needs no Accessibility permission. That control was pressed once
and flipped back by the next wallpaper the app set, it does not exist on
macOS 13, and its identity changes with every redesign of the System
Settings.

## Consequences

- The wallpaper reaches every Space, also after a wallpaper change that the
  app made itself
- The desktop flickers briefly while the agent restarts
- The app writes the store, so it backs the store up once before the first
  write and refuses to write a store it does not understand
- The feature needs macOS 14 or newer, because macOS 13 has no such store
- ADR 0001 keeps its decision about the native Swift application, but its
  claim that the Accessibility permission is necessary no longer holds
