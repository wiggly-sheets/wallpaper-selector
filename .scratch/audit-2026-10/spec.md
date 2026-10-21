# Audit 2026-10

## Problem Statement

Wallpaper Selector had been rewritten from Electron to native Swift, and the
code had moved on a lot since the documentation was last written. The October
2026 audit read the whole application, compared it with the documentation,
with the settings file format and with the behaviour of the version it
replaced, and ran the build and the test suite.

## Outcome

The audit broke the CI build, and it found defects in the settings layer, the
menu bar and the rotation path. The CI break and the defects are fixed. The
CI runner is `macos-latest`, because the macOS 14 runner images are retired,
and a local `make test` runs the same command on the same toolchain, so it
is direct evidence for the CI run. The test suite covers the fixed behaviour,
`README.md` describes what the app really does, and `CONTEXT.md` records the
behaviours that are intentional product decisions and would otherwise be read
as bugs.

The findings of the audit itself were fixed in the first round. The image
discovery skips a folder that is named like an image and lists every file
once. The thumbnail cache stays small and is dropped when the picker closes.
The All Spaces automation reports the manual fallback when System Settings
stays away. **Superseded.** There is no manual fallback any more:
[ADR 0002](../../docs/adr/0002-wallpaper-store-instead-of-accessibility.md)
replaced the Accessibility approach with the wallpaper store of macOS, so the
app puts the wallpaper on every Space by writing that store. A wallpaper that
reached only some of the displays is reported. The rotation is scoped to the
theme of the current appearance. The configuration is kept when the settings
file or the state is broken. The preview popover opens below the status item
icon. The failures are shown and the controls that cannot work are greyed out.
The CI builds the release artifacts on every push and runs the tests before a
release.

The review round that followed the audit closed three more findings. The
watcher of the settings file reads the file once more when the modification
date changed while the watcher was stopped, so a write in that window is not
lost. The sheet of the Appearance dialog sizes itself to its content, the
body scrolls and the OK button stays outside the scrolling area, and the
tests measure the sheet. The rotation controls of the Settings window bind to
a property that states the effect, so no view has to negate it. The tickets
of the closed findings are deleted, so the `issues/` folder of the audit is
gone.

The round after that closed five more findings. The settings file of the old
folder is renamed to `settings.json.migrated` when the settings location
changes, so it can never be adopted silently again. The dead code of the app
target is gone. The image list is loaded once when the effective scope is the
global folder list. The `FileManager` no longer crosses the isolation
boundary of the settings IO path, so the sendability warning is gone without
`nonisolated(unsafe)`. The CI runs the `hdiutil convert` branch of the DMG
recipe on every push.

The round after that closed three more findings. The settings file is written
on a serial queue of its own, and the write runs off the main actor, so a
settings change never blocks the user interface: the settings in memory
change right away and the file catches up. Every write runs on that one
queue and writes the settings that are current when it runs, so the writes
are ordered and the last one wins. A failed write keeps the content the file
had and is reported through the settings error, so it shows up on the General
pane and in the menu bar, and the pending writes are flushed before the app
quits. The file that is recreated after an external delete is written on the
same queue, so a change that lands while the recreate waits is not lost. A
legacy settings file that was imported is renamed to `settings.json.migrated`,
and a legacy file that was never imported is reported on every launch, so it
cannot be forgotten.

The round after that closed the last three findings. The menu of the menu bar
item is built once and updated in place, so a menu that is already open shows
the new state and a click on it always runs the current action. The state of
the menu comes from one place, the view model, so the mapping from the view
model to the menu is a single function that a test can call without a status
item in the menu bar of the machine. The preview popover takes the height of
its content and is clamped to the visible frame of the display, and its body
scrolls, so it fits on a short display and every control stays reachable. The
enablement of the items of the menu is covered by a test now.

The last change of the audit closed one more finding. The menu of the status
item is owned by a class that holds an `NSMenu` instead of being a subclass
of it. A subclass has to implement `init(coder:)`, and whether that
initializer is failable depends on the SDK, so the code would only build on
some of them.

Every ticket of the audit is closed.

## Deferred work

While the audit ran, the tickets in `issues/` were the deliberate remainder.
Every ticket said what the problem was, why it was deferred, and what "done"
would look like. A ticket that would not be actioned was labelled `wontfix`,
a ticket that needed a product decision `ready-for-human`, and the rest
`ready-for-agent`.

No ticket is left: the `issues/` folder is gone, so the audit has no open
finding. The parts that no test can cover are written down in the code
instead: the SwiftUI wiring of the enabled state and the presentation of a
live status item carry a `shortcut:` comment in the three views that bind the
enabled state, so the gap is visible where the code is.
