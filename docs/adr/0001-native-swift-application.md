# Native Swift application

## Status

Accepted. The accessibility integration is superseded by
[ADR 0002](0002-wallpaper-store-instead-of-accessibility.md).

## Decision

Wallpaper Selector is a pure Swift macOS application. SwiftUI owns app views;
AppKit owns menu-bar, window, and desktop-image integration. Views share
observable in-process state. There is no renderer, IPC layer, or JavaScript
runtime.

## Consequences

- One native process and build path
- Lower baseline memory use than a Chromium-based implementation
- Native desktop-image and status-item integration

## Superseded

The original decision gave AppKit the accessibility integration and made the
macOS Accessibility permission necessary for automating the system “Show on all
Spaces” setting. Both are gone: the app puts the wallpaper on every Space by
writing the wallpaper store of macOS, so it needs no Accessibility permission
and opens no System Settings window. See
[ADR 0002](0002-wallpaper-store-instead-of-accessibility.md).
