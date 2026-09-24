# InstantTab

A macOS Cmd+Tab replacement where latency is the product: pressing Cmd+Tab does no IPC and never waits on anything. Architecture and measurements are in docs/research.md.

## Build and test

- Only the Xcode command line tools are installed. Run tests with `scripts/test.sh`; plain `swift test` cannot find the Testing module.
- `scripts/build.sh` builds, bundles and signs with the local "InstantTab Local Signing" identity, so macOS permissions survive rebuilds. `--install --run` replaces the running copy. codesign can wait on a keychain prompt only the user can approve.
- Do not launch the app to check UI changes: it takes over Cmd+Tab for the whole Mac. Render a pane instead with `build/InstantTab.app/Contents/MacOS/InstantTab --snapshot-settings <pane> <out.png> [light|dark] [--sample] [--narrow] [--no-access]`.

## Rules

- Testable logic goes in InstantTabCore, which has no AppKit. Private macOS APIs live only in SkyLightShim, each with a public fallback.
- Native Cmd+Tab must come back on every exit path: quit, pause, signals and crashes.
- Accessibility calls into InstantTab's own process must run on the main thread.
- Settings never writes a config file that fails to parse.
- Start at Login is a plain LaunchAgent plist, because SMAppService fails its launch constraint on builds without a Team ID.
- Comments only for a non-obvious why.
