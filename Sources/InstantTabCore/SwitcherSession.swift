public struct SwitcherSession: Sendable, Equatable {
    public private(set) var entries: [SwitcherEntry]
    public private(set) var selectedIndex: Int

    public init(entries: [SwitcherEntry], selectedIndex: Int) {
        self.entries = entries
        self.selectedIndex = entries.isEmpty ? 0 : min(max(selectedIndex, 0), entries.count - 1)
    }

    public var selected: SwitcherEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    public mutating func move(by delta: Int) {
        guard !entries.isEmpty else { return }
        let count = entries.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// Keeps the selected app selected when it is still listed.
    public mutating func reconcile(with newEntries: [SwitcherEntry]) {
        let selectedPid = selected?.pid
        entries = newEntries
        if let selectedPid, let index = newEntries.firstIndex(where: { $0.pid == selectedPid }) {
            selectedIndex = index
        } else {
            selectedIndex = newEntries.isEmpty ? 0 : min(selectedIndex, newEntries.count - 1)
        }
    }
}
