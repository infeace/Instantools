# Instantools research

This began as the research for InstantTab, whose switcher is now the Cmd+Tab tool of Instantools, and it is kept as written. The sections on keyboard layout switching and on tool processes cover the Language tool and the one-process-per-tool design.

Research date: 2026-09-24. Measurements were taken on an M1 Pro running macOS 26.5.1 with two external displays at 75 Hz. The app itself must stay generic: nothing in the design depends on this machine or display layout.

## Goals

1. Speed first. The switcher appears at the next display refresh after the key press, which is the physical floor (one to two frames, 13 to 27 ms at 75 Hz). A quick tap switches without drawing anything, like native Cmd+Tab.
2. Configurable scope: all displays, the display under the mouse, the display of the focused window, or user-defined display groups.
3. Excluded apps.
4. One entry per app or one entry per window, chosen globally and per app, plus Cmd+` behavior.

## Existing apps

No existing app meets all four goals. Nothing supports custom display groups except Hammerspoon, which needs code and takes about 0.5 s to appear. Nobody publishes latency measured against native Cmd+Tab.

| App | License | Display scope | Exclusions | Per-app / per-window | Speed reports |
|---|---|---|---|---|---|
| AltTab | GPL-3.0, Pro tier in 11.x | current or all, per shortcut | yes | both, plus active-app mode | frequent lag reports |
| Witch | closed, $14 | not documented | yes | both | polls every app, slow apps slow it |
| Contexts | closed, last release 2022 | sidebar only | yes | windows, Cmd+` | called fast, abandoned |
| DockDoor | GPL-3.0 | current monitor | yes | groups only chosen apps | slower than AltTab in reports |
| Command-Tab Plus 2 | closed, $10.39 | current display | hidden apps only | apps then windows | idle CPU complaint |
| rcmd | closed | popup position only | unknown | windows, Cmd+` | vendor claims only |
| Switch (Sanyam-G) | FSL-1.1-MIT | current display | yes | windows only | pre-warms picker |
| BetterCmdTab | GPL-3.0 | Spaces only | yes | both | unknown |
| Hammerspoon | MIT | any screen list, in code | yes, in code | in code | about 0.5 s |

## Native Cmd+Tab

- The Dock owns the switcher. WindowServer matches Cmd+Tab and Cmd+Shift+Tab as symbolic hotkeys 1 and 2 before any app sees them.
- Cmd+` (symbolic hotkey 27) is not handled by a system process. AppKit in the frontmost app cycles its windows.
- It shows apps, not windows, from an MRU list and icons already in memory. It never enumerates windows on the key press, which is why it feels instant.
- A quick tap switches to the previous app without drawing anything.

## Why AltTab feels slower

Ranked by likely impact, from a read of the AltTab source (v11.7.1 and the locally installed v10.3.0) and its issue tracker:

1. A 100 ms appearance delay by default (`windowDisplayDelay`). The local install uses the default.
2. The summon is a Carbon hotkey delivered on the main thread, and filtering, layout, ordering the panel in and the frame commit all run there too. Any main-thread stall delays the switcher (issues 5109, 5721, 5981).
3. AppKit tile layout (2 to 6 ms steady, 22 to 29 ms the first time) and `makeKeyAndOrderFront` (4 to 10 ms).
4. Thumbnail recapture and a full window rescan right after every show compete with the first frames and load WindowServer (issues 5177, 5786).
5. In v10.3.0 specifically: synchronous CGS calls on the show path and ScreenCaptureKit `captureSampleBuffer`, both removed later.

AltTab's techniques are sound and worth borrowing. The slowness comes from where the work runs and from thumbnails being central to the design.

## Measured costs on this machine

