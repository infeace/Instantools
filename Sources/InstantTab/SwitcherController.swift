import AppKit
import InstantTabCore

@MainActor
final class SwitcherController {
    private let tracker: WindowTracker
    private let displays: Displays
    private let panel: SwitcherPanel
    private let focuser = Focuser()
    private let probe = FrameProbe()
    private var taps: InputTaps?

    var config = Config() {
        didSet { resolveGroups() }
    }
    private var groups = ResolvedGroups([], displays: [])
    private var session: SwitcherSession?
    private var sessionDisplay: UInt32?
    private var sessionTargets: Set<UInt32>?
    private var pressNanoseconds: UInt64 = 0
    private var showWork: DispatchWorkItem?
    private var releasePoll: Timer?
    private var lastChoice: (pid: Int32, previousFrontmost: Int32?, nanoseconds: UInt64)?
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    /// Key press to first frame of the panel, minus the show delay.
    private(set) var latency = LatencyStats()

    init(tracker: WindowTracker, displays: Displays, icons: IconCache) {
        self.tracker = tracker
        self.displays = displays
        panel = SwitcherPanel(icons: icons)
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

    func attach(_ taps: InputTaps) {
        self.taps = taps
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
        } else {
            begin(reverse: action == .backward, eventNanoseconds: eventNanoseconds)
        }
    }

    func commandReleased() {
        guard session != nil else { return }
        commit()
    }

    func sessionKey(_ key: SessionKey) {
        guard let selected = session?.selected else { return }
        // Nothing happens to an app you cannot see yet.
        if key != .cancel { showNow() }
        switch key {
        case .cancel: end()
        case .previous: changeSelection { $0.move(by: -1) }
        case .next: changeSelection { $0.move(by: 1) }
        case .quit: quit(selected.pid)
        case .hide: hide(selected.pid)
        }
    }

    func modelChanged() {
        guard var active = session else { return }
        let entries = currentEntries(targets: sessionTargets)
        guard entries != active.entries else { return }
        guard !entries.isEmpty else { return end() }
        active.reconcile(with: entries)
        session = active
        if let screen = displays.screen(for: sessionDisplay) {
            panel.update(entries: active.entries, selected: active.selectedIndex, on: screen, iconSize: config.iconSize)
        }
    }

    private func changeSelection(_ change: (inout SwitcherSession) -> Void) {
        guard var active = session else { return }
        change(&active)
        session = active
        panel.select(active.selectedIndex)
    }

    /// Like native Cmd+Tab, which never quits Finder. The app leaves the list once it has quit, or stays if it
    /// asks to save first.
    private func quit(_ pid: Int32) {
        guard pid != ownPid else {
            end()
            return NSApp.terminate(nil)
        }
        DispatchQueue.global(qos: .userInteractive).async {
            guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier != "com.apple.finder" else { return }
            app.terminate()
        }
    }

    private func hide(_ pid: Int32) {
        guard pid != ownPid else { return NSApp.hide(nil) }
        DispatchQueue.global(qos: .userInteractive).async {
            NSRunningApplication(processIdentifier: pid)?.hide()
        }
    }

    private func begin(reverse: Bool, eventNanoseconds: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        // The key event's own timestamp, when plausible, makes latency include queueing.
        pressNanoseconds = eventNanoseconds > 0 && eventNanoseconds <= now && now - eventNanoseconds < 1_000_000_000
            ? eventNanoseconds : now

        let frontmost = effectiveFrontmost(now: now)
        let mouseDisplay = displays.mouseDisplayId()
        let focusedDisplay = config.scope == .focusedDisplay
            ? DisplayScope.focusedDisplay(in: tracker.snapshot, frontmostPid: frontmost, displays: displays.displays) : nil
        let targets = DisplayScope.targets(for: config.scope, groups: groups, mouseDisplay: mouseDisplay, focusedDisplay: focusedDisplay)
        let entries = currentEntries(targets: targets)
        guard !entries.isEmpty else { return }
        let index = SwitcherFilter.initialIndex(count: entries.count, firstIsFrontmost: entries[0].pid == frontmost, reverse: reverse)
        session = SwitcherSession(entries: entries, selectedIndex: index)
        sessionDisplay = focusedDisplay ?? mouseDisplay
        sessionTargets = targets

        // A very quick tap can release Cmd before this runs: switch without drawing.
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else { return commit() }

        taps?.setSessionActive(true)
        startReleasePoll()
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
        guard let active = session, let screen = displays.screen(for: sessionDisplay) else { return }
        panel.show(entries: active.entries, selected: active.selectedIndex, on: screen, iconSize: config.iconSize)
        if measured { probe.arm(view: panel.view, startNanoseconds: pressNanoseconds + UInt64(config.showDelayMs) * 1_000_000) }
    }

    private func showNow() {
        guard let showWork else { return }
        showWork.cancel()
        self.showWork = nil
        showPanel(measured: false)
    }

    private func commit() {
        guard let entry = session?.selected else { return end() }
        focuser.focus(entry)
        lastChoice = (entry.pid, NSWorkspace.shared.frontmostApplication?.processIdentifier, DispatchTime.now().uptimeNanoseconds)
        end()
        tracker.noteChosen(entry.pid)
    }

    private func end() {
        session = nil
        sessionDisplay = nil
        sessionTargets = nil
        showWork?.cancel()
        showWork = nil
        releasePoll?.invalidate()
        releasePoll = nil
        panel.hide()
        taps?.setSessionActive(false)
    }

    /// Backstop for the modifier tap: catches a missed release, and works alone before permissions exist.
    private func startReleasePoll() {
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else { return }
                self?.commandReleased()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releasePoll = timer
    }

    private func currentEntries(targets: Set<UInt32>?) -> [SwitcherEntry] {
        SwitcherFilter.entries(for: tracker.snapshot, config: config, displays: displays.displays, targets: targets)
    }
}
