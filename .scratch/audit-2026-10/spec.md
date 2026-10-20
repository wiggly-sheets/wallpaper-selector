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

The review round that followed the audit closed three more findings. The
watcher of the settings file reads the file once more when the modification
date changed while the watcher was stopped, so a write in that window is not
lost. The sheet of the Appearance dialog sizes itself to its content, the
body scrolls and the OK button stays outside the scrolling area, and the
tests measure the sheet. The rotation controls of the Settings window bind to
a property that states the effect, so no view has to negate it. The tickets
of the closed findings are deleted, so the tickets in `issues/` are the ones
that are still open.

The round after that closed five more findings. The settings file of the old
folder is renamed to `settings.json.migrated` when the settings location
changes, so it can never be adopted silently again. The dead code of the app
target is gone. The image list is loaded once when the effective scope is the
global folder list. The `FileManager` no longer crosses the isolation
boundary of the settings IO path, so the sendability warning is gone without
`nonisolated(unsafe)`. The CI runs the `hdiutil convert` branch of the DMG
recipe on every push.

## Deferred work

The tickets in `issues/` are the deliberate remainder of the audit. None of
them is an oversight: every ticket says what the problem is, why it was
deferred, and what "done" would look like. A ticket that will not be
actioned is labelled `wontfix`, a ticket that needs a product decision
`ready-for-human`, and the rest `ready-for-agent`.

Six tickets are still open:

- 01 — the settings file write runs on the main actor
- 04 — the legacy settings migration is skipped once a settings file exists
- 07 — an open menu bar menu is not updated in place
- 10 — there is no UI test harness
- 12 — the preview popover is taller than a short display
- 14 — a settings write can be lost in the recreate path of the external reload

All six tickets are `ready-for-agent`.