| Operation | Median |
|---|---|
| `CGWindowListCopyWindowInfo`, on-screen (46 entries) | 0.6 to 0.7 ms |
| `CGWindowListCopyWindowInfo`, all (367 entries) | 3.6 to 3.8 ms |
| `SLSCopyWindowsWithOptionsAndTags`, all Spaces | 0.036 ms |
| `SLSWindowQueryWindows`, batch of 177 windows | 0.22 ms (max 9.8 ms) |
| Show a pre-created CALayer panel with 20 tiles | 4.0 ms |
| Show a freshly created CALayer panel | 7.4 ms |
| Show a pre-created SwiftUI panel | 11.5 ms |
| Trigger to next display frame, any variant | 18 to 21 ms |

Enumeration is not the bottleneck. The panel is display-bound once it is pre-created and built from layers. Accessibility (AX) calls were not measured (no permission). They are IPC per app and unbounded when an app is busy (default timeout 6 s), so they must never run on the key-press path.

## Platform facts

### Shortcut interception

- `CGSSetSymbolicHotKeyEnabled(1 and 2, false)` disables the native switcher. The setting persists after the app quits, so it must be restored on quit, on signals and at next launch after a crash. Another switcher can turn the same hotkeys off for itself, so restoring them when nothing of ours turned them off undoes that switcher's setup.
- Once the native hotkeys are off, Carbon `RegisterEventHotKey` can take Cmd+Tab. Carbon hotkeys need no Accessibility permission and keep working under Secure Input (password fields, Terminal secure keyboard entry). They are delivered on the main thread, so the main thread must stay idle.
- Modifier release comes from a listen-only session event tap (`flagsChanged`), which needs Input Monitoring. Run it on a dedicated high-priority thread. Secure Input filters `keyDown` from taps but not `flagsChanged`.
- An active (filtering) tap needs Accessibility and can break third-party input methods if always on (AltTab issue 5766). Arm it only while the switcher is open.
- Tap callbacks must be integer compares plus a queued handoff. Re-enable the tap on `kCGEventTapDisabledByTimeout`.
- macOS 26 Game Overlay takes Cmd+Esc.

### Window model

- `kAXWindowsAttribute` omits windows on other Spaces. Finding them needs a brute-force `_AXUIElementCreateWithRemoteToken` scan (yabai, AltTab).
- Window titles from `CGWindowList` and SkyLight need Screen Recording. AX titles need only Accessibility.
- Minimized (SLS tag bit 1<<60) and fullscreen (space type mask 0x20) can be read from SkyLight without touching a slow app.
- An always-fresh model is built from `NSWorkspace.runningApplications` KVO (launch notifications miss some apps), one AXObserver per app, SkyLight notify procs (per-window opt-in since Sequoia, each call replaces the whole list), and `activeSpaceDidChange`.

### Focusing a window

- Since macOS 14, `NSRunningApplication.activate` is a cooperative request and `activateIgnoringOtherApps` has no effect.
- The reliable recipe (yabai, AltTab, Hammerspoon): `_SLPSSetFrontProcessWithOptions(psn, windowId, 0x200)`, then a makeKeyWindow event record via `SLPSPostEventRecordTo`, then `kAXRaiseAction`.
- Pitfalls: allocate 0x100 bytes for the record (WindowServer aborts otherwise since 14.7.4), send a mouse-down only at an off-window point such as (300000, 300000) (macOS 27 treats edge points as resize grabs), and repair the origin Space front app with `SLSSpaceSetFrontPSN` after a cross-Space focus.
- Open report: incomplete focus on fast switching on macOS 26.6.2 (AltTab issue 6064).

### Panel

- Pre-created `NSPanel` with `.nonactivatingPanel`, level `.popUpMenu`, `canJoinAllSpaces` and `fullScreenAuxiliary`, recycled CALayer tiles, implicit animations disabled.
- Keep SwiftUI and `NSGlassEffectView` off the hot path. One project measured warm open going from 10.7 ms to 27.5 ms after adopting glass.
- Measure with `os_signpost` at the tap callback, the main-thread handoff and the `CATransaction` commit, plus `NSScreen.displayLink` target timestamps. Validate end to end with a 240 fps phone camera against native Cmd+Tab.

