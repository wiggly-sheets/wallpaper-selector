# Native Swift application

## Status

Accepted

## Decision

Wallpaper Selector is a pure Swift macOS application. SwiftUI owns app views;
AppKit owns menu-bar, window, desktop-image, and accessibility integration.
Views share observable in-process state. There is no renderer, IPC layer, or
JavaScript runtime.

## Consequences

- One native process and build path
- Lower baseline memory use than a Chromium-based implementation
- Native desktop-image and status-item integration
- macOS Accessibility permission remains necessary for automating the system
  “Show on all Spaces” setting
