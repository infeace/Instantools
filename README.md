# InstantTab

A macOS Cmd+Tab replacement that opens as fast as the native switcher and is configurable like AltTab: display scope and display groups, excluded apps, one entry per app or per window, and Cmd+` behavior.

Status: scaffold. See the roadmap below and [docs/research.md](docs/research.md) for the research and architecture.

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
3. Grant Accessibility and Input Monitoring in System Settings > Privacy & Security when asked.

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

1. Scaffold: package, build and signing scripts, latency instrumentation.
2. Daily driver: Cmd+Tab in app mode with quick tap, exclusions, all-displays or mouse-display scope, config file with live reload, login item, native switcher restore.
3. Customization: window mode and per-app overrides, Cmd+`, display groups, multiple shortcut profiles, Spaces and minimized window handling.
4. Polish: settings window, optional thumbnails, type to search.