### Displays

- CG and AX use a top-left origin. NSScreen uses bottom-left: flip with the max Y of the primary screen.
- With "Displays have separate Spaces" on, map windows to displays by Space membership. With it off, use the largest frame intersection.
- `CGDisplayCreateUUIDFromDisplayID` gives stable ids, but UUIDs can shuffle between identical monitors, after sleep or with DisplayLink. Keep a fallback fingerprint (vendor, model, serial, localized name), and prefer rules (position, orientation, built-in) over ids in user config.

### Dock overlays

- `CoreDockSendNotification("com.apple.expose.front.awake", 0)` toggles App Exposé for the frontmost app, so it opens App Exposé only after a switch has landed and closes it when sent again.
- While Mission Control or App Exposé is up, `CGWindowList` reports every window as off screen. The Dock shows it with windows at layers 18 to 20 that cover a whole display, which the Dock bar never does.
- Activating another app does not close App Exposé. Switching first and then closing it lands on the new app; closing first flashes the app App Exposé was showing.

### Thumbnails

- `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK.
- ScreenCaptureKit: cache `SCShareableContent`, prefer the macOS 26 `captureScreenshot` at thumbnail size, and limit concurrency. Repeated `captureSampleBuffer` calls leaked WindowServer memory until forced logouts (AltTab 5786), and bursts wedged the screenshot service (5861).
- Sequoia introduced recurring Screen Recording prompts. Status on Tahoe is unverified.
- Viable only if the panel never waits on a capture: cached images, background refresh.

### Signing and permissions

- Ad-hoc signing makes the designated requirement the cdhash, so every rebuild is a new app to TCC and Accessibility and Input Monitoring grants are lost.
- Fix: sign every build with one stable identity (self-signed code signing certificate or a free Apple Development certificate) and a fixed bundle id.
- Quit the app before replacing its binary. Health-check the tap with `CGEventTapIsEnabled` and `CGPreflightListenEventAccess`.
- A locally built, non-sandboxed, non-notarized app runs fine. Start at login uses a classic LaunchAgent in `~/Library/LaunchAgents`: without a Team ID, macOS pins an `SMAppService` agent to the exact binary that registered it, so every rebuild fails its launch constraint.

### macOS 26 and 27

- macOS 27 shipped on 2026-09-14. AltTab already has 27-specific bugs: other-Space windows leaking through filters (6028), panel corner radii (6053), 100% CPU from tracking dead processes (6051).
- Private SkyLight APIs can change in any release, so they belong behind one isolated shim with public fallbacks.

## Proposed architecture

Swift 6 and AppKit, built with Swift Package Manager (no Xcode required), assembled into an `.app` bundle and signed with a stable identity by a build script.

- **Input.** Carbon hotkeys for each configured shortcut. Native hotkeys 1 and 2 are disabled while running and restored on quit and signals, and at the next launch only when the last run may have left them off. A listen-only session tap on a dedicated thread watches modifiers. An active tap is armed only while the panel is open, for arrows, Esc and in-switcher keys.
- **Model.** Runs off the main thread. It combines workspace KVO, per-app AXObservers with a short messaging timeout, and SkyLight notifications with batched queries. It keeps its own MRU order of windows and publishes an immutable snapshot by atomic swap. The key press reads the snapshot and does no IPC.
- **Filter.** A pure function from snapshot, shortcut profile, display layout and mouse position to the list of entries. It runs in microseconds and is unit-testable.
- **Panel.** One pre-created non-activating panel with recycled layer tiles and pre-rendered icons. No SwiftUI, glass or animation on the show path. Whether it needs to become key is to be measured.
- **Quick tap.** The target is computed at key down. The show timer (configurable, 0 to 100 ms) is cancelled if the modifier is released first, and focus happens immediately.
- **Focus.** The SkyLight recipe above, on a background queue with supersede tokens, falling back to `activate()`.
- **SkyLight shim.** The only module that declares private symbols. Each call has a public fallback.
- **Config.** A JSON5 file (`JSONDecoder.allowsJSON5`, no dependencies) with hot reload and clear validation errors. A settings window comes later and may use SwiftUI, since it is off the hot path.
- **Diagnostics.** Signposts and an optional latency log with p50 and p95 from key press to frame.

## Configuration model

Each shortcut is a profile: keys, scope, entry mode and filters. Example:

```json5
{
  showDelayMs: 0,
  exclude: [
    { bundleId: "com.apple.finder", when: "noWindows" },
    { bundleId: "com.electron.wispr-flow" },
  ],
  displayGroups: {
    landscape: { match: [{ orientation: "landscape" }] },
    portrait: { match: [{ orientation: "portrait" }] },
  },
  shortcuts: [
    {
      keys: "cmd+tab",
      scope: "mouseDisplay",    // all | mouseDisplay | focusedDisplay | mouseGroup | group:<name>
      entries: "apps",          // apps | windows | frontAppWindows
      perApp: { "com.microsoft.VSCode": "windows" },
      appActivation: "lastWindow", // lastWindow | allWindows
      spaces: "current",        // current | all
      minimized: "last",        // show | hide | last
    },
    { keys: "cmd+`", scope: "mouseDisplay", entries: "frontAppWindows" },
    { keys: "cmd+alt+tab", scope: "all", entries: "windows" },
  ],
}
```

- A display group is a set of match rules (position, orientation, built-in or external, name pattern, display id). A group with no connected display falls back to all displays.
- In app mode, an app appears if it has a window in scope, and selecting it focuses its most recent window in scope.
- In app mode, pressing ` on a highlighted app steps through that app's windows inside the switcher.

