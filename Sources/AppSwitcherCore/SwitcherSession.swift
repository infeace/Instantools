/// One Cmd+Tab, from the press until it switches or is cancelled. The list can be empty, when nothing is on
/// the displays in scope or the snapshot is stale, and the keys still work, so an app key reaches its app.
public struct SwitcherSession: Sendable, Equatable {
    public private(set) var entries: [SwitcherEntry]
    public private(set) var selectedIndex: Int
    private var frontmostPid: Int32?
    private var reverse = false

    public init(entries: [SwitcherEntry], selectedIndex: Int) {
        self.entries = entries
        self.selectedIndex = entries.isEmpty ? 0 : min(max(selectedIndex, 0), entries.count - 1)
    }

    /// Starts where native Cmd+Tab does: on the app after the frontmost one, or on the last with Shift.
    public init(entries: [SwitcherEntry], frontmostPid: Int32?, reverse: Bool) {
        let firstIsFrontmost = entries.first.map { $0.pid == frontmostPid } ?? false
        self.init(entries: entries, selectedIndex: SwitcherFilter.initialIndex(count: entries.count, firstIsFrontmost: firstIsFrontmost, reverse: reverse))
        self.frontmostPid = frontmostPid
        self.reverse = reverse
    }

    public var selected: SwitcherEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    public mutating func move(by delta: Int) {
        guard !entries.isEmpty else { return }
        let count = entries.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    public mutating func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// A list that was empty starts where a new Cmd+Tab would.
    public mutating func reconcile(with newEntries: [SwitcherEntry]) {
        if entries.isEmpty {
            self = SwitcherSession(entries: newEntries, frontmostPid: frontmostPid, reverse: reverse)
            return
        }
        let selectedPid = selected?.pid
        entries = newEntries
        if let selectedPid, let index = newEntries.firstIndex(where: { $0.pid == selectedPid }) {
            selectedIndex = index
        } else {
            selectedIndex = newEntries.isEmpty ? 0 : min(selectedIndex, newEntries.count - 1)
        }
    }

    public enum Action: Equatable, Sendable {
        case none
        case moved
        case cancel
        case quit(pid: Int32)
        case hide(pid: Int32)
        /// Switches to the app, then opens App Exposé for it.
        case expose(SwitcherEntry)
        case switchTo(SwitcherEntry)
        case launch(bundleId: String)
    }

    /// What a key pressed while the switcher is open does. Keys that act on the selected app do nothing
    /// without one.
    public mutating func handle(_ key: SessionKey, appKeys: AppKeyMap, snapshot: Snapshot) -> Action {
        switch key {
        case .cancel:
            return .cancel
        case .previous, .next:
            guard !entries.isEmpty else { return .none }
            move(by: key == .previous ? -1 : 1)
            return .moved
        case .quit:
            return selected.map { .quit(pid: $0.pid) } ?? .none
        case .hide:
            return selected.map { .hide(pid: $0.pid) } ?? .none
        case .expose:
            return selected.map { .expose($0) } ?? .none
        case .app(let character):
            switch SwitcherFilter.target(forAppKey: character, appKeys: appKeys, in: snapshot, listed: entries) {
            case .running(let entry): return .switchTo(entry)
            case .launch(let bundleId): return .launch(bundleId: bundleId)
            case nil: return .none
            }
        }
    }
}
