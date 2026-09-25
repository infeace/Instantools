import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsKit
import SkyLightShim

@MainActor
final class SwitcherController {
    private let tracker: WindowTracker
    private let displays: Displays
    private let panel: SwitcherPanel
    private let taps: InputTaps
    private let focuser = Focuser()
    private let probe: FrameProbe

    var config = Config() {
        didSet {
            exclusions = ExclusionMatcher(config.exclude)
            appKeys = AppKeyMap(config.appKeys)
            panel.prepareBadges(for: config.appKeys.map(\.key))
            resolveGroups()
        }
    }
    private var exclusions = ExclusionMatcher([])
    private var appKeys = AppKeyMap([])
    private var groups = ResolvedGroups([], displays: [])
    private var session: SwitcherSession?
    private var sessionDisplay: UInt32?
    private var sessionTargets: Set<UInt32>?
    private var pressNanoseconds: UInt64 = 0
    /// The time of the release that ended the last session, when the tap saw it. Zero after any other end,
    /// whose time on main could be later than a genuine new Cmd+Tab while main is busy.
    private var releaseNanoseconds: UInt64 = 0
    private var showWork: DispatchWorkItem?
    /// Set once the show delay has passed, so a list that was empty until then is drawn when it fills in.
    private var panelDue = false
    private var releasePoll: Timer?
    private var exposeWait: Timer?
    /// Set when the switcher opens App Exposé, so the next switch closes it.
    private var exposeOpened = false
    private var lastChoice: (pid: Int32, previousFrontmost: Int32?, nanoseconds: UInt64)?

    /// Key press to the display frame the panel is drawn for, minus the show delay.
    private(set) var latency = LatencyStats()

    init(tracker: WindowTracker, displays: Displays, icons: IconCache, taps: InputTaps) {
        self.tracker = tracker
        self.displays = displays
        self.taps = taps
        panel = SwitcherPanel(icons: icons)
        probe = FrameProbe(view: panel.view)
        panel.onHover = { [weak self] index in self?.changeSelection { $0.select(index) } }
        panel.onClick = { [weak self] index in
            self?.changeSelection { $0.select(index) }
            self?.commit()
        }
        probe.onMeasured = { [weak self] nanoseconds in
            self?.latency.record(nanoseconds)
            Diagnostics.log.notice("press to frame \(LatencyStats.milliseconds(nanoseconds), privacy: .public)")
        }
    }

    func resolveGroups() {
        groups = ResolvedGroups(config.displayGroups, displays: displays.displays)
    }

    func warmUp() {
        panel.warmUp(entries: currentEntries(targets: nil), on: displays.screen(for: displays.mouseDisplayId()), iconSize: config.iconSize)
    }

