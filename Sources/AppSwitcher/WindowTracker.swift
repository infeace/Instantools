import AppKit
import AppSwitcherCore
import AppSwitcherKit

/// Keeps the snapshot current so the key press never queries anything. Window changes inside the active
/// app are not observed, so each key press also starts a refresh.
@MainActor
final class WindowTracker {
    private(set) var snapshot = Snapshot()
    var onChange: (() -> Void)?

    private let displays: Displays
    private let queue = DispatchQueue(label: "com.infeace.Instantools.windows", qos: .userInitiated)
    private var mru = MRUList()
    private var appsByPid: [Int32: RunningApp] = [:]
    private var windows: [WindowRecord] = []
    /// The windows of listed apps on a connected display. Placed again only when the windows, the apps or
    /// the displays change, so choosing an app only reorders.
    private var placedWindows: [WindowRecord] = []
    private var lastDisplayByPid: [Int32: UInt32] = [:]
    private var refreshInFlight = false
    private var settleRefresh: DispatchWorkItem?
    private var refreshPending = false
    private var appsObservation: NSKeyValueObservation?

    init(displays: Displays) {
        self.displays = displays
    }

    func start() {
        reloadApps(publishing: false)
        windows = Self.queryWindows() ?? []
        seedOrder()
        placeWindows()
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

    /// Which windows are on a display, and so which apps are windowless, depends on the displays. macOS can
    /// move the windows of a removed display after this, and window moves are not observed, so they are read
    /// once more when that has settled.
    func displaysChanged() {
        placeWindows()
        publish()
        refreshWindows()
        settleRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.settleRefresh = nil
                self?.refreshWindows()
            }
        }
        settleRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: work)
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
                    if let windows, windows != self.windows {
                        self.windows = windows
                        self.placeWindows()
                        self.publish()
                    }
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
        // Instantools is listed only while its Settings window is open, which makes it a regular app.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            apps[pid] = RunningApp(
                pid: pid, bundleId: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "App"
            )
            live.append(pid)
        }
        appsByPid = apps
        mru.sync(with: live)
        lastDisplayByPid = lastDisplayByPid.filter { apps[$0.key] != nil }
        placeWindows()
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

    private func placeWindows() {
        let placed = DisplayMapping.placed(windows.filter { appsByPid[$0.pid] != nil }, on: displays.displays)
        placedWindows = placed.windows
        lastDisplayByPid.merge(placed.displayByPid) { _, new in new }
    }

    private func publish() {
        let next = Snapshot(apps: mru.order.compactMap { appsByPid[$0] }, windows: placedWindows, lastDisplayByPid: lastDisplayByPid)
        guard next != snapshot else { return }
        snapshot = next
        onChange?()
    }

    /// On-screen, normal-level windows front to back (the panel is above normal level). About 1ms. Nil,
    /// which keeps the last list, when the list cannot be read or while Mission Control or App Exposé is up,
    /// since it takes every window off screen without closing any.
    nonisolated private static func queryWindows() -> [WindowRecord]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        if dockCoversADisplay(list) { return nil }
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

    nonisolated static func dockOverlayIsUp() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return dockCoversADisplay(list)
    }

    /// Mission Control and App Exposé are Dock windows at about the Dock's level that cover a whole display.
    /// The Dock itself sits at that level too but never covers a display.
    nonisolated private static func dockCoversADisplay(_ list: [[String: Any]]) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
        let displays = ids.prefix(Int(count)).map(CGDisplayBounds)
        return list.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "Dock",
                  let layer = info[kCGWindowLayer as String] as? Int, (18...20).contains(layer),
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsInfo)
            else { return false }
            return displays.contains(frame)
        }
    }
}
