# InstantTab

A macOS Cmd+Tab replacement that opens as fast as the native switcher and is configurable like AltTab: display scope and display groups, excluded apps, one entry per app or per window, and Cmd+` behavior.

Status: daily driver (roadmap step 2). See [docs/research.md](docs/research.md) for the research and architecture.

## Requirements

- macOS 14 or later (developed on macOS 26)
- Swift 6 toolchain. The Xcode command line tools are enough.

## Setup

1. Create the local signing identity, once per machine:
   ```bash
   scripts/create-signing-cert.sh
   ```
   It adds a self-signed code signing certificate to your login keychain and asks for your password to trust it. Every build is signed with it, so macOS keeps the permissions you grant across rebuilds.
2. Build, install into `~/Applications` and launch:
   ```bash
   scripts/build.sh --install --run
   ```
3. Grant Accessibility in System Settings > Privacy & Security when asked. Without it Cmd+Tab still works, but Esc and the arrow keys do not, and windows are not raised within their app.
4. Quit any other Cmd+Tab replacement (such as AltTab) so they do not both respond.

## Using it

- Hold Cmd and press Tab to move forward, add Shift to move back, release Cmd to switch. Arrow keys also move and Esc cancels.
- A quick Cmd+Tab switches to the previous app without drawing anything.
- The menu bar icon shows draw time (key press to first frame, after the show delay), config errors, Start at Login, and Pause, which hands Cmd+Tab back to macOS.
- Native Cmd+Tab is restored whenever InstantTab quits or crashes. With Start at Login on, a crashed copy is relaunched.

## Configuration

Settings live in `~/.config/instanttab/config.json5`, created with every option documented on first launch. Changes apply on save.

| Key | Values | Default |
|---|---|---|
| `showDelayMs` | 0 to 1000 | 50 |
| `scope` | `"all"`, `"mouseDisplay"` | `"all"` |
| `windowlessApps` | `"show"`, `"end"`, `"hide"` | `"show"` |
| `iconSize` | 32 to 256 | 96 |
| `exclude` | bundle ids, or `{ bundleId, when: "always" \| "noWindows" }`, `*` suffix for prefixes | none |

## Development

- `swift build` compiles, `scripts/test.sh` runs the unit tests (it adds the flags the command line tools need).
- `scripts/build.sh` assembles and signs `build/InstantTab.app`. `--debug` builds debug, `--install` copies into `~/Applications` after quitting the running copy, `--run` launches it.

## Layout

- `Sources/InstantTab`: the app (input, panel, focus).
- `Sources/InstantTabCore`: pure logic (model, filtering, config, latency stats), unit tested.
- `Sources/SkyLightShim`: the only place private macOS APIs are declared, resolved at runtime with public fallbacks.
- `docs/research.md`: research, measurements and the architecture this follows.

## Performance rules

- The key press path does no IPC. It reads the model snapshot that background threads keep fresh.
- Nothing blocks the main thread. Accessibility and SkyLight queries run off-main with short timeouts.
- No SwiftUI, glass effects or animations on the show path.
- Every change to the show path is measured: key press to first frame, p50 and p95.

## Roadmap

1. Scaffold: package, build and signing scripts, latency instrumentation. (done)
2. Daily driver: Cmd+Tab in app mode with quick tap, exclusions, all-displays or mouse-display scope, config file with live reload, login item, native switcher restore. (in testing)
3. Customization: window mode and per-app overrides, Cmd+`, display groups, multiple shortcut profiles, Spaces and minimized window handling.
4. Polish: settings window, optional thumbnails, type to search.
