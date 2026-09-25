<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Instantools icon">
</p>

<h1 align="center">Instantools</h1>

<p align="center">
  Mac tools that respond the moment you press them.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Draw time" src="https://img.shields.io/badge/draw%20time-under%201%20frame-2ea44f">
</p>

<p align="center">
  <img src="docs/images/settings.png" width="760" alt="Instantools settings">
</p>

Instantools is the successor to [InstantTab](https://github.com/infeace/InstantTab) and InstantLang, and will replace them once it is ready. It is one app with one menu bar icon, one Settings window, one login item and one set of permissions. Each tool runs in its own process, and you turn on only the ones you want.

## Tools

### Cmd+Tab

An app switcher that appears the moment you press Cmd+Tab, with the control macOS leaves out.

- **Instant.** The switcher reaches the screen within one display frame. Nothing is looked up when you press Tab: apps and windows are tracked in the background and the panel is built once at launch.
- **Monitor aware.** List apps from every monitor, the one under the mouse, the one you are working on, or a group of monitors defined by rules like "external" or "portrait", so it keeps working when you swap monitors.
- **Straight to an app.** Bind a key to an app, then Cmd+Tab and that key goes right to it, or opens it if it is not running.
- **Yours to shape.** Exclude apps always or only when they have no window, let apps like virtual machines keep Cmd+Tab, set the show delay, and preview the icon size live.
- **Safe.** Native Cmd+Tab comes back whenever the tool is turned off, quits or crashes.

| | |
|---|---|
| **Cmd+Tab** | Hold Cmd, press Tab to move, release to switch |
| **Quick Cmd+Tab** | Jump to the previous app without drawing anything |
| **Shift, \`, arrows** | Move back, or move with the arrow keys |
| **Up, Down** | App Exposé for the selected app |
| **Q, H** | Quit or hide the selected app |
| **App keys** | Go straight to the app bound to that key (Settings, App keys) |
| **Mouse** | Point to select, click to switch |
| **Esc** | Cancel |

### Language

Switch the keyboard layout with Control+Command, pressed in either order, the moment both keys are down.

- **Instant.** The switch runs inside the event callback, with no helper process in between. It takes a median of 6 ms on an M1 Pro.
- **Either order.** Ctrl then Cmd, Cmd then Ctrl, or both at once. Left and right keys count the same.
- **Typing through it.** Keys pressed while the chord is still down never cancel the switch, so it sticks when you chord in the middle of fast typing. The flip side: Ctrl+Cmd shortcuts such as Ctrl+Cmd+Q also switch, unless Shift or Option is already held.
- **Back to the last layout.** Like Ctrl+Space, it goes back to the layout used before the current one, so with two layouts it always flips between them. Emoji & Symbols and Dictation are skipped.
- **Safe.** It only listens and never blocks input, so if it quits or crashes, the keyboard is untouched.

A chord pressed while Shift, Option or Fn is held is left alone, and so is letting go of Shift from Ctrl+Cmd+Shift. Every switch is checked against what macOS reports straight after, and retried once if it did not take. To use Caps Lock as Control, set it in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys. Remove any other switcher bound to the same chord, such as a Karabiner rule: two switchers on one chord cancel out.

## Install

```bash
scripts/create-signing-cert.sh      # once per Mac: a local signing identity, so permissions survive rebuilds
scripts/build.sh --install --run    # build, copy to ~/Applications and launch
```

Requires macOS 14 or later and a Swift 6 toolchain (the Xcode command line tools are enough).

`--install` also quits InstantTab and InstantLang and removes their login agents. The apps and their settings stay where they are. On its first launch Instantools copies the Cmd+Tab settings from InstantTab, turns on the tools you used, and turns on Start at login if either old app had it. To go back, turn off Start at login in Instantools and quit it, then open the old app and turn its Start at login back on. Each time Instantools starts it quits the old apps if they are running, since they would fight it for the same keys.

On a fresh install Settings opens so you can choose the tools. Quit any other Cmd+Tab replacement first.

## Permissions

Each tool runs as part of Instantools, so macOS asks once and lists only Instantools in Privacy & Security.

- **Accessibility** covers both tools. Cmd+Tab works without it, but the keys inside the switcher and raising the right window need it.
- **Input Monitoring** is all that Language needs when you use it without Cmd+Tab. With Accessibility allowed it is not needed, unless Input Monitoring is switched off for Instantools: that stops Language and the keys inside the switcher even with Accessibility.

Settings > General lists Accessibility while any tool is on, and Input Monitoring while a tool that is on is missing it: Language without either permission, or either tool while Input Monitoring is switched off. Each has a button to allow it.

## Configure

Settings and `~/.config/instantools/cmd-tab.json5` stay in sync, so edit whichever you prefer. The file documents every option.

```json5
{
  showDelayMs: 50,
  scope: "mouseGroup",
  exclude: [{ bundleId: "com.apple.finder", when: "noWindows" }],
  appKeys: { f: "com.apple.finder", s: "com.apple.Safari" },
  passThrough: ["com.parallels.desktop.console"],
  displayGroups: [
    { name: "Laptop", match: ["builtIn"] },
    { name: "Desk", match: ["external"] },
  ],
}
```

## How it works

Instantools is one host process plus one process per tool.

- **The host** owns the menu bar icon, Settings, Start at login and the settings files. It starts each enabled tool from `Contents/Helpers` and talks to it over its stdin and stdout, one JSON message per line, only to show live status in Settings.
- **Each tool** does its whole job inside its own process: pressing Cmd+Tab or Control+Command does no IPC and never waits on anything. One tool never slows or stops another.
- **Supervision.** A tool that exits unexpectedly restarts at once, then after 1 and 5 seconds. After 5 exits within a minute it stays down and Settings offers to try again. If the host itself crashes, the tools keep working for 15 seconds, long enough for the login agent to bring the host back.
- **Safe exits.** Native Cmd+Tab comes back on every way the Cmd+Tab tool exits, and the host restores it too after any exit it did not ask for.

## Develop

```bash
swift build                  # compile
scripts/test.sh              # unit tests
scripts/build.sh             # signed build/Instantools.app (--debug, --install, --run)
```

Settings panes render to PNG without Screen Recording permission and without starting any tool, for checking UI changes:

```bash
build/Instantools.app/Contents/MacOS/Instantools --snapshot-settings switcher out.png dark --sample
```

| Path | What |
|---|---|
| `Sources/Instantools` | The host: menu bar, Settings, Start at login, tool supervisor, first-launch migration |
| `Sources/InstantoolsCore` | Tool ids, host and tool messages, restart backoff, migration decisions. Unit tested |
| `Sources/InstantoolsKit` | Shared by the host and the tools: the tool side of the channel, logging, permissions |
| `Sources/AppSwitcher` | The Cmd+Tab tool: input, switcher panel, focus |
| `Sources/AppSwitcherCore` | Its pure logic: filtering, monitor groups, config. Unit tested |
| `Sources/AppSwitcherKit` | What Settings shares with it: config store, displays, native Cmd+Tab, panel style |
| `Sources/LayoutSwitcher` | The Language tool: event tap and input sources |
| `Sources/LayoutSwitcherCore` | Its pure logic: chord detection and layout choice. Unit tested |
| `Sources/SkyLightShim` | The only place private macOS APIs are touched, each with a fallback |
| `docs/research.md` | Research, measurements and the architecture behind it |

## Roadmap

- [x] Instant switcher, quick tap, mouse, Q and H, exclusions, monitor scopes and groups
- [x] Settings window with live preview, config file sync, Start at Login
- [x] App keys: Cmd+Tab, then a bound key, goes straight to that app
- [x] App Exposé on Up and Down, apps that keep Cmd+Tab
- [x] One app for Cmd+Tab and Language, each tool in its own process
- [ ] Replace InstantTab and InstantLang
- [ ] Keyboard navigation in Settings
- [ ] One entry per window and per-app rules (deferred)
- [ ] Multiple shortcuts with their own scope (deferred)
