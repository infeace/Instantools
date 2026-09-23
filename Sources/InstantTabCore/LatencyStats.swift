/// A fixed-size ring of latency samples in nanoseconds with nearest-rank percentiles.
public struct LatencyStats: Sendable {
    public let capacity: Int
    private var samples: [UInt64] = []
    private var nextIndex = 0

    public init(capacity: Int = 256) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    public var count: Int { samples.count }

    public mutating func record(_ nanoseconds: UInt64) {
        if samples.count < capacity {
            samples.append(nanoseconds)
        } else {
            samples[nextIndex] = nanoseconds
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    /// Nearest-rank percentile for `p` in 0...100, or nil when there are no samples.
    public func percentile(_ p: Double) -> UInt64? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public var summary: String {
        guard let p50 = percentile(50), let p95 = percentile(95) else { return "no samples" }
        return "p50 \(Self.milliseconds(p50)) p95 \(Self.milliseconds(p95)) (n=\(count))"
    }

    static func milliseconds(_ nanoseconds: UInt64) -> String {
        let tenths = (nanoseconds + 50_000) / 100_000
        return "\(tenths / 10).\(tenths % 10)ms"
    }
}
