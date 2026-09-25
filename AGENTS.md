# Instantools

A macOS menu bar app of small tools where latency is the product, each in its own process: InstantTab, an app switcher on Cmd+Tab, and InstantLang, a keyboard layout switcher on Control+Command. It is the successor to the standalone InstantTab and InstantLang apps and will replace them once it is ready. Pressing a tool's keys does no IPC and never waits on anything. Architecture and measurements are in docs/research.md.

## Build and test

- Only the Xcode command line tools are installed. Run tests with `scripts/test.sh`; plain `swift test` cannot find the Testing module.
- `scripts/build.sh` builds build/Instantools.app with the tools in Contents/Helpers, and signs it with the local "Instantools Local Signing" identity, or "InstantTab Local Signing" when that is the one this Mac has, so macOS permissions survive rebuilds. `--install --run` replaces the running copy, and also quits the standalone InstantTab and InstantLang apps and removes their login agents, keeping the apps. codesign can wait on a keychain prompt only the user can approve.
- Do not launch the app to check UI changes: it takes over Cmd+Tab and Control+Command for the whole Mac, and a second layout switcher on the same chord cancels out the first. Render a pane instead with `build/Instantools.app/Contents/MacOS/Instantools --snapshot-settings <general|switcher|keys|monitors|exclusions|language|about|group-editor|welcome-tools|welcome-permissions|welcome-done> <out.png> [light|dark] [--sample] [--narrow] [--no-access|--input-monitoring-off]`. `language` is InstantLang's Layouts pane. It starts no tool, runs no migration and writes nothing.
- A tool binary run by hand prints a message and exits. Only the host starts tools.

## Layout

- `Instantools` is the host: menu bar, Settings, the first-launch welcome, Start at login, the tool supervisor and the first-launch migration.
- `InstantoolsCore` holds tool ids, host and tool messages, restart backoff, migration decisions, and tool and permission states. `InstantoolsKit` is shared by the host and the tools: the tool side of the channel, logging, permissions and the keyboard layout list.
- `AppSwitcher` is InstantTab, the Cmd+Tab tool, `AppSwitcherCore` its pure logic, and `AppSwitcherKit` what Settings shares with it: the config store, displays, native Cmd+Tab and the panel style.
- `LayoutSwitcher` is InstantLang, the layout tool, and `LayoutSwitcherCore` its pure logic.
- A new tool is a case in `ToolId`, its status in `ToolMessage`, an executable target, a line in the `tools` list of `scripts/build.sh`, a Settings pane, and its icon, drawn by `scripts/make-icon.swift` as `Resources/<name>.png` and copied by `scripts/build.sh`.

## Rules

- Testable logic goes in the Core targets, which have no AppKit; LayoutSwitcherCore has no Carbon or CoreGraphics either. Private macOS APIs live only in SkyLightShim, each with a public fallback.
- Tools are started only by the host, with Process or posix_spawn, never through LaunchServices, launchd or SMAppService. Started any other way, macOS treats a tool as an app of its own, without the host's permissions.
- Each tool's hot path stays inside its own process. The channel to the host only carries status for Settings.
- A tool keeps working for the grace period after the host is gone, then exits normally. Tools never write the config; Settings in the host owns every write.
- Tools have no Info.plist, so tool code never reads identifiers or versions from `Bundle.main`. Nothing in a tool prints to stdout, which is the channel to the host.
- Native Cmd+Tab must come back on every exit path of InstantTab: quit, pause, signals and crashes. The host restores it too after any exit it did not ask for.
- Only one copy of each tool may run: the host is single instance and stops leftover tools and the standalone apps before starting its own.
- Accessibility calls into a process's own windows must run on its main thread.
- InstantLang's event tap is listen-only and never holds back input. TIS calls run on the main thread, and the tap sits on the main run loop so the switch happens inside its callback.
- Settings never writes a config file that fails to parse.
- Start at Login is a plain LaunchAgent plist for the host only, because SMAppService fails its launch constraint on builds without a Team ID.
- Comments only for a non-obvious why.