    func hotKeyPressed(_ action: HotKeys.Action, eventNanoseconds: UInt64) {
        if session != nil {
            changeSelection { $0.move(by: action == .forward ? 1 : -1) }
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        // The key event's own timestamp, when plausible, makes latency include queueing.
        let pressed = Self.plausible(eventNanoseconds, now: now)
        // The release reaches main from the tap thread and a Tab through the run loop, in either order. A
        // Tab pressed before the release that ended the session would otherwise start a new one when it
        // arrives late, which switches straight back.
        if let pressed, pressed < releaseNanoseconds { return }
        begin(reverse: action == .backward, pressNanoseconds: pressed ?? now, now: now)
    }

    /// `eventNanoseconds` is the release event's own time from the tap, or nil from the poll.
    func commandReleased(eventNanoseconds: UInt64?) {
        guard session != nil else { return }
        commit()
        if let eventNanoseconds, let released = Self.plausible(eventNanoseconds, now: DispatchTime.now().uptimeNanoseconds) {
            releaseNanoseconds = released
        }
    }

    /// Event times share DispatchTime's clock.
    private static func plausible(_ nanoseconds: UInt64, now: UInt64) -> UInt64? {
        nanoseconds > 0 && nanoseconds <= now && now - nanoseconds < 1_000_000_000 ? nanoseconds : nil
    }

    func sessionKey(_ key: SessionKey) {
        guard var active = session else { return }
        if key.showsPanel { showNow() }
        let action = active.handle(key, appKeys: appKeys, snapshot: tracker.snapshot)
        session = active
        switch action {
        case .none: break
        case .moved: panel.select(active.selectedIndex)
        case .cancel: end()
        case .quit(let pid): quit(pid)
        case .hide(let pid): hide(pid)
        case .expose(let entry): expose(entry)
        // Switches on the key press, without waiting for Cmd to be released. Within the show delay nothing
        // is drawn, like a quick Cmd+Tab.
        case .switchTo(let entry): commit(entry)
        case .launch(let bundleId):
            end()
            focuser.launch(bundleId: bundleId, closingExpose: takeExposeToClose())
        }
    }

    /// Like native Cmd+Tab. App Exposé shows the frontmost app, so it waits up to a second for the switch
    /// to land.
    private func expose(_ entry: SwitcherEntry) {
        commit(entry)
        exposeWait?.invalidate()
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let landed = NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid
                guard landed || DispatchTime.now().uptimeNanoseconds > deadline else { return }
                self?.exposeWait?.invalidate()
                self?.exposeWait = nil
                if landed { self?.exposeOpened = SkyLight.toggleAppExpose() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        exposeWait = timer
    }

    func modelChanged() {
        guard var active = session else { return }
        let entries = currentEntries(targets: sessionTargets)
        guard entries != active.entries else { return }
        active.reconcile(with: entries)
        session = active
        guard panelDue, let screen = displays.screen(for: sessionDisplay) else { return }
        if active.entries.isEmpty {
            panel.hide()
        } else if panel.isVisible {
            panel.update(entries: active.entries, selected: active.selectedIndex, on: screen, iconSize: config.iconSize)
        } else {
            panel.show(entries: active.entries, selected: active.selectedIndex, on: screen, iconSize: config.iconSize)
        }
    }

    private func changeSelection(_ change: (inout SwitcherSession) -> Void) {
        guard var active = session else { return }
        change(&active)
        session = active
        panel.select(active.selectedIndex)
    }

    /// Like native Cmd+Tab, which never quits Finder. The app leaves the list once it has quit, or stays if it
    /// asks to save first. Both calls message the app, so they stay off the main thread.
    private func quit(_ pid: Int32) {
        DispatchQueue.global(qos: .userInteractive).async {
            guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier != "com.apple.finder" else { return }
            app.terminate()
        }
    }

    private func hide(_ pid: Int32) {
        DispatchQueue.global(qos: .userInteractive).async {
            NSRunningApplication(processIdentifier: pid)?.hide()
        }
    }

    private func begin(reverse: Bool, pressNanoseconds: UInt64, now: UInt64) {
        // A new switch replaces an App Exposé still waiting for the last one to land.
        exposeWait?.invalidate()
        exposeWait = nil
        self.pressNanoseconds = pressNanoseconds

        let frontmost = effectiveFrontmost(now: now)
        let mouseDisplay = displays.mouseDisplayId()
        let focusedDisplay = config.scope == .focusedDisplay
            ? DisplayScope.focusedDisplay(in: tracker.snapshot, frontmostPid: frontmost, displays: displays.displays) : nil
        let targets = DisplayScope.targets(for: config.scope, groups: groups, mouseDisplay: mouseDisplay, focusedDisplay: focusedDisplay)
        let entries = currentEntries(targets: targets)
        session = SwitcherSession(entries: entries, frontmostPid: frontmost, reverse: reverse)
        sessionDisplay = focusedDisplay ?? mouseDisplay
        sessionTargets = targets

        // A very quick tap can release Cmd before this runs: switch without drawing.
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else {
            // No notification reports a window opened in the app already in front, so a stale snapshot can
            // list nothing, and without a refresh every quick tap would find nothing.
            if entries.isEmpty { tracker.refreshWindows() }
            return commit()
        }

        if config.showDelayMs == 0 {
            showPanel(measured: true)
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.showWork = nil
                    self?.showPanel(measured: true)
                }
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.showDelayMs), execute: work)
        }
        // After a show with no delay, since enabling the tap is a WindowServer call. The poll covers a release
        // in between.
        taps.setSessionActive(true)
        startReleasePoll()
        tracker.refreshWindows()
    }

    /// Right after a switch macOS may still report the old frontmost app, so the choice stands in for it.
    private func effectiveFrontmost(now: UInt64) -> Int32? {
        let reported = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let lastChoice, now - lastChoice.nanoseconds < 1_000_000_000, reported == lastChoice.previousFrontmost else {
            return reported
        }
        return lastChoice.pid
    }

    /// Only a show at the configured delay is measured, since an early one would read as impossibly fast.
    private func showPanel(measured: Bool) {
        panelDue = true
        guard let active = session, !active.entries.isEmpty, let screen = displays.screen(for: sessionDisplay) else { return }
        panel.show(entries: active.entries, selected: active.selectedIndex, on: screen, iconSize: config.iconSize)
        if measured { probe.arm(startNanoseconds: pressNanoseconds + UInt64(config.showDelayMs) * 1_000_000) }
    }

    private func showNow() {
        guard let showWork else { return }
        showWork.cancel()
        self.showWork = nil
        showPanel(measured: false)
    }

    private func commit(_ chosen: SwitcherEntry? = nil) {
        guard let entry = chosen ?? session?.selected else { return end() }
        focuser.focus(entry, frame: windowFrame(of: entry), closingExpose: takeExposeToClose())
        lastChoice = (entry.pid, NSWorkspace.shared.frontmostApplication?.processIdentifier, DispatchTime.now().uptimeNanoseconds)
        end()
        tracker.noteChosen(entry.pid)
    }

    /// For raising the window by its frame when AX cannot tell window ids.
    private func windowFrame(of entry: SwitcherEntry) -> CGRect? {
        guard let windowId = entry.windowId else { return nil }
        return tracker.snapshot.windows.first { $0.id == windowId }?.frame
    }

    private func takeExposeToClose() -> Bool {
        defer { exposeOpened = false }
        return exposeOpened
    }

    private func end() {
        releaseNanoseconds = 0
        session = nil
        sessionDisplay = nil
        sessionTargets = nil
        showWork?.cancel()
        showWork = nil
        panelDue = false
        releasePoll?.invalidate()
        releasePoll = nil
        panel.hide()
        taps.setSessionActive(false)
    }

    /// Backstop for the modifier tap: catches a missed release, and works alone before permissions exist.
    private func startReleasePoll() {
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else { return }
                self?.commandReleased(eventNanoseconds: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releasePoll = timer
    }

    /// What Cmd+Tab would list from every display, for the Settings preview.
    func previewEntries() -> [SwitcherEntry] {
        currentEntries(targets: nil)
    }

    private func currentEntries(targets: Set<UInt32>?) -> [SwitcherEntry] {
        SwitcherFilter.entries(
            for: tracker.snapshot, windowlessApps: config.windowlessApps, exclusions: exclusions, appKeys: appKeys,
            displays: displays.displays, targets: targets
        )
    }
}
