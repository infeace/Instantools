<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="InstantTab icon">
</p>

<h1 align="center">InstantTab</h1>

<p align="center">
  Cmd+Tab for macOS that appears the moment you press it, with the control macOS leaves out.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Draw time" src="https://img.shields.io/badge/draw%20time-under%201%20frame-2ea44f">
</p>

<p align="center">
  <img src="docs/images/settings.png" width="760" alt="InstantTab settings">
</p>

## Why

- **Instant.** The switcher reaches the screen within one display frame. Nothing is looked up when you press Tab: apps and windows are tracked in the background and the panel is built once at launch.
- **Monitor aware.** List apps from every monitor, the one under the mouse, the one you are working on, or a group of monitors defined by rules like "external" or "portrait", so it keeps working when you swap monitors.
- **Straight to an app.** Bind a key to an app, then Cmd+Tab and that key goes right to it, or opens it if it is not running.
- **Yours to shape.** Exclude apps always or only when they have no window, set the show delay, and preview the icon size live.
- **Safe.** Native Cmd+Tab comes back whenever InstantTab quits, pauses or crashes.

## Install

```bash
scripts/create-signing-cert.sh      # once per Mac: a local signing identity, so permissions survive rebuilds
scripts/build.sh --install --run    # build, copy to ~/Applications and launch
```

Then allow **Accessibility** when asked. Cmd+Tab works without it, but the in-switcher keys and raising the right window need it. Quit any other Cmd+Tab replacement first.

Requires macOS 14 or later and a Swift 6 toolchain (the Xcode command line tools are enough).

## Use

| | |
|---|---|
| **Cmd+Tab** | Hold Cmd, press Tab to move, release to switch |
| **Quick Cmd+Tab** | Jump to the previous app without drawing anything |
| **Shift, \`, arrows** | Move back, or move with the arrow keys |
| **Q, H** | Quit or hide the selected app |
| **App keys** | Go straight to the app bound to that key (Settings, App Keys) |
| **Mouse** | Point to select, click to switch |
| **Esc** | Cancel |

Everything else lives in **Settings** (menu bar icon, then Settings…).

## Configure

Settings and `~/.config/instanttab/config.json5` stay in sync, so edit whichever you prefer. The file documents every option.

```json5
{
  showDelayMs: 50,
  scope: "mouseGroup",
  exclude: [{ bundleId: "com.apple.finder", when: "noWindows" }],
  appKeys: { f: "com.apple.finder", s: "com.apple.Safari" },
  displayGroups: [
    { name: "Laptop", match: ["builtIn"] },
    { name: "Desk", match: ["external"] },
  ],
}
```

## Develop

```bash
swift build                  # compile
scripts/test.sh              # unit tests
scripts/build.sh             # signed build/InstantTab.app (--debug, --install, --run)
```

Settings panes render to PNG without Screen Recording permission, for checking UI changes:

```bash
build/InstantTab.app/Contents/MacOS/InstantTab --snapshot-settings general out.png dark
```

| Path | What |
|---|---|
| `Sources/InstantTab` | The app: input, switcher panel, focus, Settings |
| `Sources/InstantTabCore` | Pure logic: filtering, monitor groups, config. Unit tested |
| `Sources/SkyLightShim` | The only place private macOS APIs are touched, each with a fallback |
| `docs/research.md` | Research, measurements and the architecture behind it |

The hot path has one rule: pressing Cmd+Tab does no IPC and never waits on anything.

## Roadmap

- [x] Instant switcher, quick tap, mouse, Q and H, exclusions, monitor scopes and groups
- [x] Settings window with live preview, config file sync, Start at Login
- [x] App keys: Cmd+Tab, then a bound key, goes straight to that app
- [ ] Keyboard navigation in Settings
- [ ] One entry per window and per-app rules (deferred)
- [ ] Multiple shortcuts with their own scope (deferred)
