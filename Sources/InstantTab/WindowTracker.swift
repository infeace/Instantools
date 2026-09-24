import AppKit
import InstantTabCore

/// Keeps the snapshot current so the key press never queries anything. Window changes inside the active
/// app are not observed, so each key press also starts a refresh.
@MainActor
final class WindowTracker {
    private(set) var snapshot = Snapshot()
    var onChange: (() -> Void)?

    private let displays: Displays
    private let queue = DispatchQueue(label: "com.infeace.InstantTab.windows", qos: .userInitiated)
    private var mru = MRUList()
    private var appsByPid: [Int32: RunningApp] = [:]
    private var windows: [WindowRecord] = []
    private var lastDisplayByPid: [Int32: UInt32] = [:]
    private var refreshInFlight = false
    private var refreshPending = false
    private var appsObservation: NSKeyValueObservation?

    init(displays: Displays) {
        self.displays = displays
    }

    func start() {
        reloadApps(publishing: false)
        windows = Self.queryWindows()
        seedOrder()
        publish()

        appsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.reload() }
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            // Menu bar apps activate too, but are never listed.
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.appsByPid[pid] == nil { self.reloadApps() }
                self.mru.touch(pid)
                self.publish()
                self.refreshWindows()
            }
        }
        for name in [
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    func reload() {
        reloadApps()
        refreshWindows()
    }

    /// Reorders as soon as an app is chosen, so a quick second Cmd+Tab toggles back even before macOS
    /// reports the activation.
    func noteChosen(_ pid: Int32) {
        mru.touch(pid)
        publish()
    }

    func refreshWindows() {
        guard !refreshInFlight else {
            refreshPending = true
            return
        }
        refreshInFlight = true
        queue.async {
            let windows = Self.queryWindows()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.refreshInFlight = false
                    let changed = windows != self.windows
                    self.windows = windows
                    if changed { self.publish() }
                    if self.refreshPending {
                        self.refreshPending = false
                        self.refreshWindows()
                    }
                }
            }
        }
    }

    private func reloadApps(publishing: Bool = true) {
        var apps: [Int32: RunningApp] = [:]
        var live: [Int32] = []
        // InstantTab itself is listed only while Settings is open, which makes it a regular app.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            apps[pid] = RunningApp(
                pid: pid, bundleId: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "App",
                isHidden: app.isHidden
            )
            live.append(pid)
        }
        appsByPid = apps
        mru.sync(with: live)
        lastDisplayByPid = lastDisplayByPid.filter { apps[$0.key] != nil }
        if publishing { publish() }
    }

    private func seedOrder() {
        var order: [Int32] = []
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { order.append(front) }
        order += windows.map(\.pid)
        let byLaunch = NSWorkspace.shared.runningApplications
            .filter { appsByPid[$0.processIdentifier] != nil }
            .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
            .map(\.processIdentifier)
        order += byLaunch
        mru = MRUList(order.filter { appsByPid[$0] != nil })
    }

    private func publish() {
        let visible = windows.filter { appsByPid[$0.pid] != nil }
        let displayList = displays.displays
        for window in visible.reversed() {
            if let display = DisplayMapping.display(for: window.frame, in: displayList) {
                lastDisplayByPid[window.pid] = display
            }
        }
        let next = Snapshot(apps: mru.order.compactMap { appsByPid[$0] }, windows: visible, lastDisplayByPid: lastDisplayByPid)
        guard next != snapshot else { return }
        snapshot = next
        onChange?()
    }

    /// On-screen, normal-level windows front to back (the panel is above normal level). About 1ms.
    nonisolated private static func queryWindows() -> [WindowRecord] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsInfo),
                  // Tiny layer-0 windows are helpers and overlays, not windows a person would switch to.
                  frame.width >= 40, frame.height >= 40
            else { return nil }
            return WindowRecord(id: id, pid: pid, frame: frame)
        }
    }
}
