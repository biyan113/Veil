# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] - 2026-11-15

### Fixed

- Menu bar icon captures no longer include the wallpaper showing through the translucent menu bar, so tray and Settings icons are no longer smeared.

## [1.0.1] - 2026-11-15

### Changed

- Release version is now 1.0.1.

## [1.0.0] - 2026-11-15

First public release.

### Added

- Menu bar icon that drops down a tray containing the menu bar icons you added to Veil, in your chosen order; long collections wrap onto several rows.
- Open icons from the tray, including icons covered by the MacBook notch. Standard status menus are shown as a native mirrored menu under the tray icon; popovers are moved horizontally to line up with the tray icon; other UI falls back to a real click on the original icon.
- Real icon appearance captured from the menu bar with Screen Recording permission, cached locally as PNG files; monochrome icons are turned into template images that follow light/dark mode, colored icons keep their colors. Falls back to the app icon without the permission.
- Several ways to toggle the tray: clicking the Veil icon, a configurable global shortcut (default ⌥⌘B), and scrolling over the menu bar (can be turned off).
- Tray interactions: click to open, drag out of the tray to remove, right-click for Open / Remove from Veil; Esc or clicking elsewhere closes the tray.
- Settings window with Layout (pick and reorder icons with click and drag-and-drop), General (launch at login, scroll to toggle, shortcut recorder, Veil icon style) and About panes.
- Four styles for the Veil menu bar icon: chevron, eye, dot, lines.
- Favorites survive app restarts and icons whose titles change with state (relinked when the app has a single icon).

### Fixed

Fixes made before the first public release:

- Icon image cache filenames are now stable across launches, so cached icon images are no longer lost after a restart.
- Faster tray opening: only the apps that own added icons are scanned, icon capture is rate-limited and image processing runs off the main thread.
- No icon capture while the menu bar is hidden (full screen), so window contents are no longer saved as icons.
- Accessibility calls are capped at 1 second, so an unresponsive app no longer blocks Veil.
- Fixed the old shortcut coming back after clearing it, and the shortcut stopping working when the Settings window was closed while recording.
- Fixed a race when toggling the tray quickly, a stale Veil icon state, and the tray not closing when clicking the Settings window.
- Clicking the Veil icon after moving the pointer no longer closes and immediately reopens the tray (outside clicks are now hit-tested using the event's own location).
- `build.sh` correctly falls back to ad-hoc signing when no certificate is available.

[Unreleased]: https://github.com/biyan113/Veil/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/biyan113/Veil/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/biyan113/Veil/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/biyan113/Veil/releases/tag/v1.0.0
