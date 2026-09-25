public enum SwitcherFilter {
    /// `targets` nil means every display. Runs on every key press.
    public static func entries(
        for snapshot: Snapshot,
        windowlessApps: Config.Placement,
        exclusions: ExclusionMatcher,
        appKeys: AppKeyMap = AppKeyMap([]),
        displays: [Display],
        targets: Set<UInt32>?
    ) -> [SwitcherEntry] {
        let windowsByPid = Dictionary(grouping: snapshot.windows, by: \.pid)

        var listed: [SwitcherEntry] = []
        var trailing: [SwitcherEntry] = []
        for app in snapshot.apps {
            let windows = windowsByPid[app.pid] ?? []
            if exclusions.isExcluded(bundleId: app.bundleId, hasWindows: !windows.isEmpty) { continue }

            func entry(_ windowId: UInt32?) -> SwitcherEntry {
                SwitcherEntry(pid: app.pid, name: app.name, windowId: windowId, key: appKeys.key(for: app.bundleId))
            }

            if let targets {
                if let window = windows.first(where: { window in
                    DisplayMapping.display(for: window.frame, in: displays).map(targets.contains) ?? false
                }) {
                    listed.append(entry(window.id))
                    continue
                }
                if !windows.isEmpty { continue }
                // Hidden and minimized apps stay with the display they were last seen on.
                if let last = snapshot.lastDisplayByPid[app.pid], displays.contains(where: { $0.id == last }), !targets.contains(last) {
                    continue
                }
            } else if let window = windows.first {
                listed.append(entry(window.id))
                continue
            }

            switch windowlessApps {
            case .show: listed.append(entry(nil))
            case .end: trailing.append(entry(nil))
            case .hide: break
            }
        }
        return listed + trailing
    }

    /// Like native Cmd+Tab: forward starts on the previous app, backward on the last one.
    public static func initialIndex(count: Int, firstIsFrontmost: Bool, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        if reverse { return count - 1 }
        return firstIsFrontmost && count > 1 ? 1 : 0
    }
}
