public struct LatencyStats: Sendable, Equatable {
    public let capacity: Int
    private var samples: [UInt64] = []
    private var nextIndex = 0

    public init(capacity: Int = 256) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    public var count: Int { samples.count }

    public var chronological: [UInt64] {
        samples.count < capacity ? samples : Array(samples[nextIndex...] + samples[..<nextIndex])
    }

    public mutating func record(_ nanoseconds: UInt64) {
        if samples.count < capacity {
            samples.append(nanoseconds)
        } else {
            samples[nextIndex] = nanoseconds
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    /// Nearest-rank percentile for `p` in 0...100.
    public func percentile(_ p: Double) -> UInt64? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public static func milliseconds(_ nanoseconds: UInt64) -> String {
        let tenths = (nanoseconds + 50_000) / 100_000
        return "\(tenths / 10).\(tenths % 10)ms"
    }
}
