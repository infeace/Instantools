public struct MRUList: Sendable, Equatable {
    public private(set) var order: [Int32] = []

    public init(_ order: [Int32] = []) {
        for pid in order { append(pid) }
    }

    public mutating func touch(_ pid: Int32) {
        remove(pid)
        order.insert(pid, at: 0)
    }

    public mutating func append(_ pid: Int32) {
        guard !order.contains(pid) else { return }
        order.append(pid)
    }

    public mutating func remove(_ pid: Int32) {
        order.removeAll { $0 == pid }
    }

    public mutating func sync(with live: [Int32]) {
        let liveSet = Set(live)
        order.removeAll { !liveSet.contains($0) }
        for pid in live { append(pid) }
    }
}