## Risks

1. Private APIs break on OS updates, macOS 27 in particular. Mitigation: the shim, public fallbacks, and testing before upgrading the OS.
2. If InstantTab dies, native Cmd+Tab stays disabled. Mitigation: restore on quit, on signals and at the next launch after a crash, keep the app alive with a login agent, and offer a menu item that restores native.
3. Replacing the binary while it runs can leave taps dead or, per an unconfirmed macOS 26 report, drop input. Mitigation: the build script quits the app first, and filtering taps are armed only while the panel is open.
4. Windows on other Spaces need a brute-force AX token scan. It is deferred to phase 2.
5. Thumbnails cost WindowServer load and permission prompts. They are off by default and come later.

## Keyboard layout switching

The Language tool switches layouts on Control+Command. Measured on the same Mac:

- `TISSelectInputSource` takes a median of 6 ms, with a maximum of about 21 to 27 ms. Other processes see the new layout 3 to 7 ms later, as long as their run loop is serviced. TIS is not thread safe and must run on the main thread.
- Karabiner's `select_input_source` goes through a socket to a separate user process, and `input_source_if` reads a cached language that is updated asynchronously, so a quick second toggle can read the old layout and do nothing.
- Karabiner 16.1 grabs the keyboards again after every wake, which leaves gaps of several seconds in which a chord does nothing.
- The switch fires on the press that completes the chord and is never undone by later keys: when typing fast, the next letter often lands while the chord is still down.
- Secure Input (password fields, Terminal's secure keyboard entry) hides key presses from event taps but not modifier changes, so a tap that only watches modifiers keeps working.

So the tool runs a listen-only tap for modifier changes on the main run loop and switches inside the callback, with no hop to another thread or process. It tracks the previous layout itself rather than waiting for the notification, and checks each switch against what macOS reports, retrying once.

## Tool processes and permissions

Each tool is its own process, started by the host. Measured on macOS 26.5.1 with a probe app:

| Fact | What Instantools does |
|---|---|
| A process started by the app with `Process` or `posix_spawn`, a plain executable or one inside a nested .app, and its own children, count as the app to TCC (its responsible process). They get its Accessibility, Input Monitoring and event posting grants, verified by real event delivery, AX calls, active and listen taps, `TISSelectInputSource` and windows, and keep them after the app exits. | Tools are started only by the host and share its one set of permissions. |
| A helper opened through LaunchServices (`NSWorkspace.openApplication`, `open`), a launchd job, or a spawn with responsibility disclaimed is its own TCC identity, with its own prompts and Privacy entries. | Tools are never opened, never login items, and refuse to run unless the host started them. |
| With Accessibility granted and no Input Monitoring record, listen-only keyboard taps work. Input Monitoring turned off explicitly blocks them even with Accessibility on. With no permission, a tap for modifier changes is created but receives nothing. `CGPreflightListenEventAccess` is true with Accessibility alone, and false when Input Monitoring was switched off even with Accessibility on. | Both tools create their taps only once `CGPreflightListenEventAccess` is true. The host checks it too, since a tap created earlier keeps running but hears nothing once Input Monitoring is switched off, and offers Input Monitoring whenever it is false and a tool needs it. |
| An idle AppKit tool process with a window costs about 9 MB (phys_footprint). | One process per tool is cheap. |
| Rebuilds signed with the same identity keep TCC grants. | Every build is signed with one local identity. |

A tool whose stdin reaches end of file keeps working for 15 seconds and then exits normally, so Cmd+Tab and layout switching survive a host crash while launchd relaunches the host, and a force-quit host leaves no tools behind for long. The new host stops any tool still running from before, then starts its own.

InstantTab restores native Cmd+Tab on its own way out: its atexit handler covers every `exit()`, including the one after a termination signal, and its crash handlers restore before re-raising. The host restores it too after any exit it did not ask for and after any exit by a signal, since a kill skips the tool's handlers. It never restores otherwise, so someone who runs only InstantLang next to another switcher keeps that switcher's setup. To know when, the host keeps a marker in its defaults, set just before it starts InstantTab and cleared once native Cmd+Tab is known to be back, after any exit it saw. At quit and on termination signals it restores while the marker is set or InstantTab is still running or stopping, even if it was just turned off, because the host exits before it learns how the tool ended. At launch it restores only while the marker is still set, left by a host that crashed or was killed, or after stopping a leftover InstantTab tool or the standalone InstantTab app.

## Sources

- AltTab source: https://github.com/lwouis/alt-tab-macos (commit 56891e0, v11.7.1), issues 171, 4507, 4959, 5109, 5177, 5585, 5721, 5766, 5786, 5861, 5900, 5911, 6028, 6051, 6053, 6064
- yabai: https://github.com/koekeishiya/yabai (window_manager.c, space.c, display.c)
- AeroSpace: https://github.com/nikitabobko/AeroSpace
- DockDoor: https://github.com/ejbills/DockDoor (KeybindHelper.swift, EventTapThread.swift, issue 1589)
- Hammerspoon: https://github.com/Hammerspoon/hammerspoon (issue 1936, hs.window.filter docs)
- Karabiner-Elements: https://github.com/pqrs-org/Karabiner-Elements (select_input_source, input_source_if)
- Activation changes in macOS 14: https://developer.apple.com/videos/play/wwdc2023/10054/
- TCC and stable signing: https://developer.apple.com/forums/thread/730043
- Event tap permissions: https://developer.apple.com/forums/thread/707680
- Tap and re-signing race: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/
- Sequoia screen recording prompts: https://www.macrumors.com/2024/10/07/apple-screen-recording-popup-update/
- Glass cost measurement: https://github.com/ggbond268/MacTools/pull/426
- macOS 27 release: https://9to5mac.com/2026/09/09/apple-confirms-macos-27-golden-gate-launch-date-september-14/
- Display UUID instability: https://github.com/jakehilborn/displayplacer/issues/89
- Competitor survey: https://alt-tab.app/pricing, https://manytricks.com/witch/help/qanda.html, https://contexts.co/, https://noteifyapp.com/command-tab-plus/, https://github.com/Sanyam-G/switch, https://github.com/rokartur/BetterCmdTab
