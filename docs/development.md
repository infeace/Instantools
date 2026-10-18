# Developing Instantools

How Instantools works, how to build and test it, and where things live. For what it does and how to install it, see the [README](../README.md).

## How it works

Instantools is one host process plus one process per tool.

- **The host** owns the menu bar, Settings, the welcome window, Start at login and the settings files. It starts each enabled tool from `Contents/Helpers` and talks to it over its stdin and stdout, one JSON message per line, only to show live status and to check that it still answers.
- **Each tool** does its whole job inside its own process: pressing Cmd+Tab or Control+Command does no IPC and never waits on anything. InstantSnap's window moves are Accessibility calls into the app that owns the window, on a queue of their own, so a busy app never holds up its shortcuts or the mouse.
- **Supervision.** A tool that exits unexpectedly restarts at once, then after 1 and 5 seconds. A tool that hangs is stopped and counts as one of those exits: the host pings each tool every 2 seconds, and stops one that misses 3 pings in a row or is not ready 12 seconds after it starts. After 5 exits within a minute it stays down and Settings offers to try again. If the host itself crashes, the tools keep working for 15 seconds, long enough for the login agent to bring the host back.
- **Safe exits.** InstantTab restores native Cmd+Tab on every way out. The host also remembers whether InstantTab may have left it off, and restores it after any exit it did not ask for, at quit, and at the next launch after a crash. When InstantTab is off, Instantools leaves native Cmd+Tab alone, so another switcher keeps its setup.

## Develop

```bash
swift build                  # compile
scripts/test.sh              # unit tests
scripts/build.sh             # signed build/Instantools.app (--debug, --install, --run)
swift scripts/make-icon.swift  # redraw the app and tool icons into Resources
```

Settings panes and the welcome steps render to PNG without Screen Recording permission and without starting any tool, for checking UI changes:

```bash
build/Instantools.app/Contents/MacOS/Instantools --snapshot-settings switcher out.png dark --sample --height 900
```

Panes are `general`, `switcher`, `keys`, `monitors`, `exclusions`, `language` (the Layouts pane), `snapping`, `snapShortcuts`, `about`, `group-editor`, `welcome-tools`, `welcome-permissions` and `welcome-done`. Add `--narrow` for the narrowest window, and `--no-access` or `--input-monitoring-off` for the permission states.

| Path | What |
|---|---|
| `Sources/Instantools` | The host: menu bar, Settings, welcome window, Start at login, tool supervisor, first-launch migration |
| `Sources/InstantoolsCore` | Tool ids, host and tool messages, restart backoff, migration decisions, tool and permission states, the config file protocol. Unit tested |
| `Sources/InstantoolsKit` | Shared by the host and the tools: the tool side of the channel, the config file store, logging, permissions, the keyboard layout list |
| `Sources/AppSwitcher` | InstantTab: input, switcher panel, focus |
| `Sources/AppSwitcherCore` | Its pure logic: filtering, monitor groups, config. Unit tested |
| `Sources/AppSwitcherKit` | What Settings shares with it: its config store, displays, native Cmd+Tab, panel style |
| `Sources/LayoutSwitcher` | InstantLang: event tap and input sources |
| `Sources/LayoutSwitcherCore` | Its pure logic: chord detection and layout choice. Unit tested |
| `Sources/WindowSnapper` | InstantSnap: hotkeys, window moves, drag watch, preview |
| `Sources/WindowSnapperCore` | Its pure logic: layouts, drag zones, shortcuts, config, Rectangle import. Unit tested |
| `Sources/SkyLightShim` | The only place private macOS APIs are touched, each with a fallback |
| `docs/research.md` | Research, measurements and the architecture behind it |

## Signing prompts

Creating the signing identity asks for your password once, to trust it. A build may then ask up to three times, once for each program it signs, whether `codesign` may use the identity's key. Always Allow stops those prompts for later builds, at a cost: any program you run could then sign with that key without asking, and pass itself off as Instantools to get the permissions you gave it. Allow asks again at the next build.

## Coming from the standalone apps

`--install` quits the standalone InstantTab and InstantLang apps and removes their login agents, and leaves the apps and their settings where they are. On its first launch Instantools copies the standalone InstantTab app's settings, turns on the tools you used, and turns on Start at login if either app had it. Each time Instantools starts it quits the standalone apps if they are running, since they would fight it for the same keys. To go back, turn off Start at login in Instantools and quit it, then open the standalone app and turn its Start at login back on.

## Privacy in the code

The event taps are in `Sources/LayoutSwitcher/ChordTap.swift` and `Sources/AppSwitcher/InputTaps.swift`, the hotkeys in `Sources/AppSwitcher/HotKeys.swift` and `Sources/WindowSnapper/SnapHotKeys.swift`, and the mouse watch in `Sources/WindowSnapper/DragSnapper.swift`.

## Roadmap

- [x] Instant switcher, quick tap, mouse, Q and H, exclusions, monitor scopes and groups
- [x] Settings window with live preview, config file sync, Start at login
- [x] App keys: Cmd+Tab, then a bound key, goes straight to that app
- [x] App Exposé on Up and Down, apps that keep Cmd+Tab
- [x] One app for InstantTab and InstantLang, each tool in its own process
- [x] Tool icons, a welcome window, live layouts in Settings and the menu
- [x] InstantSnap: window snapping by shortcut and by drag, with Rectangle's shortcuts
- [ ] Replace the standalone InstantTab and InstantLang apps
- [ ] InstantLang settings: which layouts take part, shortcuts that should not switch, a key per layout
- [ ] VoiceOver in the switcher
- [ ] Keyboard navigation in Settings
- [ ] One entry per window and per-app rules (deferred)
- [ ] Multiple shortcuts with their own scope (deferred)
- [ ] InstantSnap: record shortcuts in Settings
