# Veil

**English** | [简体中文](README.zh-CN.md)

Veil is a small macOS menu bar utility that keeps your favorite menu bar icons one click away, including the ones hidden behind the MacBook notch. It does not hide or rearrange anything: your menu bar stays exactly as it is. You pick the icons you use most, and Veil shows them in a tray that drops down from its own menu bar icon. Clicking an icon in the tray opens that app's menu or popover.

![The Veil tray](docs/images/tray.png)

> The app's interface is currently in **Simplified Chinese** only.

## Features

- **A tray of the icons you choose.** Click the Veil icon to drop down a tray with the icons you added, shown in the order you set. Long collections wrap onto several rows.
- **Works around the notch.** Icons covered by the notch can still be opened from the tray.
- **Menus open under the tray.** Standard status menus are rebuilt as a native menu right below the tray icon. Popovers (`NSPopover`) are moved horizontally to line up with the tray icon.
- **Real icon appearance.** With Screen Recording permission, Veil captures what each icon actually looks like in the menu bar and shows that in the tray and in Settings. Monochrome icons follow light/dark mode; colored icons keep their colors. Without the permission, the app's own icon is shown instead.
- **Several ways to open the tray:** click the Veil icon, press a global shortcut (default ⌥⌘B, changeable in Settings), or scroll down while the pointer is over the menu bar (can be turned off).
- **Drag-and-drop organizing** in Settings › Layout.
- **Four styles for the Veil icon** (chevron, eye, dot, lines) and an option to launch at login.

## Screenshots

| Settings › Layout | Settings › General |
| --- | --- |
| ![Layout settings](docs/images/settings-layout.png) | ![General settings](docs/images/settings-general.png) |

## Installation

1. Download `Veil-<version>-macos-arm64.zip` from [GitHub Releases](https://github.com/biyan113/Veil/releases).
2. Unzip it and drag **Veil.app** into `/Applications`.
3. Open Veil. On first launch it opens its Settings window, where you can grant the permissions below.

Keep Veil in `/Applications`: macOS ties privacy permissions and the login item to the app's location and signature.

## Permissions and privacy

Veil asks for two permissions in System Settings › Privacy & Security.

| Permission | What Veil uses it for |
| --- | --- |
| **Accessibility** (required) | Listing the menu bar icons of running apps, reading their menus, and clicking icons and menu items on your behalf when you use the tray. Without it the tray cannot open. |
| **Screen Recording** (optional) | Capturing the real look of the menu bar icons. Veil captures only the menu bar strip, crops out each visible icon, and saves the crops as PNG files in `~/Library/Caches/net.bytenote.veil/`. Without it, the tray shows app icons instead. |

**Privacy:** the captured icon images stay on your Mac in the cache folder above. Veil's source code contains no networking code (no `URLSession`, sockets or similar), so nothing is uploaded or sent anywhere. Settings and the list of icons you added are stored in Veil's own user defaults. You can delete the cache folder at any time; Veil recaptures icons the next time they are visible.

The global shortcut uses the Carbon hot-key API and does not need any extra permission.

## Usage

- **Add icons:** open Settings (right-click the Veil icon › the first menu item, or reopen Veil from Finder) and go to the **Layout** tab. The top section lists every icon in your menu bar (it is only a picker; nothing in the real menu bar changes). Click an icon, or drag it into the lower section, to add it to Veil.
- **Reorder / remove:** drag icons within the lower section to reorder them; drag one back to the top section, or click it there again, to remove it.
- **Open the tray:** click the Veil icon, press ⌥⌘B, or scroll down over the menu bar. Scroll up over the menu bar, click anywhere else, or press Esc to close it.
- **In the tray:** click an icon to open its menu. Drag an icon out of the tray to remove it from Veil. Right-click an icon for **Open** and **Remove from Veil**.
- **Veil icon menu:** right-click (or Control-click) the Veil icon for Settings and Quit.

## System requirements

- macOS 14 Sonoma or later
- A Mac with Apple silicon (release builds are arm64 only)

Veil has been tested mainly on macOS 27. It should run on macOS 14 and later, but older versions have received less testing.

## Known limitations

- **Veil does not hide icons.** It is not a menu bar hider like Bartender or Ice. Every icon stays in the real menu bar; Veil only gives you another way to reach the ones you choose.
- **Mirrored menus are simplified.** When Veil can read a menu through Accessibility, it shows a native copy of it under the tray. The copy keeps titles, enabled state, check marks, keyboard shortcuts and submenus, but **loses item icons and custom views** (sliders, toggles, rich rows, etc.). Choosing an item clicks the matching item in the original menu.
- **Some menus and windows still appear in their original place.** If a menu consists only of custom views (so there is no text to mirror), or the app shows something other than a standard menu or popover (for example its own custom window), Veil really clicks the icon and the app's UI appears where the app puts it, which can be next to or behind the notch.
- **Popovers are only moved sideways.** They keep the vertical position macOS gives them.
- **Icon images can be stale.** An icon can only be captured while it is actually visible on screen, so icons hidden by the notch show the last captured image, or the app icon if they were never captured. Icons are not captured while the menu bar is hidden (full screen, auto-hide).
- **Locally built copies are ad-hoc signed** unless a Developer ID certificate is available, so macOS may ask you to grant the permissions again after each rebuild.

## Building from source

Requirements: Xcode with Swift 6 (the package uses `swift-tools-version:6.0`), on an Apple silicon Mac.

```bash
./build.sh
```

This builds a release binary, assembles `build/Veil.app`, signs it (with the first "Developer ID Application" identity in your keychain, or `VEIL_SIGN_ID` if set, otherwise ad-hoc), and installs it to `/Applications/Veil.app`, replacing any running copy.

Environment variables:

| Variable | Effect |
| --- | --- |
| `VEIL_NO_INSTALL=1` | Only build `build/Veil.app`; do not touch `/Applications`. |
| `VEIL_BUILD=<n>` | Build number (`CFBundleVersion`). Defaults to `git rev-list --count HEAD`, or `1` outside a git checkout. |
| `VEIL_SIGN_ID=<identity>` | Code-signing identity to use. |

The version number lives in `VERSION`, and the `Info.plist` template in `Resources/Info.plist.in`.

**App icon:** the build uses the checked-in `Resources/AppIcon.icns`. `Scripts/make-icon.swift` is the tool that draws it; to regenerate the icon after changing that script:

```bash
swift Scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

## License

Veil is free software, licensed under the [GNU General Public License v3.0](LICENSE) (GPL-3.0). Copyright © 2026 Veil contributors.

See [CHANGELOG.md](CHANGELOG.md) for release notes.
