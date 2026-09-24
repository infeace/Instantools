import AppKit
import InstantTabCore

/// Runs a Cmd+Tab session: picks the entries and the starting selection from the snapshot at key down,
/// draws the panel after the configured delay, and focuses the selection when Cmd is released.
@MainActor
final class SwitcherController {
    private let tracker: WindowTracker
    private let displays: Displays
    private let icons: IconCache
    private let panel = SwitcherPanel()
    private let focuser = Focuser()
    private let probe = FrameProbe()
    private var taps: InputTaps?

    var config = Config()
    private var session: SwitcherSession?
    private var sessionDisplay: UInt32?
    private var pressNanoseconds: UInt64 = 0
    private var showWork: DispatchWorkItem?
    private var releasePoll: Timer?
    private var lastChosen: (pid: Int32, nanoseconds: UInt64)?

    /// Key press to first frame of the panel, minus the configured show delay.
    private(set) var latency = LatencyStats()

    init(tracker: WindowTracker, displays: Displays, icons: IconCache) {
        self.tracker = tracker
        self.displays = displays
        self.icons = icons
        panel.onShown = { [weak self] view in
            guard let self else { return }
            probe.arm(view: view, startNanoseconds: pressNanoseconds + UInt64(config.showDelayMs) * 1_000_000)
        }
        probe.onMeasured = { [weak self] nanoseconds in
            self?.latency.record(nanoseconds)
            Diagnostics.log.notice("press to frame \(LatencyStats.milliseconds(nanoseconds), privacy: .public)")
        }
    }

    func attach(_ taps: InputTaps) {
        self.taps = taps
    }

    func warmUp() {
        let entries = currentEntries(mouseDisplay: displays.mouseDisplayId())
        panel.warmUp(entries: entries, icons: icons, on: displays.screen(for: displays.mouseDisplayId()), iconSize: config.iconSize)
    }

    // MARK: Input

    func hotKeyPressed(_ action: HotKeys.Action, eventNanoseconds: UInt64) {
        let delta = action == .forward ? 1 : -1
        if var active = session {
            active.move(by: delta)
            session = active
            panel.select(active.selectedIndex)
            return
        }
        begin(reverse: action == .backward, eventNanoseconds: eventNanoseconds)
    }

    func commandReleased() {
        guard session != nil else { return }
        commit()
    }

    func sessionKey(_ key: SessionKey) {
        guard var active = session else { return }
        switch key {
        case .cancel:
            end()
        case .previous, .next:
            active.move(by: key == .next ? 1 : -1)
            session = active
            panel.select(active.selectedIndex)
        }
    }

    /// The snapshot changed during a session: keep the selection and redraw if needed.
    func modelChanged() {
        guard var active = session else { return }
        let entries = currentEntries(mouseDisplay: sessionDisplay)
        guard entries != active.entries else { return }
        guard !entries.isEmpty else { return end() }
        active.reconcile(with: entries)
        session = active
        if let screen = displays.screen(for: sessionDisplay) {
            panel.update(entries: active.entries, selected: active.selectedIndex, icons: icons, on: screen, iconSize: config.iconSize)
        }
    }

    // MARK: Session

    private func begin(reverse: Bool, eventNanoseconds: UInt64) {
        let now = MachClock.nanoseconds(fromTicks: MachClock.now())
        // Prefer the key event's own timestamp when it is plausible, so latency includes queueing.
        pressNanoseconds = eventNanoseconds > 0 && eventNanoseconds <= now && now - eventNanoseconds < 1_000_000_000
            ? eventNanoseconds : now

        let mouseDisplay = displays.mouseDisplayId()
        let entries = currentEntries(mouseDisplay: mouseDisplay)
        guard !entries.isEmpty else { return }
        // Right after a switch, macOS may not report the new frontmost app yet.
        let recentlyChosen = lastChosen.flatMap { now - $0.nanoseconds < 1_000_000_000 ? $0.pid : nil }
        let frontmost = recentlyChosen ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        let index = SwitcherFilter.initialIndex(count: entries.count, firstIsFrontmost: entries[0].pid == frontmost, reverse: reverse)
        session = SwitcherSession(entries: entries, selectedIndex: index)
        sessionDisplay = mouseDisplay

        // Cmd can already be up if the tap was very quick: switch without drawing.
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else { return commit() }

        taps?.setSessionActive(true)
        startReleasePoll()
        if config.showDelayMs == 0 {
            showPanel()
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.showPanel() }
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.showDelayMs), execute: work)
        }
        tracker.refreshWindows()
    }

    private func showPanel() {
        guard let active = session, let screen = displays.screen(for: sessionDisplay) else { return }
        panel.show(entries: active.entries, selected: active.selectedIndex, icons: icons, on: screen, iconSize: config.iconSize)
    }

    private func commit() {
        guard let entry = session?.selected else { return end() }
        focuser.focus(entry)
        lastChosen = (entry.pid, MachClock.nanoseconds(fromTicks: MachClock.now()))
        end()
        tracker.noteChosen(entry.pid)
    }

    private func end() {
        session = nil
        sessionDisplay = nil
        showWork?.cancel()
        showWork = nil
        releasePoll?.invalidate()
        releasePoll = nil
        panel.hide()
        taps?.setSessionActive(false)
    }

    /// Backstop for the modifier tap: catches a missed release, or works alone before permissions are granted.
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

    private func currentEntries(mouseDisplay: UInt32?) -> [SwitcherEntry] {
        SwitcherFilter.entries(for: tracker.snapshot, config: config, displays: displays.displays, mouseDisplay: mouseDisplay)
    }
}
